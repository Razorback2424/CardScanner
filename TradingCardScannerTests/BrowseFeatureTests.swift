import SwiftData
import XCTest
@testable import TradingCardScanner

final class BrowseFeatureTests: XCTestCase {
#if DEBUG
    func testBundledModernPokemonChecklistCoversEveryScannerSet() async throws {
        let root = try makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PokemonChecklistStore(
            root: root,
            bundle: Bundle.main
        )
        let bundledSnapshot = await store.bundledSnapshot()
        let snapshot = try XCTUnwrap(bundledSnapshot)

        for definition in SetCodeMap.definitions.values {
            let entries = snapshot.manifest.entries.filter {
                $0.providerID.caseInsensitiveCompare(definition.tcgdexSetID) == .orderedSame
            }
            XCTAssertFalse(entries.isEmpty, "Missing bundled set \(definition.tcgdexSetID)")
            XCTAssertTrue(
                entries.allSatisfy { !(snapshot.checklist(for: $0.set.catalogID)?.isEmpty ?? true) },
                "Bundled set \(definition.tcgdexSetID) has no checklist"
            )
            XCTAssertTrue(
                entries.allSatisfy { $0.officialCount != nil },
                "Bundled set \(definition.tcgdexSetID) is missing its printed denominator"
            )
        }
    }

#endif
#if DEBUG
    /// Developer-only release step. Set POKEMON_SNAPSHOT_OUTPUT to a checkout
    /// directory before running this test; normal unit-test runs are a no-op.
    func testGeneratePokemonChecklistSnapshotWhenRequested() async throws {
        let configuredPath = ProcessInfo.processInfo.environment["POKEMON_SNAPSHOT_OUTPUT"]
            ?? (Bundle(for: BrowseFeatureTests.self)
                .object(forInfoDictionaryKey: "POKEMON_SNAPSHOT_OUTPUT") as? String)
        guard let path = configuredPath,
              !path.isEmpty,
              !path.contains("$(") else { return }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try await PokemonChecklistSnapshotGenerator.generate(
            transport: TCGdexBrowseTransport(),
            outputDirectory: output
        )

        let store = PokemonChecklistStore(root: output, bundle: nil)
        let snapshot = await store.downloadedSnapshot()
        XCTAssertNotNil(snapshot)
        XCTAssertFalse(snapshot?.manifest.entries.isEmpty == true)
    }

    func testSnapshotGeneratorRejectsMissingModernSetCoverage() async throws {
        let root = try makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            try await PokemonChecklistSnapshotGenerator.generate(
                transport: FakePokemonBrowseTransport(),
                outputDirectory: root
            )
            XCTFail("Expected the generator to reject incomplete modern coverage")
        } catch let error as PokemonChecklistError {
            guard case let .missingModernSetCoverage(ids) = error else {
                return XCTFail("Unexpected generator error: \(error)")
            }
            XCTAssertEqual(ids.count, SetCodeMap.definitions.count)
        }
    }
#endif

    func testCatalogIDsAreNamespacedByGame() {
        XCTAssertNotEqual(
            CatalogSetID(game: .pokemon, providerID: "abc").id,
            CatalogSetID(game: .magic, providerID: "abc").id
        )
    }

    @MainActor
    func testBrowseSearchDefaultsToAllResultKinds() {
        let model = BrowseViewModel(catalog: EmptyBrowseCatalog())

        XCTAssertEqual(model.searchGames, CardGame.allCases)
        XCTAssertTrue(model.searchResults.isEmpty)
    }

    func testCatalogSearchResultIDsNamespaceKindsAndOptionalVariants() {
        let cardSummary = browseDisplaySummary(providerID: "card-1", number: "001")
        let card = CatalogSearchResult.card(cardSummary)
        let product = SealedProductSummary(
            id: "product-1",
            name: "Booster Box",
            setName: "Example Set",
            variantID: nil,
            marketPriceUSD: nil,
            updatedAt: nil,
            imageURL: nil
        )
        let sealed = CatalogSearchResult.sealed(game: .pokemon, product: product)

        XCTAssertEqual(card.id, "card:\(cardSummary.id)")
        XCTAssertEqual(sealed.id, "sealed:pokemon:product-1:")
        XCTAssertNotEqual(card.id, sealed.id)
    }

    func testInactiveSealedSegmentDoesNotRequestCardSearch() {
        let normalizedSetQuery = CardNameSearch.normalize("Vendor Set")

        XCTAssertFalse(
            CatalogGameCardSearchPolicy.shouldRequest(
                isActive: false,
                normalizedQuery: normalizedSetQuery
            )
        )
        XCTAssertTrue(
            CatalogGameCardSearchPolicy.shouldRequest(
                isActive: true,
                normalizedQuery: normalizedSetQuery
            )
        )
        XCTAssertFalse(
            CatalogGameCardSearchPolicy.shouldRequest(
                isActive: true,
                normalizedQuery: "a"
            )
        )
    }

    func testCatalogSearchRankingUsesNameBucketsThenStableTieBreakers() {
        let values = [
            CatalogSearchResult.card(browseDisplaySummary(providerID: "exact", name: "Pikachu", number: "001")),
            CatalogSearchResult.card(browseDisplaySummary(providerID: "prefix", name: "Pika", number: "002")),
            CatalogSearchResult.card(browseDisplaySummary(providerID: "token", name: "Al Pikachu", number: "003")),
            CatalogSearchResult.card(browseDisplaySummary(providerID: "contains", name: "Spiky Pikachu", number: "004")),
            CatalogSearchResult.card(browseDisplaySummary(providerID: "other", name: "Other", number: "005"))
        ]

        let ranked = CatalogSearchResultRanking.sorted(values, query: " PIKA ")

        XCTAssertEqual(ranked.map(\.name), ["Pika", "Pikachu", "Al Pikachu", "Spiky Pikachu", "Other"])
    }

    func testCatalogSearchStateReductionKeepsTheSpecifiedPrecedence() {
        XCTAssertEqual(
            CatalogSearchState.reduce(
                resultCount: 1,
                lanes: [CatalogSearchLaneStatus(isLoading: true, error: "offline")],
                sealedWasSkippedForMissingCredentials: true
            ),
            .results(hasFailures: true)
        )
        XCTAssertEqual(
            CatalogSearchState.reduce(
                resultCount: 0,
                lanes: [CatalogSearchLaneStatus(isLoading: true)],
                sealedWasSkippedForMissingCredentials: false
            ),
            .loading
        )
        XCTAssertEqual(
            CatalogSearchState.reduce(
                resultCount: 0,
                lanes: [CatalogSearchLaneStatus(error: "offline")],
                sealedWasSkippedForMissingCredentials: false
            ),
            .failed
        )
        XCTAssertEqual(
            CatalogSearchState.reduce(
                resultCount: 0,
                lanes: [CatalogSearchLaneStatus()],
                sealedWasSkippedForMissingCredentials: true
            ),
            .empty(needsSealedSetup: true)
        )
        XCTAssertEqual(
            CatalogSearchState.reduce(
                resultCount: 0,
                lanes: [CatalogSearchLaneStatus()],
                sealedWasSkippedForMissingCredentials: false
            ),
            .empty(needsSealedSetup: false)
        )
    }

    func testCatalogCountCopyUsesSingularAndPluralForms() {
        XCTAssertEqual(countLabel(1, singular: "card", plural: "cards"), "1 card")
        XCTAssertEqual(countLabel(2, singular: "card", plural: "cards"), "2 cards")
        XCTAssertEqual(countLabel(1, singular: "set", plural: "sets"), "1 set")
        XCTAssertEqual(countLabel(2, singular: "set", plural: "sets"), "2 sets")
        XCTAssertEqual(
            countLabel(1, singular: "sealed product", plural: "sealed products"),
            "1 sealed product"
        )
        XCTAssertEqual(
            countLabel(2, singular: "sealed product", plural: "sealed products"),
            "2 sealed products"
        )
    }

    func testCatalogGameSummaryCountsEveryEligibleRowButKeepsOnlyThreeForArtwork() {
        let sets = [
            CatalogSet(
                catalogID: CatalogSetID(game: .pokemon, providerID: "one"),
                name: "One",
                code: "ONE",
                logoURL: nil,
                symbolURL: nil,
                cardCount: 10,
                releaseDate: nil,
                sortRank: 1
            ),
            CatalogSet(
                catalogID: CatalogSetID(game: .pokemon, providerID: "two"),
                name: "Two",
                code: "TWO",
                logoURL: nil,
                symbolURL: nil,
                cardCount: 10,
                releaseDate: nil,
                sortRank: 2
            )
        ]
        let now = Date(timeIntervalSince1970: 2_000)
        let rows = [
            browseDisplayRow(id: "old", quantity: 4, dateAdded: now.addingTimeInterval(-4)),
            browseDisplayRow(id: "newest", quantity: 1, dateAdded: now.addingTimeInterval(-1)),
            browseDisplayRow(id: "middle", quantity: 2, dateAdded: now.addingTimeInterval(-2)),
            browseDisplayRow(id: "third", quantity: 3, dateAdded: now.addingTimeInterval(-3)),
            browseDisplayRow(
                id: "sealed",
                quantity: 100,
                dateAdded: now,
                itemKind: .sealedProduct
            ),
            browseDisplayRow(id: "zero", quantity: 0, dateAdded: now)
        ]

        let summary = CatalogGameSummary(game: .pokemon, sets: sets, rows: rows)

        XCTAssertEqual(summary.setCount, 2)
        XCTAssertEqual(summary.ownedCardQuantity, 10)
        XCTAssertEqual(summary.recentArtworkRows.map(\.id), ["newest", "middle", "third"])
        XCTAssertEqual(summary.subtitle, "2 sets · 10 cards owned")
    }

    func testCatalogGameSummaryPrefersBundledArtworkBeforeStrictRecency() {
        let sets = [
            CatalogSet(
                catalogID: CatalogSetID(game: .pokemon, providerID: "me05"),
                name: "Pitch Black",
                code: "PBL",
                logoURL: nil,
                symbolURL: nil,
                cardCount: 119,
                releaseDate: nil,
                sortRank: 218
            ),
            CatalogSet(
                catalogID: CatalogSetID(game: .pokemon, providerID: "sv08.5"),
                name: "Prismatic Evolutions",
                code: "PRE",
                logoURL: nil,
                symbolURL: nil,
                cardCount: 180,
                releaseDate: nil,
                sortRank: 217
            ),
            CatalogSet(
                catalogID: CatalogSetID(game: .pokemon, providerID: "me04"),
                name: "Chaos Rising",
                code: "CRI",
                logoURL: nil,
                symbolURL: nil,
                cardCount: 128,
                releaseDate: nil,
                sortRank: 216
            ),
            CatalogSet(
                catalogID: CatalogSetID(game: .pokemon, providerID: "sv08"),
                name: "Surging Sparks",
                code: "SSP",
                logoURL: nil,
                symbolURL: nil,
                cardCount: 252,
                releaseDate: nil,
                sortRank: 215
            )
        ]

        let summary = CatalogGameSummary(game: .pokemon, sets: sets, rows: [])

        XCTAssertEqual(
            summary.recentSetArtwork.map(\.providerID),
            ["sv08.5", "sv08", "me05"]
        )
    }

    func testCatalogCardDisplayGroupingKeepsFinishAndPrintingBoundaries() {
        let set = CatalogSetID(game: .pokemon, providerID: "master")
        let normal = browseDisplaySummary(
            providerID: "master-001",
            setID: set,
            number: "001",
            variant: .normal
        )
        let reverse = browseDisplaySummary(
            providerID: "master-001",
            setID: set,
            number: "001",
            variant: .reverse
        )
        let otherNumber = browseDisplaySummary(
            providerID: "master-002",
            setID: set,
            number: "002",
            variant: .normal
        )
        let firstEdition = browseDisplaySummary(
            providerID: "master-001",
            setID: CatalogSetID(
                game: .pokemon,
                providerID: "base1",
                pokemonPrintRun: .firstEdition
            ),
            number: "001",
            variant: .normal
        )
        let unlimited = browseDisplaySummary(
            providerID: "master-001",
            setID: CatalogSetID(
                game: .pokemon,
                providerID: "base1",
                pokemonPrintRun: .unlimited
            ),
            number: "001",
            variant: .normal
        )

        let groups = CatalogCardDisplayGrouping.groups(
            for: [normal, reverse, otherNumber, firstEdition, unlimited]
        )

        XCTAssertEqual(groups.count, 4)
        XCTAssertEqual(groups[0].summaries.map(\.id), [normal.id, reverse.id])
        XCTAssertEqual(groups.map(\.id).count, Set(groups.map(\.id)).count)
    }

    func testCatalogCardDisplayGroupingKeepsMagicTreatmentsAsSingletons() {
        let foil = browseDisplaySummary(
            game: .magic,
            providerID: "printing-foil",
            number: "10"
        )
        let treated = browseDisplaySummary(
            game: .magic,
            providerID: "printing-surge",
            number: "10"
        )

        let groups = CatalogCardDisplayGrouping.groups(for: [foil, treated])

        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { $0.summaries.count == 1 })
        XCTAssertEqual(Set(groups.map(\.id)).count, 2)
    }

    func testCatalogCardDisplayGroupingDisambiguatesDuplicateMagicIdentities() {
        let first = browseDisplaySummary(
            game: .magic,
            providerID: "duplicate-printing",
            number: "10"
        )
        let second = browseDisplaySummary(
            game: .magic,
            providerID: "duplicate-printing",
            number: "10"
        )

        let groups = CatalogCardDisplayGrouping.groups(for: [first, second])

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.map(\.id)).count, 2)
    }

    func testCatalogCardDisplayGroupingKeepsNamedSoleFinishAndUnparseableNumbersVisible() {
        let named = browseDisplaySummary(
            providerID: "master-001",
            number: "001",
            variant: .reverse,
            isSoleSlotForCard: true
        )
        let punctuation = browseDisplaySummary(providerID: "punctuation", number: "?")
        let otherPunctuation = browseDisplaySummary(providerID: "punctuation-2", number: "!")

        let groups = CatalogCardDisplayGrouping.groups(for: [named, punctuation, otherPunctuation])

        XCTAssertEqual(groups[0].preferredSummary.masterSetVariantLabel, PhysicalVariant.reverse.label)
        XCTAssertEqual(groups.count, 3)
        XCTAssertNotEqual(groups[1].id, groups[2].id)
    }

    func testPokemonReleaseOrderCacheUsesProviderSetID() {
        PokemonCatalogReleaseOrder.install(["sv08.5": 312])
        XCTAssertEqual(PokemonCatalogReleaseOrder.order(forSetID: "SV08.5"), 312)
    }

    func testPokemonSearchURLCarriesNameAndPagination() throws {
        let url = try XCTUnwrap(BrowseRequestBuilder.pokemonSearchURL(query: "ho oh", page: 3))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(values["name"], "ho oh")
        XCTAssertEqual(values["pagination:page"], "3")
        XCTAssertEqual(values["pagination:itemsPerPage"], "60")
    }

    func testScryfallSearchRequestsExactPrintings() throws {
        let query = "name:\"Black Lotus\" lang:en game:paper (e:lea or e:2ed)"
        let url = try XCTUnwrap(BrowseRequestBuilder.scryfallSearchURL(query: query))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(values["q"], query)
        XCTAssertEqual(values["unique"], "prints")
    }

    func testSetDirectoryCacheSurvivesANewStoreInstance() async throws {
        let root = try makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let set = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "sv08.5"),
            name: "Prismatic Evolutions",
            code: "PRE",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 180,
            releaseDate: nil,
            sortRank: 1
        )

        let writer = CatalogCacheStore(root: root)
        await writer.storeSets([set], for: .pokemon)
        let reader = CatalogCacheStore(root: root)
        let saved = await reader.sets(for: .pokemon)

        XCTAssertEqual(saved?.value, [set])
        XCTAssertTrue(saved?.isFresh == true)
    }

    func testSortPriceCacheRoundTripsAndReportsStaleOrderingHints() async throws {
        let root = try makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let prices = ["card-1": 12.50, "card-2": 1.25]

        let writer = CatalogCacheStore(root: root)
        await writer.storeSortPrices(prices, for: "sv08.5")

        let reader = CatalogCacheStore(root: root)
        let saved = await reader.sortPrices(for: "sv08.5")
        XCTAssertEqual(saved?.value, prices)
        XCTAssertTrue(saved?.isFresh == true)

        let directory = root.appendingPathComponent("SortPrices", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let file = try XCTUnwrap(files.first)
        var envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        )
        envelope["storedAt"] = 0.0
        try JSONSerialization.data(withJSONObject: envelope).write(to: file, options: .atomic)

        let stale = await CatalogCacheStore(root: root).sortPrices(for: "sv08.5")
        XCTAssertEqual(stale?.value, prices)
        XCTAssertFalse(stale?.isFresh == true)
    }

    func testSealedPageCacheRetainsSavedPageAndFreshness() async throws {
        let root = try makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let product = SealedProductSummary(
            id: "sealed-1",
            name: "Booster Box",
            setName: "Example Set",
            variantID: "sealed",
            marketPriceUSD: 120,
            updatedAt: .now,
            imageURL: URL(string: "https://example.com/product.jpg"),
            tcgplayerProductID: "123"
        )
        let key = CatalogCacheStore.sealedPageKey(game: .pokemon, setID: "example", query: nil, offset: 0)
        let writer = CatalogCacheStore(root: root)
        await writer.storeSealedProductPage(
            CatalogPage(items: [product], nextCursor: "1"),
            for: key
        )

        let reader = CatalogCacheStore(root: root)
        let saved = await reader.sealedProductPage(for: key)

        XCTAssertEqual(saved?.value.items, [product])
        XCTAssertEqual(saved?.value.nextCursor, "1")
        XCTAssertTrue(saved?.isFresh == true)
    }

    func testCatalogSetOrderingIsNewestFirstByReleaseOrder() {
        let older = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "older"),
            name: "Older",
            code: "OLD",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 1,
            releaseDate: nil,
            sortRank: 10
        )
        let newer = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "newer"),
            name: "Newer",
            code: "NEW",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 1,
            releaseDate: nil,
            sortRank: 20
        )

        XCTAssertEqual(
            CatalogSetOrdering.newestFirst([older, newer]).map(\.id),
            [newer.id, older.id]
        )
    }

    func testCatalogSetOrderingIsOldestFirstThroughOrdered() {
        let older = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "older"),
            name: "Older",
            code: "OLD",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 1,
            releaseDate: nil,
            sortRank: 10
        )
        let newer = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "newer"),
            name: "Newer",
            code: "NEW",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 1,
            releaseDate: nil,
            sortRank: 20
        )

        XCTAssertEqual(
            CatalogSetOrdering.ordered(
                [newer, older],
                by: .oldestFirst,
                ownership: CatalogOwnershipIndex(rows: [])
            ).map(\.id),
            [older.id, newer.id]
        )
    }

    func testCatalogSetOrderingUsesStableIDForEqualReleaseRanks() {
        let beta = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "beta"),
            name: "Beta",
            code: "BET",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 1,
            releaseDate: nil,
            sortRank: 20
        )
        let alpha = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "alpha"),
            name: "Alpha",
            code: "ALP",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 1,
            releaseDate: nil,
            sortRank: 20
        )

        XCTAssertEqual(
            CatalogSetOrdering.newestFirst([beta, alpha]).map(\.id),
            [alpha.id, beta.id]
        )
    }

    func testCatalogSetOrderingReleaseRailUsesDatedSetsAndOneGameMayFillRail() {
        let now = Date(timeIntervalSince1970: 2_000 * 86_400)
        func set(
            game: CardGame,
            id: String,
            daysFromNow: Int,
            cardCount: Int? = 20,
            sortRank: Int = 0
        ) -> CatalogSet {
            CatalogSet(
                catalogID: CatalogSetID(game: game, providerID: id),
                name: id,
                code: id.prefix(3).uppercased(),
                logoURL: nil,
                symbolURL: nil,
                cardCount: cardCount,
                releaseDate: now.addingTimeInterval(TimeInterval(daysFromNow) * 86_400),
                sortRank: sortRank
            )
        }

        let pokemonNewest = set(game: .pokemon, id: "pokemon-newest", daysFromNow: -1)
        let pokemonSecond = set(game: .pokemon, id: "pokemon-second", daysFromNow: -2)
        let pokemonThird = set(game: .pokemon, id: "pokemon-third", daysFromNow: -3)
        let magicOlder = set(game: .magic, id: "magic-older", daysFromNow: -4)
        let tooSmall = set(game: .magic, id: "too-small", daysFromNow: -1, cardCount: 9)
        let future = set(game: .magic, id: "future", daysFromNow: 1)
        let outsideWindow = set(
            game: .magic,
            id: "outside-window",
            daysFromNow: -46
        )
        let exactWindowEdge = set(
            game: .magic,
            id: "exact-window-edge",
            daysFromNow: -45
        )

        let rail = CatalogSetOrdering.releaseRail(
            from: [
                .pokemon: [pokemonNewest, pokemonSecond, pokemonThird],
                .magic: [magicOlder, tooSmall, future, outsideWindow, exactWindowEdge]
            ],
            now: now
        )

        XCTAssertEqual(rail.title, "Just released")
        XCTAssertTrue(rail.showsNewBadges)
        XCTAssertEqual(
            rail.sets.map(\.id),
            [pokemonNewest.id, pokemonSecond.id, pokemonThird.id]
        )
        XCTAssertFalse(rail.sets.contains(tooSmall))
        XCTAssertFalse(rail.sets.contains(future))
        XCTAssertFalse(rail.sets.contains(outsideWindow))

        let edgeRail = CatalogSetOrdering.releaseRail(
            from: [.magic: [exactWindowEdge]],
            now: now
        )
        XCTAssertEqual(edgeRail.sets.map(\.id), [exactWindowEdge.id])

        let minimumRailCount = set(
            game: .magic,
            id: "minimum-rail-count",
            daysFromNow: -1,
            cardCount: CatalogSetOrdering.minimumRailCardCount
        )
        let minimumRail = CatalogSetOrdering.releaseRail(
            from: [.magic: [tooSmall, minimumRailCount]],
            now: now
        )
        XCTAssertEqual(minimumRail.sets.map(\.id), [minimumRailCount.id])

        let recoveredFromZeroBreakdown = set(
            game: .pokemon,
            id: "recovered-from-zero-breakdown",
            daysFromNow: -1,
            cardCount: 69
        )
        let recoveredRail = CatalogSetOrdering.releaseRail(
            from: [.pokemon: [recoveredFromZeroBreakdown]],
            now: now
        )
        XCTAssertEqual(recoveredRail.sets.map(\.id), [recoveredFromZeroBreakdown.id])
        XCTAssertEqual(magicOlder.game, .magic)
    }

    func testCatalogSetOrderingNewBadgeIsNilSafeAndUses45DayWindow() {
        let now = Date(timeIntervalSince1970: 2_000 * 86_400)
        func set(releasedAt: Date?) -> CatalogSet {
            CatalogSet(
                catalogID: CatalogSetID(game: .pokemon, providerID: UUID().uuidString),
                name: "Fixture",
                code: "FIX",
                logoURL: nil,
                symbolURL: nil,
                cardCount: nil,
                releaseDate: releasedAt,
                sortRank: 1
            )
        }

        XCTAssertTrue(
            CatalogSetOrdering.isNew(
                set(releasedAt: now.addingTimeInterval(-45 * 86_400)),
                now: now
            )
        )
        XCTAssertTrue(
            CatalogSetOrdering.isNew(
                set(releasedAt: now.addingTimeInterval(-44 * 86_400)),
                now: now
            )
        )
        XCTAssertFalse(
            CatalogSetOrdering.isNew(
                set(releasedAt: now.addingTimeInterval(-45 * 86_400 - 1)),
                now: now
            )
        )
        XCTAssertFalse(
            CatalogSetOrdering.isNew(
                set(releasedAt: now.addingTimeInterval(1)),
                now: now
            )
        )
        XCTAssertFalse(CatalogSetOrdering.isNew(set(releasedAt: nil), now: now))
    }

    func testCatalogSetListMostCompleteSortLeavesUnknownTotalsLast() {
        let complete = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "complete"),
            name: "Complete",
            code: "CMP",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 1,
            releaseDate: nil,
            sortRank: 1
        )
        let unknown = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "unknown"),
            name: "Unknown",
            code: "UNK",
            logoURL: nil,
            symbolURL: nil,
            cardCount: nil,
            releaseDate: nil,
            sortRank: 500
        )
        let card = CollectedCard(
            collectionKey: "catalog-list-complete",
            game: .pokemon,
            providerID: "complete-001",
            name: "Card",
            setName: "Complete",
            setCode: "CMP",
            cardNumber: "001",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .normal,
            variantResolution: .userConfirmed
        )
        let ownership = CatalogOwnershipIndex([card])

        XCTAssertEqual(
            CatalogSetOrdering.ordered(
                [unknown, complete],
                by: .mostComplete,
                ownership: ownership
            ).map(\.id),
            [complete.id, unknown.id]
        )
    }

    func testCatalogSetStartedFilterIncludesOwnedSetWithUnknownTotal() {
        let started = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "started"),
            name: "Started",
            code: "START",
            logoURL: nil,
            symbolURL: nil,
            cardCount: nil,
            releaseDate: nil,
            sortRank: 1
        )
        let unstarted = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "unstarted"),
            name: "Unstarted",
            code: "EMPTY",
            logoURL: nil,
            symbolURL: nil,
            cardCount: nil,
            releaseDate: nil,
            sortRank: 2
        )
        let card = CollectedCard(
            collectionKey: "catalog-list-started",
            game: .pokemon,
            providerID: "started-001",
            name: "Started card",
            setName: "Started",
            setCode: "START",
            cardNumber: "001",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .normal,
            variantResolution: .userConfirmed
        )
        let ownership = CatalogOwnershipIndex([card])

        let visible = [started, unstarted].filter {
            CatalogSetListFilter.started.includes($0, ownership: ownership)
        }

        XCTAssertEqual(visible.map(\.id), [started.id])
        XCTAssertEqual(ownership.progress(for: started).owned, 1)
        XCTAssertNil(ownership.progress(for: started).fraction)
    }

    func testCatalogSetOrderingMostCompleteIsStrictlyDescendingAcrossKnownFractions() {
        func set(_ providerID: String, _ code: String, cardCount: Int?) -> CatalogSet {
            CatalogSet(
                catalogID: CatalogSetID(game: .pokemon, providerID: providerID),
                name: providerID,
                code: code,
                logoURL: nil,
                symbolURL: nil,
                cardCount: cardCount,
                releaseDate: nil,
                sortRank: 1
            )
        }

        func card(_ index: Int, code: String, setName: String) -> CollectedCard {
            CollectedCard(
                collectionKey: "ordering-\(code)-\(index)",
                game: .pokemon,
                providerID: "\(code)-\(index)",
                name: "Card \(index)",
                setName: setName,
                setCode: code,
                cardNumber: String(format: "%03d", index),
                rarity: nil,
                imageURL: nil,
                thumbnailURL: nil,
                variant: .normal,
                variantResolution: .userConfirmed
            )
        }

        let complete = set("complete", "CMP", cardCount: 4)
        let half = set("half", "HAF", cardCount: 4)
        let quarter = set("quarter", "QTR", cardCount: 4)
        let unknown = set("unknown", "UNK", cardCount: nil)
        let ownership = CatalogOwnershipIndex([
            card(1, code: "CMP", setName: "complete"),
            card(2, code: "CMP", setName: "complete"),
            card(3, code: "CMP", setName: "complete"),
            card(4, code: "CMP", setName: "complete"),
            card(1, code: "HAF", setName: "half"),
            card(2, code: "HAF", setName: "half"),
            card(1, code: "QTR", setName: "quarter")
        ])

        let ordered = CatalogSetOrdering.ordered(
            [unknown, quarter, half, complete],
            by: .mostComplete,
            ownership: ownership
        )
        let fractions = ordered.map { ownership.progress(for: $0).fraction ?? -1 }

        XCTAssertEqual(ordered.map(\.id), [complete.id, half.id, quarter.id, unknown.id])
        XCTAssertTrue(zip(fractions, fractions.dropFirst()).allSatisfy { $0 > $1 })
    }

    func testMasterCountTreatsAllZeroVariationBreakdownAsUnpublished() throws {
        let zeroBreakdown = try decode(TCGdexCardCount.self, from: """
        {"total":200,"official":200,"normal":0,"holo":0,"reverse":0}
        """)
        XCTAssertEqual(
            PokemonMasterSetDefinition.masterCount(
                cardCount: zeroBreakdown,
                setName: "Black and White",
                printRun: nil
            ),
            200
        )

        let reverseOnly = try decode(TCGdexCardCount.self, from: """
        {"total":20,"official":20,"normal":0,"holo":0,"reverse":5}
        """)
        XCTAssertEqual(
            PokemonMasterSetDefinition.masterCount(
                cardCount: reverseOnly,
                setName: "Fixture",
                printRun: nil
            ),
            5
        )

        let publishedBreakdown = try decode(TCGdexCardCount.self, from: """
        {"total":24,"official":24,"normal":40,"holo":0,"reverse":72}
        """)
        XCTAssertEqual(
            PokemonMasterSetDefinition.masterCount(
                cardCount: publishedBreakdown,
                setName: "Prismatic Evolutions",
                printRun: nil
            ),
            112
        )

        let firstEdition = try decode(TCGdexCardCount.self, from: """
        {"total":69,"official":69,"normal":0,"holo":0,"reverse":0,"firstEd":42}
        """)
        XCTAssertEqual(
            PokemonMasterSetDefinition.masterCount(
                cardCount: firstEdition,
                setName: "Base Set",
                printRun: .firstEdition
            ),
            42
        )

        let baseUnlimited = try decode(TCGdexCardCount.self, from: """
        {"total":2,"official":2,"normal":0,"holo":0,"reverse":0}
        """)
        XCTAssertEqual(
            PokemonMasterSetDefinition.masterCount(
                cardCount: baseUnlimited,
                setName: "Base Set",
                printRun: .unlimited
            ),
            1
        )
    }

    func testSetDirectoryExcludesStandalonePromoRows() throws {
        for id in ["rc", "sp", "wp"] {
            let row = try decode(TCGdexBrowseSet.self, from: """
            {"id":"\(id)","name":"\(id.uppercased())","cardCount":{"total":1,"official":1}}
            """)
            XCTAssertFalse(PokemonMasterSetDefinition.includesInSetDirectory(row))
        }

        let normal = try decode(TCGdexBrowseSet.self, from: """
        {"id":"fixture","name":"A normal set","cardCount":null}
        """)
        XCTAssertTrue(PokemonMasterSetDefinition.includesInSetDirectory(normal))
    }

    func testCatalogSetOrderingMostCompleteUsesStableReleaseAndIDTies() {
        func set(_ providerID: String, sortRank: Int) -> CatalogSet {
            CatalogSet(
                catalogID: CatalogSetID(game: .pokemon, providerID: providerID),
                name: providerID,
                code: providerID.uppercased(),
                logoURL: nil,
                symbolURL: nil,
                cardCount: 1,
                releaseDate: nil,
                sortRank: sortRank
            )
        }

        let older = set("older", sortRank: 10)
        let beta = set("beta", sortRank: 20)
        let alpha = set("alpha", sortRank: 20)
        let ownership = CatalogOwnershipIndex(rows: [])

        XCTAssertEqual(
            CatalogSetOrdering.ordered(
                [older, beta, alpha],
                by: .mostComplete,
                ownership: ownership
            ).map(\.id),
            [alpha.id, beta.id, older.id]
        )
    }

    func testCatalogSetOrderingMostCompleteUsesChecklistCompletionIndex() {
        func set(_ providerID: String) -> CatalogSet {
            CatalogSet(
                catalogID: CatalogSetID(game: .pokemon, providerID: providerID),
                name: providerID,
                code: providerID.uppercased(),
                logoURL: nil,
                symbolURL: nil,
                cardCount: 99,
                releaseDate: nil,
                sortRank: 1
            )
        }

        let lower = set("lower")
        let higher = set("higher")
        let index = CatalogSetCompletionIndex(
            completions: [
                lower.id: SetCompletion(owned: 1, total: 2, unit: "variations"),
                higher.id: SetCompletion(owned: 2, total: 3, unit: "variations")
            ],
            tier: .standard
        )

        XCTAssertEqual(
            CatalogSetOrdering.ordered(
                [lower, higher],
                by: .mostComplete,
                ownership: CatalogOwnershipIndex(rows: []),
                completions: index,
                tier: .standard
            ).map(\.id),
            [higher.id, lower.id]
        )
    }

    func testCatalogSetOrderingNameAToZUsesNameThenStableID() {
        func set(_ providerID: String, name: String) -> CatalogSet {
            CatalogSet(
                catalogID: CatalogSetID(game: .pokemon, providerID: providerID),
                name: name,
                code: providerID.uppercased(),
                logoURL: nil,
                symbolURL: nil,
                cardCount: 1,
                releaseDate: nil,
                sortRank: 1
            )
        }

        let beta = set("beta", name: "Alpha")
        let alpha = set("alpha", name: "Alpha")
        let zeta = set("zeta", name: "Zeta")

        XCTAssertEqual(
            CatalogSetOrdering.ordered(
                [zeta, beta, alpha],
                by: .nameAToZ,
                ownership: CatalogOwnershipIndex(rows: [])
            ).map(\.id),
            [alpha.id, beta.id, zeta.id]
        )
    }

    func testCatalogSetListGroupingLeavesNonChronologicalSortUnlabeled() {
        let sets = [
            CatalogSet(
                catalogID: CatalogSetID(game: .pokemon, providerID: "dated"),
                name: "Dated",
                code: "DAT",
                logoURL: nil,
                symbolURL: nil,
                cardCount: 1,
                releaseDate: Date(timeIntervalSince1970: 1_700_000_000),
                sortRank: 1
            ),
            CatalogSet(
                catalogID: CatalogSetID(game: .pokemon, providerID: "earlier"),
                name: "Earlier",
                code: "EAR",
                logoURL: nil,
                symbolURL: nil,
                cardCount: 1,
                releaseDate: nil,
                sortRank: 2
            )
        ]

        let groups = CatalogSetListGrouping.groups(for: sets, sort: .mostComplete)

        XCTAssertEqual(groups.count, 1)
        XCTAssertNil(groups[0].title)
        XCTAssertEqual(groups[0].sets.map(\.id), sets.map(\.id))
    }

    func testCatalogSetListGroupingLeadsWithEarlierForOldestFirst() {
        let dated = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "dated"),
            name: "Dated",
            code: "DAT",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 1,
            releaseDate: Date(timeIntervalSince1970: 1_700_000_000),
            sortRank: 1
        )
        let undated = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "undated"),
            name: "Undated",
            code: "UND",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 1,
            releaseDate: nil,
            sortRank: 2
        )

        let ordered = CatalogSetOrdering.oldestFirst([dated, undated])
        let groups = CatalogSetListGrouping.groups(for: ordered, sort: .oldestFirst)

        XCTAssertEqual(groups.first?.title, "Earlier")
        XCTAssertEqual(groups.first?.sets.map(\.id), [undated.id])
    }

    func testCatalogSetOrderingReleaseRailFallsBackToCatalogOrderWithoutBadging() {
        let set = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "only"),
            name: "Only set",
            code: "ONLY",
            logoURL: nil,
            symbolURL: nil,
            cardCount: nil,
            releaseDate: nil,
            sortRank: 1
        )

        let rail = CatalogSetOrdering.releaseRail(from: [.pokemon: [set]])
        XCTAssertEqual(rail.title, "Recent sets")
        XCTAssertFalse(rail.showsNewBadges)
        XCTAssertEqual(rail.sets.map(\.id), [set.id])
        XCTAssertTrue(CatalogSetOrdering.releaseRail(from: [:]).sets.isEmpty)
    }

    func testSealedSetOrderingUsesReleaseDateNewestFirst() {
        let older = SealedSetSummary(
            id: "older",
            name: "Older Set",
            sealedCount: 1,
            game: .pokemon,
            releaseDate: Date(timeIntervalSince1970: 100)
        )
        let newer = SealedSetSummary(
            id: "newer",
            name: "Newer Set",
            sealedCount: 1,
            game: .pokemon,
            releaseDate: Date(timeIntervalSince1970: 200)
        )
        let undated = SealedSetSummary(
            id: "undated",
            name: "Undated Set",
            sealedCount: 1,
            game: .pokemon,
            releaseDate: nil
        )

        XCTAssertEqual(
            SealedSetOrdering.newestFirst([older, undated, newer]).map(\.id),
            [newer.id, older.id, undated.id]
        )
    }

    @MainActor
    func testSealedSearchReadsCachedResultsWithoutCredentials() async throws {
        let root = try makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let product = SealedProductSummary(
            id: "cached-sealed-1",
            name: "Cached Booster Box",
            setName: "Example Set",
            variantID: "sealed",
            marketPriceUSD: 100,
            updatedAt: .now,
            imageURL: nil,
            tcgplayerProductID: nil
        )
        let cache = CatalogCacheStore(root: root)
        let key = CatalogCacheStore.sealedPageKey(
            game: .pokemon,
            setID: nil,
            query: "box",
            offset: 0
        )
        await cache.storeSealedProductPage(
            CatalogPage(items: [product], nextCursor: nil),
            for: key
        )
        let client = RecordingJustTCGProviding()
        let model = SealedBrowseModel(
            client: client,
            cache: cache,
            isConfigured: { false }
        )

        await model.search(query: "box")

        XCTAssertEqual(model.searchLanes[.pokemon]?.products, [product])
        let requestCount = await client.sealedSearchCount()
        XCTAssertEqual(requestCount, 0)
    }

    @MainActor
    func testSealedSearchPopulatesOneLanePerGameAndHonorsMinimumQueryLength() async throws {
        let root = try makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pokemonProduct = SealedProductSummary(
            id: "pokemon-sealed-1",
            name: "Pokémon Booster Box",
            setName: "Example Pokémon Set",
            variantID: "sealed",
            marketPriceUSD: 120,
            updatedAt: nil,
            imageURL: nil,
            tcgplayerProductID: nil
        )
        let magicProduct = SealedProductSummary(
            id: "magic-sealed-1",
            name: "Magic Booster Box",
            setName: "Example Magic Set",
            variantID: "sealed",
            marketPriceUSD: 90,
            updatedAt: nil,
            imageURL: nil,
            tcgplayerProductID: nil
        )
        let client = RecordingJustTCGProviding(productsByGame: [
            .pokemon: [pokemonProduct],
            .magic: [magicProduct]
        ])
        let model = SealedBrowseModel(
            client: client,
            cache: CatalogCacheStore(root: root),
            isConfigured: { true }
        )

        await model.search(query: "b")
        XCTAssertTrue(model.searchLanes.isEmpty)
        let shortQueryRequestCount = await client.sealedSearchCount()
        XCTAssertEqual(shortQueryRequestCount, 0)

        await model.search(query: "box")

        XCTAssertEqual(model.searchLanes[.pokemon]?.products, [pokemonProduct])
        XCTAssertEqual(model.searchLanes[.magic]?.products, [magicProduct])
        let searchedGames = await client.sealedSearchGames()
        XCTAssertEqual(Set(searchedGames), Set(CardGame.allCases))
    }

    @MainActor
    func testSealedSearchCanLoadOnlyTheSelectedGame() async throws {
        let root = try makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let client = RecordingJustTCGProviding()
        let model = SealedBrowseModel(
            client: client,
            cache: CatalogCacheStore(root: root),
            isConfigured: { true }
        )

        await model.search(query: "box", games: [.magic])

        XCTAssertEqual(Set(model.searchLanes.keys), Set([CardGame.magic]))
        let searchedGames = await client.sealedSearchGames()
        XCTAssertEqual(searchedGames, [.magic])
    }

    @MainActor
    func testBrowseSearchDebouncesBeforeStartingBothSearchLanes() async throws {
        let root = try makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sealedClient = RecordingJustTCGProviding()
        let sealedModel = SealedBrowseModel(
            client: sealedClient,
            cache: CatalogCacheStore(root: root),
            isConfigured: { true }
        )
        let catalog = EmptyBrowseCatalog()
        let model = BrowseViewModel(catalog: catalog, sealedModel: sealedModel)

        model.searchText = "box"
        try await Task.sleep(for: .milliseconds(150))
        let earlyCardSearchCount = await catalog.searchCount()
        let earlySealedSearchCount = await sealedClient.sealedSearchCount()
        XCTAssertEqual(earlyCardSearchCount, 0)
        XCTAssertEqual(earlySealedSearchCount, 0)

        let bothSearchesStarted = await waitUntil {
            let cardCount = await catalog.searchCount()
            let sealedCount = await sealedClient.sealedSearchCount()
            return cardCount == CardGame.allCases.count
                && sealedCount == CardGame.allCases.count
        }
        XCTAssertTrue(bothSearchesStarted)

        let cardSearchCount = await catalog.searchCount()
        let sealedSearchCount = await sealedClient.sealedSearchCount()
        XCTAssertEqual(cardSearchCount, CardGame.allCases.count)
        XCTAssertEqual(sealedSearchCount, CardGame.allCases.count)
    }

    @MainActor
    func testBrowseSearchUsesSelectedGameForBothResultKinds() async throws {
        let root = try makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sealedClient = RecordingJustTCGProviding()
        let sealedModel = SealedBrowseModel(
            client: sealedClient,
            cache: CatalogCacheStore(root: root),
            isConfigured: { true }
        )
        let catalog = EmptyBrowseCatalog()
        let model = BrowseViewModel(catalog: catalog, sealedModel: sealedModel)

        model.selectedGame = .magic
        model.searchText = "box"

        let searchesStarted = await waitUntil {
            let cardCount = await catalog.searchCount()
            let sealedCount = await sealedClient.sealedSearchCount()
            return cardCount == 1 && sealedCount == 1
        }

        XCTAssertTrue(searchesStarted)
        XCTAssertEqual(Set(model.lanes.keys), Set([.magic]))
        let searchedGames = await sealedClient.sealedSearchGames()
        XCTAssertEqual(searchedGames, [.magic])
    }

    @MainActor
    func testBrowseSearchPaginationAdvancesCardLaneWithoutRecordingError() async throws {
        let root = try makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = browseDisplaySummary(
            providerID: "page-one",
            name: "Booster One",
            number: "001"
        )
        let second = browseDisplaySummary(
            providerID: "page-two",
            name: "Booster Two",
            number: "002"
        )
        let catalog = PagingBrowseCatalog(first: first, second: second)
        let sealedModel = SealedBrowseModel(
            client: RecordingJustTCGProviding(),
            cache: CatalogCacheStore(root: root),
            isConfigured: { false }
        )
        let model = BrowseViewModel(catalog: catalog, sealedModel: sealedModel)

        model.selectedGame = .pokemon
        model.searchText = "box"

        let firstPageLoaded = await waitUntil {
            model.lanes[.pokemon]?.cards.count == 1
                && model.lanes[.pokemon]?.cursor == "next"
        }
        XCTAssertTrue(firstPageLoaded)

        await model.loadMoreSearchResults()

        XCTAssertEqual(model.lanes[.pokemon]?.cards.map(\.id), [first.id, second.id])
        XCTAssertNil(model.lanes[.pokemon]?.cursor)
        XCTAssertNil(model.lanes[.pokemon]?.error)
        let requestedCursors = await catalog.requestedCursors()
        XCTAssertEqual(requestedCursors, [nil, "next"])
    }

    private func browseDisplaySummary(
        game: CardGame = .pokemon,
        providerID: String,
        setID: CatalogSetID? = nil,
        name: String = "Fixture",
        number: String,
        variant: PhysicalVariant? = nil,
        isSoleSlotForCard: Bool = false
    ) -> CatalogCardSummary {
        CatalogCardSummary(
            game: game,
            providerID: providerID,
            setID: setID ?? CatalogSetID(game: game, providerID: "display"),
            setName: "Display Set",
            setCode: "DSP",
            name: name,
            collectorNumber: number,
            thumbnailURL: nil,
            imageURL: nil,
            masterSetVariant: variant,
            isSoleSlotForCard: isSoleSlotForCard
        )
    }

    private func browseDisplayRow(
        id: String,
        quantity: Int,
        dateAdded: Date,
        itemKind: CollectionItemKind = .rawCard
    ) -> CollectionRow {
        CollectionRow(
            id: id,
            game: .pokemon,
            name: id,
            setCode: "DSP",
            setName: "Display Set",
            setReleaseOrder: 0,
            cardNumber: id,
            variantID: nil,
            variantLabel: nil,
            quantity: quantity,
            dateAdded: dateAdded,
            price: .unknown,
            itemKind: itemKind
        )
    }

    private func makeTemporaryCacheDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from string: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(string.utf8))
    }

    private func waitUntil(
        _ condition: @escaping () async -> Bool
    ) async -> Bool {
        for _ in 0..<300 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }
}

@MainActor
final class BrowseCollectionTests: XCTestCase {
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    func testCatalogSelectionIncrementsNormalizedImportAlias() throws {
        let context = try makeContext()
        let imported = CollectedCard(
            collectionKey: "csv:Prismatic Evolutions|074#reverse",
            game: .pokemon,
            providerID: "csv:Prismatic Evolutions|074",
            name: "Eevee",
            setName: "Prismatic Evolutions",
            setCode: "PRE",
            cardNumber: "074",
            rarity: "Common",
            imageURL: nil,
            thumbnailURL: nil,
            variant: .reverse,
            variantResolution: .imported,
            identityResolution: .imported,
            quantity: 1
        )
        imported.catalogProviderID = "sv08.5-074"
        context.insert(imported)
        try context.save()

        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "PRE")
        let mutation = try! CollectionStore(context: context).add(
            card,
            resolved: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
            identityResolution: .catalogSelected,
            matchCatalogAliases: true
        )

        XCTAssertFalse(mutation.didInsert)
        XCTAssertEqual(mutation.collectionKey, imported.collectionKey)
        XCTAssertEqual(imported.quantity, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectedCard>()).count, 1)
    }

    func testPreTreatmentCSVUsesCollectionReadThrough() throws {
        let context = try makeContext()
        let existing = CollectedCard(
            collectionKey: "magic:printing#foil#treatment=surgefoil",
            game: .magic,
            providerID: "printing",
            name: "Fixture",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "10",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .foil,
            variantResolution: .userConfirmed,
            magicTreatments: [.surgeFoil]
        )
        context.insert(existing)
        try context.save()

        // This is the shape exported before Slice 5 appended the treatment
        // column: the old finish key is the treatment-free alias.
        let csv = """
        game,provider_id,card_name,set_name,set_code,card_number,finish,finish_name,quantity
        magic,printing,Fixture,Fixture Set,FIC,10,foil,Foil,1
        """
        let plan = try CollectionCSV.parse(Data(csv.utf8))
        let result = try CollectionCSV.apply(plan, to: context)

        XCTAssertEqual(result.mergedEntries, 1)
        XCTAssertEqual(result.insertedEntries, 0)
        XCTAssertEqual(existing.quantity, 2)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CollectedCard>()).map(\.collectionKey),
            ["magic:printing#foil#treatment=surgefoil"]
        )
    }

    func testPostTreatmentCSVUsesCollectionReadThroughForLegacyRow() throws {
        let context = try makeContext()
        let existing = CollectedCard(
            collectionKey: "magic:printing#foil",
            game: .magic,
            providerID: "printing",
            name: "Fixture",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "10",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .foil,
            variantResolution: .userConfirmed
        )
        context.insert(existing)
        try context.save()

        let source = CollectedCard(
            collectionKey: "magic:printing#foil#treatment=neonink",
            game: .magic,
            providerID: "printing",
            name: "Fixture",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "10",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .foil,
            variantResolution: .userConfirmed,
            magicTreatments: [.neonInk],
            magicTreatmentQualifiers: ["neonink": "red"]
        )

        let plan = try CollectionCSV.parse(
            Data(CollectionCSV.export([source]).text.utf8)
        )
        let result = try CollectionCSV.apply(plan, to: context)

        XCTAssertEqual(result.mergedEntries, 1)
        XCTAssertEqual(result.insertedEntries, 0)
        XCTAssertEqual(existing.collectionKey, source.collectionKey)
        XCTAssertEqual(existing.magicTreatmentIDsRaw, ["neonink"])
        XCTAssertEqual(existing.magicTreatmentQualifiers, ["neonink": "red"])
        XCTAssertEqual(existing.quantity, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectedCard>()).count, 1)
    }

    func testCSVImportRejectsAnArbitraryTreatmentIDWithoutCreatingARow() throws {
        let context = try makeContext()
        let unknown = try XCTUnwrap(MagicTreatment(id: "surge foil"))
        let source = CollectedCard(
            collectionKey: MagicTreatmentKeyCodec.finishQualifiedCollectionKey(
                base: "magic:printing",
                game: .magic,
                finish: .foil,
                treatments: [unknown]
            ),
            game: .magic,
            providerID: "printing",
            name: "Fixture",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "10",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .foil,
            variantResolution: .userConfirmed,
            magicTreatments: [unknown],
            magicTreatmentQualifiers: ["Future / Foil": "publisher stamp"]
        )
        source.magicContentKindRaw = "future-face"

        let plan = try CollectionCSV.parse(
            Data(CollectionCSV.export([source]).text.utf8)
        )
        let result = try CollectionCSV.apply(plan, to: context)

        XCTAssertEqual(result.failedRows.count, 1)
        XCTAssertEqual(result.failedEntries.first?.magicTreatmentIDsRaw, ["surge foil"])
        XCTAssertTrue(try context.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
    }

    func testNewCatalogSelectionStoresCatalogProvenanceAndUndoes() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "PRE")
        let store = CollectionStore(context: context)
        let mutation = try! store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            identityResolution: .catalogSelected,
            setReleaseOrder: 300,
            matchCatalogAliases: true
        )

        let inserted = try XCTUnwrap(store.card(forKey: mutation.collectionKey))
        XCTAssertEqual(inserted.identityResolution, .catalogSelected)
        XCTAssertEqual(inserted.setReleaseOrder, 300)

        try! store.undo(mutation)
        XCTAssertNil(store.card(forKey: mutation.collectionKey))
    }

    func testSetCompletionCountsCollectorNumbersNotVariantsOrQuantity() {
        let set = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "sv08.5"),
            name: "Prismatic Evolutions",
            code: "PRE",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 180,
            releaseDate: nil,
            sortRank: 1
        )
        let cards = [
            completionCard(number: "074", variant: .normal, quantity: 3),
            completionCard(number: "074/131", variant: .reverse),
            completionCard(number: "075", variant: .masterBall)
        ]

        XCTAssertEqual(
            SetCompletionCalculator.progress(for: set, cards: cards),
            SetCompletion(owned: 2, total: 180, unit: "cards")
        )
    }

    func testLegacyFirstEditionPriceRemainsReadable() {
        let card = completionCard(number: "001", variant: .firstEdition)
        let oldKey = PriceRecord.key(
            game: .pokemon,
            printingID: card.providerID,
            variantID: PhysicalVariant.firstEdition.id
        )
        let oldRecord = PriceRecord(
            key: oldKey,
            game: .pokemon,
            printingID: card.providerID,
            variantID: PhysicalVariant.firstEdition.id
        )
        oldRecord.applyImported(amount: 125, sourceUpdatedAt: nil)

        XCTAssertNotEqual(card.priceKey, oldKey)
        XCTAssertEqual(
            PriceStore.record(for: card, in: [oldKey: oldRecord])?.unitMarketPriceUSD,
            125
        )
    }

    /// The instrument a position is attributed to and the record whose price is
    /// shown for it must be one decision. `CollectionView` projects the whole
    /// collection through this on every render, so it also has to answer without
    /// touching the store — the ledger's equivalent costs two predicate fetches
    /// per candidate key, which is what made the grid re-fetch thousands of rows
    /// per keystroke.
    func testPriceStorageKeyAgreesWithTheRecordThatSuppliesThePrice() {
        let card = completionCard(number: "001", variant: .firstEdition)
        let legacyKey = PriceRecord.key(
            game: .pokemon,
            printingID: card.providerID,
            variantID: PhysicalVariant.firstEdition.id
        )
        XCTAssertNotEqual(card.priceKey, legacyKey)

        // No records at all: the canonical key, never a legacy one.
        XCTAssertEqual(PriceStore.priceStorageKey(for: card, in: [:]), card.priceKey)

        // Only the legacy key holds a value, so that is the instrument in force
        // — matching the record `record(for:in:)` hands back for display.
        let legacyRecord = PriceRecord(
            key: legacyKey,
            game: .pokemon,
            printingID: card.providerID,
            variantID: PhysicalVariant.firstEdition.id
        )
        legacyRecord.applyImported(amount: 125, sourceUpdatedAt: nil)
        let legacyOnly = [legacyKey: legacyRecord]
        XCTAssertEqual(PriceStore.priceStorageKey(for: card, in: legacyOnly), legacyKey)
        XCTAssertEqual(
            PriceStore.record(for: card, in: legacyOnly)?.key,
            PriceStore.priceStorageKey(for: card, in: legacyOnly)
        )

        // Once the canonical key carries its own value it wins outright.
        let canonical = PriceRecord(
            key: card.priceKey,
            game: .pokemon,
            printingID: card.providerID,
            variantID: card.variantID
        )
        canonical.applyImported(amount: 200, sourceUpdatedAt: nil)
        let both = [legacyKey: legacyRecord, card.priceKey: canonical]
        XCTAssertEqual(PriceStore.priceStorageKey(for: card, in: both), card.priceKey)
        XCTAssertEqual(
            PriceStore.record(for: card, in: both)?.key,
            PriceStore.priceStorageKey(for: card, in: both)
        )

        // An invalidated canonical record is authoritative: the position must
        // not fall through to the legacy value the invalidation withdrew.
        canonical.invalidate(at: .now)
        XCTAssertEqual(PriceStore.priceStorageKey(for: card, in: both), card.priceKey)
        XCTAssertEqual(
            PriceStore.record(for: card, in: both)?.key,
            PriceStore.priceStorageKey(for: card, in: both)
        )
    }

    func testImportedPrintRunMetadataIndexUsesStableProviderID() throws {
        let context = try makeContext()
        let card = completionCard(number: "001", variant: .holo)
        card.providerID = "csv:base-set|001"
        card.pokemonPrintRunRaw = PokemonPrintRun.firstEdition.rawValue
        context.insert(card)
        try context.save()

        let indexed = PriceStore(context: context).importedCardsByProviderID()

        XCTAssertEqual(indexed[card.providerID]?.map(\.collectionKey), [card.collectionKey])
        XCTAssertNil(indexed[card.priceStorageID])
    }

    func testVariantCorrectionRetargetsTheScanActivity() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "PRE")
        let store = CollectionStore(context: context)
        _ = try! store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )

        let mutation = try XCTUnwrap(
            try! store.recordVariantCorrection(
                for: card,
                from: .normal,
                to: ResolvedVariant(variant: .reverse, resolution: .userConfirmed)
            )
        )
        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())

        XCTAssertEqual(activities.count, 2, "a correction is not another acquisition")
        let retargeted = try XCTUnwrap(activities.first { $0.kind == .added })
        let correction = try XCTUnwrap(activities.first { $0.kind == .corrected })
        XCTAssertEqual(retargeted.source, .scan)
        XCTAssertEqual(retargeted.collectionKey, mutation.collectionKey)
        XCTAssertEqual(retargeted.variantID, PhysicalVariant.reverse.id)
        XCTAssertNotNil(retargeted.correctedAt)
        XCTAssertEqual(correction.deltaQuantity, 0)
        XCTAssertEqual(correction.collectionKey, mutation.collectionKey)
    }

    func testGradedVariantCorrectionStaysOnTheCertificateRow() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "PRE")
        let store = CollectionStore(context: context)
        let acquired = try store.addScannedGraded(
            underlying: card,
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            certificationNumber: "12345678",
            resolved: ResolvedVariant(variant: .normal, resolution: .catalogSilent)
        )
        let row = try XCTUnwrap(store.card(forKey: acquired.collectionKey))
        let activityID = try XCTUnwrap(acquired.activityID)

        let corrected = try XCTUnwrap(
            try store.recordVariantCorrection(
                for: row,
                to: ResolvedVariant(variant: .holo, resolution: .userConfirmed),
                activityID: activityID,
                quantity: 1
            )
        )

        let updated = try XCTUnwrap(store.card(forKey: corrected.collectionKey))
        XCTAssertEqual(updated.collectionKey, row.collectionKey)
        XCTAssertEqual(updated.itemKind, .gradedCard)
        XCTAssertEqual(updated.variant, .holo)
        XCTAssertEqual(updated.variantResolution, .userConfirmed)
        XCTAssertEqual(try context.fetch(FetchDescriptor<InventoryEvent>()).count, 1)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CollectionActivity>()).filter { $0.kind == .corrected }.count,
            1
        )
    }

    func testVariantCorrectionPreservesPokemonPrintRunIdentity() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "BASE1")
        let store = CollectionStore(context: context)
        _ = try! store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan,
            pokemonPrintRun: .firstEdition
        )

        let mutation = try XCTUnwrap(
            try! store.recordVariantCorrection(
                for: card,
                from: .normal,
                to: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
                pokemonPrintRun: .firstEdition
            )
        )
        let corrected = try XCTUnwrap(store.card(forKey: mutation.collectionKey))
        XCTAssertEqual(corrected.pokemonPrintRun, .firstEdition)
        XCTAssertTrue(corrected.collectionKey.hasSuffix("@firstEdition"))
    }

    func testVariantCorrectionWithMissingSourceDoesNotCreateAnUnbalancedPosition() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "PRE")
        let store = CollectionStore(context: context)

        let mutation = try store.recordVariantCorrection(
            for: card,
            from: .normal,
            to: ResolvedVariant(variant: .reverse, resolution: .userConfirmed)
        )

        XCTAssertNil(mutation)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
    }

    func testIncrementUndoRemovesExactlyOneCopyAndRecordsUndoActivity() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "PRE")
        let store = CollectionStore(context: context)
        _ = try store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )
        let second = try store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )

        try store.undo(second)

        XCTAssertEqual(store.card(forKey: second.collectionKey)?.quantity, 1)
        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertEqual(activities.count, 3)
        let undone = try XCTUnwrap(activities.first { $0.kind == .undone })
        XCTAssertEqual(undone.deltaQuantity, -1)
        XCTAssertEqual(
            activities.filter { $0.kind == .added && $0.id == second.activityID }.first?.resolvedQuantity,
            1
        )
        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(InventoryLedger.quantities(from: events)[second.collectionKey], 1)
    }

    func testMultipleCorrectionsUndoTheFullLineageToZero() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "PRE")
        let store = CollectionStore(context: context)
        let acquired = try store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )
        let firstCorrection = try XCTUnwrap(
            try store.recordVariantCorrection(
                for: card,
                from: .normal,
                to: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
                previousLedgerOperationIDs: acquired.ledgerOperationIDs
            )
        )
        let secondCorrection = try XCTUnwrap(
            try store.recordVariantCorrection(
                for: card,
                from: .reverse,
                to: ResolvedVariant(variant: .holo, resolution: .userConfirmed),
                previousCollectionKey: firstCorrection.collectionKey,
                previousLedgerOperationIDs: firstCorrection.ledgerOperationIDs
            )
        )

        XCTAssertEqual(secondCorrection.ledgerOperationIDs.count, 3)
        try store.undo(secondCorrection)

        XCTAssertTrue(try context.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertEqual(activities.count, 4)
        XCTAssertEqual(activities.filter { $0.kind == .added }.count, 1)
        XCTAssertEqual(activities.filter { $0.kind == .corrected }.count, 2)
        XCTAssertEqual(activities.filter { $0.kind == .undone }.count, 1)
        XCTAssertEqual(activities.reduce(0) { $0 + $1.signedQuantity }, 0)
        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertTrue(InventoryLedger.quantities(from: events).isEmpty)
    }

    func testCorrectionIntoExistingDestinationUndoPreservesOtherCopy() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "PRE")
        let store = CollectionStore(context: context)
        let original = try store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )
        _ = try store.add(
            card,
            resolved: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
            source: .scan
        )
        let corrected = try XCTUnwrap(
            try store.recordVariantCorrection(
                for: card,
                from: .normal,
                to: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
                previousLedgerOperationIDs: original.ledgerOperationIDs
            )
        )

        try store.undo(corrected)

        XCTAssertNil(store.card(forKey: original.collectionKey))
        XCTAssertEqual(store.card(forKey: corrected.collectionKey)?.quantity, 1)
        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(InventoryLedger.quantities(from: events)[corrected.collectionKey], 1)
    }

    func testUndoWithMissingLineageDoesNotPartiallyMutateCollection() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "PRE")
        let store = CollectionStore(context: context)
        let mutation = try store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )
        let badMutation = CollectionMutation(
            collectionKey: mutation.collectionKey,
            activityID: mutation.activityID,
            didInsert: mutation.didInsert,
            ledgerOperationIDs: [UUID()]
        )

        XCTAssertThrowsError(try store.undo(badMutation))
        XCTAssertEqual(store.card(forKey: mutation.collectionKey)?.quantity, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectionActivity>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<InventoryEvent>()).count, 1)
    }

    func testPrintRunScanAggregatesLegacyUnqualifiedRow() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodePokemon(), setCode: "BASE1")
        let resolved = ResolvedVariant(variant: .normal, resolution: .userConfirmed)
        let legacy = CollectedCard(card: card, resolved: resolved)
        legacy.pokemonPrintRunRaw = PokemonPrintRun.firstEdition.rawValue
        context.insert(legacy)
        try context.save()

        let mutation = try! CollectionStore(context: context).add(
            card,
            resolved: resolved,
            source: .scan,
            pokemonPrintRun: .firstEdition,
            matchCatalogAliases: true
        )

        XCTAssertFalse(mutation.didInsert)
        XCTAssertEqual(mutation.collectionKey, legacy.collectionKey)
        XCTAssertEqual(legacy.quantity, 2)
    }

    func testSetCompletionIncludesNormalizedImportAlias() {
        let set = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "sv08.5"),
            name: "Prismatic Evolutions",
            code: "PRE",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 180,
            releaseDate: nil,
            sortRank: 1
        )
        let imported = completionCard(number: "076", variant: .reverse)
        imported.setCode = "Prismatic Evolutions"
        imported.catalogProviderID = "sv08.5-076"

        XCTAssertEqual(SetCompletionCalculator.progress(for: set, cards: [imported]).owned, 1)
    }

    func testStampedReprintDoesNotCompleteItsSourceExpansionSlot() throws {
        let stamped = try XCTUnwrap(
            PokemonStampedReleaseCatalog.entries(providerID: "swsh11-066").first?.variant
        )
        let owned = completionCard(number: "066", variant: stamped)
        owned.providerID = "swsh11-066"
        owned.catalogProviderID = "swsh11-066"
        owned.setName = "Trick or Trade 2023"
        owned.setCode = "TOT23"
        let lostOrigin = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "swsh11"),
            name: "Lost Origin",
            code: "LOR",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 196,
            releaseDate: nil,
            sortRank: 1
        )
        let gengar = CatalogCardSummary(
            game: .pokemon,
            providerID: "swsh11-066",
            setID: lostOrigin.catalogID,
            setName: lostOrigin.name,
            setCode: lostOrigin.code,
            name: "Gengar",
            collectorNumber: "066",
            thumbnailURL: nil,
            imageURL: nil
        )

        XCTAssertEqual(SetCompletionCalculator.progress(for: lostOrigin, cards: [owned]).owned, 0)
        XCTAssertFalse(SetCompletionCalculator.owns(gengar, cards: [owned]))
    }

    func testAddingStampedGengarStoresStampedReleaseMetadataAndArtwork() throws {
        let context = try makeContext()
        let card = IdentifiedCard.pokemon(try decodeStampedGengar(), setCode: "LOR")
        let stamped = try XCTUnwrap(
            PokemonStampedReleaseCatalog.entries(providerID: "swsh11-066").first?.variant
        )

        let mutation = try! CollectionStore(context: context).add(
            card,
            resolved: ResolvedVariant(variant: stamped, resolution: .userConfirmed),
            identityResolution: .printedIdentifier
        )
        let stored = try XCTUnwrap(CollectionStore(context: context).card(forKey: mutation.collectionKey))

        XCTAssertEqual(stored.setName, "Trick or Trade 2023")
        XCTAssertEqual(stored.setCode, "TOT23")
        XCTAssertEqual(stored.variantID, "trickOrTrade2023Holofoil")
        XCTAssertEqual(
            stored.imageURL,
            "https://tcgplayer-cdn.tcgplayer.com/product/515661_400w.jpg"
        )
        XCTAssertEqual(stored.thumbnailURL, stored.imageURL)
    }

    func testSetQuerySortsByNumberAndPriceWithUnknownPricesLast() {
        let cards = [
            summary(id: "set-10", number: "10"),
            summary(id: "set-2", number: "2"),
            summary(id: "set-1", number: "1"),
            summary(id: "set-3", number: "3")
        ]
        let prices = [cards[0].id: 4.50, cards[1].id: 12.00]

        XCTAssertEqual(query(cards, sort: .numberLowToHigh).map(\.collectorNumber), ["1", "2", "3", "10"])
        XCTAssertEqual(query(cards, sort: .numberHighToLow).map(\.collectorNumber), ["10", "3", "2", "1"])
        XCTAssertEqual(query(cards, sort: .priceHighToLow, prices: prices).map(\.collectorNumber), ["2", "10", "1", "3"])
        XCTAssertEqual(query(cards, sort: .priceLowToHigh, prices: prices).map(\.collectorNumber), ["10", "2", "1", "3"])
    }

    func testPriceRequestIdentityRejectsStaleContentRequestsAndCancellation() {
        let content = UUID()
        let request = UUID()
        let identity = CatalogPriceRequestIdentity(
            contentGeneration: content,
            requestID: request
        )

        XCTAssertTrue(
            identity.matches(
                contentGeneration: content,
                requestID: request,
                isCancelled: false
            )
        )
        XCTAssertFalse(
            identity.matches(
                contentGeneration: UUID(),
                requestID: request,
                isCancelled: false
            )
        )
        XCTAssertFalse(
            identity.matches(
                contentGeneration: content,
                requestID: UUID(),
                isCancelled: false
            )
        )
        XCTAssertFalse(
            identity.matches(
                contentGeneration: content,
                requestID: nil,
                isCancelled: false
            )
        )
        XCTAssertFalse(
            identity.matches(
                contentGeneration: content,
                requestID: request,
                isCancelled: true
            )
        )
    }

    func testPriceLoadStateRejectsLateCompletionAfterContentChanges() {
        var state = CatalogPriceLoadState()
        let oldRequest = UUID()
        state.begin(requestID: oldRequest)
        XCTAssertTrue(state.isLoading)
        XCTAssertFalse(state.hasLoadedPrices)

        state.invalidate()
        state.finish(requestID: oldRequest, loaded: true)
        XCTAssertNil(state.requestID)
        XCTAssertFalse(state.isLoading)
        XCTAssertFalse(state.hasLoadedPrices)

        let currentRequest = UUID()
        state.begin(requestID: currentRequest)
        state.finish(requestID: currentRequest, loaded: true)
        XCTAssertNil(state.requestID)
        XCTAssertFalse(state.isLoading)
        XCTAssertTrue(state.hasLoadedPrices)
    }

    func testCatalogSetQuerySortsCollectorNumberSuffixesNaturally() {
        let cards = [
            magicSummary(id: "suffix-b", number: "525b"),
            magicSummary(id: "bare", number: "525"),
            magicSummary(id: "suffix-a", number: "525a")
        ]

        XCTAssertEqual(
            query(cards).map(\.collectorNumber),
            ["525", "525a", "525b"]
        )
    }

    func testSetQueryFiltersOwnedAndNotOwnedIncludingCatalogAliases() {
        let ownedSummary = summary(id: "set-1", number: "1")
        let unownedSummary = summary(id: "set-2", number: "2")
        let alias = completionCard(number: "1", variant: .normal)
        alias.providerID = "csv:Set|1"
        alias.catalogProviderID = ownedSummary.providerID

        XCTAssertEqual(
            query([ownedSummary, unownedSummary], ownership: .owned, ownedCards: [alias]).map(\.id),
            [ownedSummary.id]
        )
        XCTAssertEqual(
            query([ownedSummary, unownedSummary], ownership: .notOwned, ownedCards: [alias]).map(\.id),
            [unownedSummary.id]
        )
    }

    func testCatalogSummaryCarriesTreatmentAndQualifierWithoutChangingItsSlotID() throws {
        let summary = magicSummary(
            id: "printing",
            number: "429",
            treatments: [MagicTreatment.neonInk.id],
            qualifiers: [MagicTreatment.neonInk.id: "red"]
        )
        let decoded = try JSONDecoder().decode(
            CatalogCardSummary.self,
            from: JSONEncoder().encode(summary)
        )

        XCTAssertEqual(decoded.magicTreatmentIDsRaw, ["neonink"])
        XCTAssertEqual(decoded.magicTreatmentDisplayLabel, "Neon Ink · Red")
        XCTAssertEqual(decoded.id, summary.id)
    }

    func testBrowseOwnershipRequiresTreatmentWhenTheSummarySpecifiesOne() {
        let summary = magicSummary(
            id: "fic-10",
            number: "10",
            treatments: [MagicTreatment.surgeFoil.id]
        )
        let genericFoil = magicCompletionCard(number: "10", variant: .foil)
        let treatedFoil = magicCompletionCard(
            number: "10",
            variant: .foil,
            treatments: [.surgeFoil]
        )
        let nonfoil = magicCompletionCard(number: "10", variant: .nonfoil)

        XCTAssertFalse(SetCompletionCalculator.owns(summary, cards: [genericFoil]))
        XCTAssertFalse(SetCompletionCalculator.owns(summary, cards: [nonfoil]))
        XCTAssertTrue(SetCompletionCalculator.owns(summary, cards: [treatedFoil]))
        XCTAssertEqual(
            CatalogOwnershipIndex([genericFoil, treatedFoil]).quantity(of: summary),
            1
        )
    }

    func testSetCompletionDoesNotCreateATreatmentSlotAndKeepsSuffixesDistinct() {
        let set = CatalogSet(
            catalogID: CatalogSetID(game: .magic, providerID: "fic"),
            name: "Final Fantasy Commander",
            code: "FIC",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 2,
            releaseDate: nil,
            sortRank: 1
        )
        let owned = [
            magicCompletionCard(number: "523a", variant: .foil),
            magicCompletionCard(number: "523a", variant: .foil, treatments: [.surgeFoil]),
            magicCompletionCard(number: "523b", variant: .foil)
        ]

        XCTAssertEqual(
            SetCompletionCalculator.progress(for: set, cards: owned),
            SetCompletion(owned: 2, total: 2, unit: "cards")
        )
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CollectedCard.self, PriceRecord.self, CollectionActivity.self, InventoryEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container.mainContext
    }

    private func completionCard(
        number: String,
        variant: PhysicalVariant,
        quantity: Int = 1
    ) -> CollectedCard {
        CollectedCard(
            collectionKey: "test:\(number)#\(variant.id)",
            game: .pokemon,
            providerID: "sv08.5-\(number)",
            name: "Card \(number)",
            setName: "Prismatic Evolutions",
            setCode: "PRE",
            cardNumber: number,
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: variant,
            variantResolution: .userConfirmed,
            quantity: quantity
        )
    }

    private func summary(
        id: String,
        number: String,
        treatments: [String] = []
    ) -> CatalogCardSummary {
        CatalogCardSummary(
            game: .pokemon,
            providerID: id,
            setID: CatalogSetID(game: .pokemon, providerID: "set"),
            setName: "Set",
            setCode: "SET",
            name: "Card \(number)",
            collectorNumber: number,
            thumbnailURL: nil,
            imageURL: nil,
            magicTreatmentIDsRaw: treatments
        )
    }

    private func magicSummary(
        id: String,
        number: String,
        treatments: [String] = [],
        qualifiers: [String: String] = [:]
    ) -> CatalogCardSummary {
        CatalogCardSummary(
            game: .magic,
            providerID: id,
            setID: CatalogSetID(game: .magic, providerID: "fic"),
            setName: "Final Fantasy Commander",
            setCode: "FIC",
            name: "Fixture",
            collectorNumber: number,
            thumbnailURL: nil,
            imageURL: nil,
            magicTreatmentIDsRaw: treatments,
            magicTreatmentQualifiers: qualifiers
        )
    }

    private func magicCompletionCard(
        number: String,
        variant: PhysicalVariant,
        treatments: [MagicTreatment] = []
    ) -> CollectedCard {
        CollectedCard(
            collectionKey: "magic:fic-\(number)#\(variant.id)",
            game: .magic,
            providerID: "fic-\(number)",
            name: "Fixture",
            setName: "Final Fantasy Commander",
            setCode: "FIC",
            cardNumber: number,
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: variant,
            variantResolution: .userConfirmed,
            magicTreatments: treatments
        )
    }

    private func query(
        _ cards: [CatalogCardSummary],
        sort: CatalogSetSort = .numberLowToHigh,
        ownership: CatalogOwnershipFilter = .all,
        ownedCards: [CollectedCard] = [],
        prices: [String: Double] = [:]
    ) -> [CatalogCardSummary] {
        CatalogSetQuery.apply(
            cards,
            search: "",
            sort: sort,
            ownership: ownership,
            owned: CatalogOwnershipIndex(ownedCards),
            prices: prices
        )
    }

    private func decodePokemon() throws -> TCGdexCard {
        let json = #"""
        {
          "id": "sv08.5-074", "localId": "074", "name": "Eevee",
          "image": "https://assets.tcgdex.net/en/sv/sv08.5/074", "rarity": "Common",
          "set": { "id": "sv08.5", "name": "Prismatic Evolutions", "cardCount": { "total": 180, "official": 131 } },
          "variants": { "firstEdition": false, "holo": false, "normal": true, "reverse": true }
        }
        """#
        return try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8))
    }

    private func decodeStampedGengar() throws -> TCGdexCard {
        let json = #"""
        {
          "id": "swsh11-066", "localId": "066", "name": "Gengar",
          "image": "https://assets.tcgdex.net/en/swsh/swsh11/066", "rarity": "Rare Holo",
          "set": { "id": "swsh11", "name": "Lost Origin", "cardCount": { "total": 217, "official": 196 } },
          "variants": { "firstEdition": false, "holo": true, "normal": false, "reverse": true }
        }
        """#
        return try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8))
    }

    // MARK: - Which sets were really printed twice

    /// The e-card sets never had a 1st Edition run — TCGdex reports
    /// `cardCount.firstEd == 0` for Expedition, Aquapolis and Skyridge, against
    /// non-zero counts for every set from Base Set to Neo Destiny. Splitting
    /// them invented a "Skyridge — 1st Edition" master set that never existed
    /// and cut the real set's completion across two impossible halves.
    func testECardSetsAreNotSplitIntoPrintRuns() {
        for id in ["ecard1", "ecard2", "ecard3"] {
            let set = catalogSet(id: id, name: "Skyridge")
            let runs = PokemonMasterSetDefinition.virtualSets(set)
            XCTAssertEqual(runs.count, 1, "\(id) had one print run")
            XCTAssertNil(runs[0].pokemonPrintRun)
            XCTAssertEqual(runs[0].name, "Skyridge", "no qualifier against nothing")
        }
    }

    /// Base Set 2 and Legendary Collection are the other zero-firstEd sets of
    /// the era and must not be split either.
    func testSetsWithoutAFirstEditionRunAreNotSplit() {
        for id in ["base4", "lc"] {
            XCTAssertEqual(
                PokemonMasterSetDefinition.virtualSets(catalogSet(id: id, name: "Base Set 2")).count,
                1
            )
        }
    }

    /// Base Set alone had three runs; the other nine split sets had two.
    func testPrintedTwiceSetsStillSplit() {
        let base = PokemonMasterSetDefinition.virtualSets(catalogSet(id: "base1", name: "Base Set"))
        XCTAssertEqual(base.map(\.pokemonPrintRun), [.firstEdition, .shadowless, .unlimited])

        for id in ["base2", "base3", "base5", "gym1", "gym2", "neo1", "neo2", "neo3", "neo4"] {
            let runs = PokemonMasterSetDefinition.virtualSets(catalogSet(id: id, name: "Jungle"))
            XCTAssertEqual(
                runs.map(\.pokemonPrintRun), [.firstEdition, .unlimited], "\(id) split wrongly"
            )
        }
    }

    func testScannerPrintRunChoicesUseTheSameEligibilityAsBrowse() {
        XCTAssertEqual(
            PokemonMasterSetDefinition.printRuns(forSetProviderID: "base1"),
            [.firstEdition, .shadowless, .unlimited]
        )
        XCTAssertEqual(
            PokemonMasterSetDefinition.printRuns(forSetProviderID: "GYM2"),
            [.firstEdition, .unlimited]
        )
        XCTAssertTrue(PokemonMasterSetDefinition.printRuns(forSetProviderID: "ecard3").isEmpty)
        XCTAssertTrue(PokemonMasterSetDefinition.printRuns(forSetProviderID: "lc").isEmpty)
    }

    private func catalogSet(id: String, name: String) -> CatalogSet {
        CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: id),
            name: name,
            code: name.prefix(3).uppercased(),
            logoURL: nil,
            symbolURL: nil,
            cardCount: 100,
            releaseDate: nil,
            sortRank: 1
        )
    }
}

final class PokemonChecklistBrowseTests: XCTestCase {
    func testOfflineModernPokemonCardResolvesWithoutProviderRequests() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let set = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "sv10"),
            name: "Destined Rivals",
            code: "DRI",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 182,
            releaseDate: nil,
            sortRank: 1
        )
        let summary = CatalogCardSummary(
            game: .pokemon,
            providerID: "sv10-085",
            setID: set.catalogID,
            setName: set.name,
            setCode: set.code,
            name: "Example Pokémon",
            collectorNumber: "085",
            thumbnailURL: URL(string: "https://example.com/card-small.png"),
            imageURL: URL(string: "https://example.com/card-large.png")
        )
        let snapshot = PokemonChecklistSnapshot(
            manifest: PokemonChecklistSnapshotManifest(
                schemaVersion: PokemonChecklistSnapshotVersion.schema,
                rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
                generatedAt: .now,
                directoryFingerprint: "fixture",
                entries: [PokemonChecklistSnapshotEntry(
                    set: set,
                    providerID: "sv10",
                    providerFingerprint: "fixture",
                    resource: "sets/sv10.json"
                )]
            ),
            checklists: [set.id: [summary]]
        )
        let store = PokemonChecklistStore(root: root, bundle: nil)
        try await store.publish(snapshot)
        let offline = PokemonOfflineCatalog(
            store: PokemonChecklistStore(root: root, bundle: nil)
        )

        let offlineCard = await offline.card(
            providerSetID: "SV10",
            localID: "085",
            expectedOfficialCount: 182
        )
        let card = try XCTUnwrap(offlineCard)
        XCTAssertEqual(card.id, "sv10-085")
        XCTAssertEqual(card.name, "Example Pokémon")
        XCTAssertNil(card.pricing)
        XCTAssertNil(card.variants)
        XCTAssertEqual(card.highImageURL, URL(string: "https://example.com/card-large.png"))

        let identified = IdentifiedCard.pokemon(card, setCode: "DRI")
        XCTAssertEqual(
            VariantResolver.resolve(identified.variantEvidence),
            .resolved(ResolvedVariant(variant: nil, resolution: .catalogSilent))
        )
    }

    func testOfflinePokemonCardAllowsMasterCountDifferentFromPrintedDenominator() throws {
        let set = sampleSet(id: "sv10", name: "Destined Rivals")
        let summary = CatalogCardSummary(
            game: .pokemon,
            providerID: "sv10-085",
            setID: set.catalogID,
            setName: set.name,
            setCode: set.code,
            name: "Example Pokémon",
            collectorNumber: "085",
            thumbnailURL: nil,
            imageURL: nil
        )
        let snapshot = PokemonChecklistSnapshot(
            manifest: PokemonChecklistSnapshotManifest(
                schemaVersion: PokemonChecklistSnapshotVersion.schema,
                rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
                generatedAt: .now,
                directoryFingerprint: "fixture",
                entries: [PokemonChecklistSnapshotEntry(
                    set: set,
                    providerID: "sv10",
                    providerFingerprint: "fixture",
                    resource: "sets/sv10.json"
                )]
            ),
            checklists: [set.id: [summary]]
        )

        XCTAssertNotNil(
            PokemonOfflineCardFactory.card(
                in: snapshot,
                providerSetID: "sv10",
                localID: "085",
                expectedOfficialCount: 181
            )
        )
    }

    func testOfflineHistoricalMatchingRejectsWrongPrintedDenominator() throws {
        let set = sampleSet(id: "sv09", name: "Journey Together")
        let summary = CatalogCardSummary(
            game: .pokemon,
            providerID: "sv09-085",
            setID: set.catalogID,
            setName: set.name,
            setCode: set.code,
            name: "Example Pokémon",
            collectorNumber: "085",
            thumbnailURL: nil,
            imageURL: nil
        )
        let snapshot = PokemonChecklistSnapshot(
            manifest: PokemonChecklistSnapshotManifest(
                schemaVersion: PokemonChecklistSnapshotVersion.schema,
                rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
                generatedAt: .now,
                directoryFingerprint: "fixture",
                entries: [PokemonChecklistSnapshotEntry(
                    set: set,
                    providerID: "sv09",
                    providerFingerprint: "fixture",
                    officialCount: 159,
                    resource: "sets/sv09.json"
                )]
            ),
            checklists: [set.id: [summary]]
        )
        let identifier = try XCTUnwrap(
            PokemonHistoricalScanParser.parse(
                numberLines: ["085/182"],
                titleLines: ["Example Pokémon"]
            )
        )
        guard case let .pokemonHistorical(evidence) = identifier else {
            return XCTFail("Expected historical Pokémon evidence")
        }

        XCTAssertNil(
            PokemonOfflineCardFactory.historicalCard(in: snapshot, evidence: evidence),
            "A same-number/title match from a set with the wrong denominator must not identify the card."
        )
    }

    func testOfflinePokemonCardPreservesAllPublishedVariantRows() throws {
        let set = sampleSet(id: "sv04", name: "Paradox Rift")
        let variants: [PhysicalVariant] = [.normal, .holo, .reverse, PhysicalVariant(id: "energy", label: "Energy")]
        let summaries = variants.map { variant in
            CatalogCardSummary(
                game: .pokemon,
                providerID: "sv04-085",
                setID: set.catalogID,
                setName: set.name,
                setCode: set.code,
                name: "Example Pokémon",
                collectorNumber: "085",
                thumbnailURL: nil,
                imageURL: nil,
                masterSetVariant: variant,
                isExpandedMasterSetVariant: variant.id == "energy",
                isSoleSlotForCard: false
            )
        }
        let snapshot = PokemonChecklistSnapshot(
            manifest: PokemonChecklistSnapshotManifest(
                schemaVersion: PokemonChecklistSnapshotVersion.schema,
                rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
                generatedAt: .now,
                directoryFingerprint: "fixture",
                entries: [PokemonChecklistSnapshotEntry(
                    set: set,
                    providerID: "sv04",
                    providerFingerprint: "fixture",
                    resource: "sets/sv04.json"
                )]
            ),
            checklists: [set.id: summaries]
        )

        let card = try XCTUnwrap(
            PokemonOfflineCardFactory.card(
                in: snapshot,
                providerSetID: "sv04",
                localID: "085",
                expectedOfficialCount: 182
            )
        )
        XCTAssertNil(card.pricing)
        XCTAssertEqual(
            Set(card.catalogVariants),
            Set(variants)
        )
        switch VariantResolver.resolve(
            IdentifiedCard.pokemon(card, setCode: "PAR").variantEvidence
        ) {
        case let .needsChoice(options, lockDidNotApply):
            XCTAssertNil(lockDidNotApply)
            XCTAssertEqual(Set(options), Set(variants))
        case .resolved:
            XCTFail("Multiple offline variant rows must remain a user choice.")
        }
    }

    func testOfflineModernScanUsesZeroProviderRequestsEvenWhenMasterCountDiffers() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let set = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "sv04"),
            name: "Paradox Rift",
            code: "PAR",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 250,
            releaseDate: nil,
            sortRank: 1
        )
        let summaries = ["085", "182"].map { number in
            CatalogCardSummary(
                game: .pokemon,
                providerID: "sv04-\(number)",
                setID: set.catalogID,
                setName: set.name,
                setCode: set.code,
                name: "Offline Card \(number)",
                collectorNumber: number,
                thumbnailURL: nil,
                imageURL: nil
            )
        }
        let snapshot = PokemonChecklistSnapshot(
            manifest: PokemonChecklistSnapshotManifest(
                schemaVersion: PokemonChecklistSnapshotVersion.schema,
                rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
                generatedAt: .now,
                directoryFingerprint: "fixture",
                entries: [PokemonChecklistSnapshotEntry(
                    set: set,
                    providerID: set.providerID,
                    providerFingerprint: "fixture",
                    resource: "sets/sv04.json"
                )]
            ),
            checklists: [set.id: summaries]
        )
        try await PokemonChecklistStore(root: root, bundle: nil).publish(snapshot)

        let source = CountingPokemonCardSource(
            primary: .failure(.badResponse),
            fallback: .failure(.badResponse)
        )
        let catalog = CardCatalog(
            source: source,
            offline: PokemonOfflineCatalog(
                store: PokemonChecklistStore(root: root, bundle: nil)
            ),
            resolvedDiskCache: ResolvedPokemonCardCache(
                root: root.appendingPathComponent("resolved"),
                appVersion: "test"
            ),
            tcgdexBreaker: TCGdexCircuitBreaker(cooldown: 0)
        )
        let definition = try XCTUnwrap(SetCodeMap.definitions["PAR"])
        for number in ["085", "182"] {
            let card = try await catalog.card(for: .pokemon(
                setCode: "PAR",
                cardNumber: number,
                printedTotal: definition.officialCount,
                setDefinition: definition
            ))
            XCTAssertEqual(card.name, "Offline Card \(number)")
        }
        let counts = await source.requestCounts()
        XCTAssertEqual(counts.primary, 0)
        XCTAssertEqual(counts.fallback, 0)
    }

    func testPokemonFallbackUsesSecondaryProviderOnlyAfterRetryablePrimaryFailure() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = CountingPokemonCardSource(
            primary: .failure(.badResponse),
            fallback: .card(pokemonAPIResult(setID: "sv10", number: "85"))
        )
        let catalog = CardCatalog(
            source: source,
            offline: PokemonOfflineCatalog(
                store: PokemonChecklistStore(root: root.appendingPathComponent("offline"), bundle: nil)
            ),
            resolvedDiskCache: ResolvedPokemonCardCache(
                root: root.appendingPathComponent("resolved"),
                appVersion: "test"
            ),
            tcgdexBreaker: TCGdexCircuitBreaker(cooldown: 0)
        )
        let definition = try XCTUnwrap(SetCodeMap.definitions["DRI"])
        let card = try await catalog.card(for: .pokemon(
            setCode: "DRI",
            cardNumber: "085",
            printedTotal: definition.officialCount,
            setDefinition: definition
        ))

        // The secondary provider returns `sv10-85`, but the resolved card must
        // remain addressable by TCGdex as `sv10-085` for later repricing.
        XCTAssertEqual(card.providerID, "sv10-085")
        let counts = await source.requestCounts()
        XCTAssertEqual(counts.primary, 1)
        XCTAssertEqual(counts.fallback, 1)
    }

    func testModernFallbackSuccessDoesNotClearTCGdexBreaker() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = CountingPokemonCardSource(
            primary: .failure(.badResponse),
            fallback: .card(pokemonAPIResult(setID: "sv10", number: "85"))
        )
        let breaker = TCGdexCircuitBreaker(cooldown: 60)
        let catalog = CardCatalog(
            source: source,
            offline: PokemonOfflineCatalog(
                store: PokemonChecklistStore(root: root.appendingPathComponent("offline"), bundle: nil)
            ),
            resolvedDiskCache: ResolvedPokemonCardCache(
                root: root.appendingPathComponent("resolved"),
                appVersion: "test"
            ),
            tcgdexBreaker: breaker
        )
        let definition = try XCTUnwrap(SetCodeMap.definitions["DRI"])

        _ = try await catalog.card(for: .pokemon(
            setCode: "DRI",
            cardNumber: "085",
            printedTotal: definition.officialCount,
            setDefinition: definition
        ))

        let breakerPermitted = await breaker.permitsRequest(now: Date().addingTimeInterval(1))
        XCTAssertFalse(breakerPermitted)
    }

    func testPromoFallbackSuccessDoesNotClearTCGdexBreaker() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = CountingPokemonCardSource(
            primary: .failure(.badResponse),
            fallback: .card(pokemonAPIResult(setID: "svp", number: "001"))
        )
        let breaker = TCGdexCircuitBreaker(cooldown: 60)
        let catalog = CardCatalog(
            source: source,
            offline: PokemonOfflineCatalog(
                store: PokemonChecklistStore(root: root.appendingPathComponent("offline"), bundle: nil)
            ),
            resolvedDiskCache: ResolvedPokemonCardCache(
                root: root.appendingPathComponent("resolved"),
                appVersion: "test"
            ),
            tcgdexBreaker: breaker
        )
        let definition = PokemonPromoSetDefinition(
            printedPrefix: "SVP",
            tcgdexSetID: "svp",
            catalogLocalIDPrefix: ""
        )

        _ = try await catalog.card(for: .pokemonPromo(
            prefix: "SVP",
            localID: "001",
            setDefinition: definition
        ))

        let breakerPermitted = await breaker.permitsRequest(now: Date().addingTimeInterval(1))
        XCTAssertFalse(breakerPermitted)
    }

    func testNetworkPokemonLookupDoesNotRequireProviderDenominator() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = CountingPokemonCardSource(
            primary: .card(try makeTCGdexCard(setID: "sv10", localID: "085")),
            fallback: .failure(.badResponse)
        )
        let catalog = CardCatalog(
            source: source,
            offline: PokemonOfflineCatalog(
                store: PokemonChecklistStore(root: root.appendingPathComponent("offline"), bundle: nil)
            ),
            resolvedDiskCache: ResolvedPokemonCardCache(
                root: root.appendingPathComponent("resolved"),
                appVersion: "test"
            ),
            tcgdexBreaker: TCGdexCircuitBreaker(cooldown: 0)
        )
        let definition = try XCTUnwrap(SetCodeMap.definitions["DRI"])
        let card = try await catalog.card(for: .pokemon(
            setCode: "DRI",
            cardNumber: "085",
            printedTotal: definition.officialCount,
            setDefinition: definition
        ))

        XCTAssertEqual(card.providerID, "sv10-085")
        let counts = await source.requestCounts()
        XCTAssertEqual(counts.primary, 1)
        XCTAssertEqual(counts.fallback, 0)
    }

    func testPokemonCardNotFoundDoesNotFallThroughToSecondaryProvider() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = CountingPokemonCardSource(
            primary: .failure(.cardNotFound),
            fallback: .card(pokemonAPIResult(setID: "sv10", number: "85"))
        )
        let catalog = CardCatalog(
            source: source,
            offline: PokemonOfflineCatalog(
                store: PokemonChecklistStore(root: root.appendingPathComponent("offline"), bundle: nil)
            ),
            resolvedDiskCache: ResolvedPokemonCardCache(
                root: root.appendingPathComponent("resolved"),
                appVersion: "test"
            ),
            tcgdexBreaker: TCGdexCircuitBreaker(cooldown: 0)
        )
        let definition = try XCTUnwrap(SetCodeMap.definitions["DRI"])

        do {
            _ = try await catalog.card(for: .pokemon(
                setCode: "DRI",
                cardNumber: "085",
                printedTotal: definition.officialCount,
                setDefinition: definition
            ))
            XCTFail("Expected terminal card-not-found")
        } catch {
            XCTAssertEqual(CardCatalog.classify(error), .notInCatalog)
        }
        let counts = await source.requestCounts()
        XCTAssertEqual(counts.primary, 1)
        XCTAssertEqual(counts.fallback, 0)
    }

    func testVariantlessResolvedCacheFallsThroughToTheOfflineVariantChecklist() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheRoot = root.appendingPathComponent("resolved")
        let offlineRoot = root.appendingPathComponent("offline")
        let definition = try XCTUnwrap(SetCodeMap.definitions["DRI"])
        let key = "pokemon|sv10|085|\(definition.officialCount)"

        // Simulate a cache entry with the right identity but no finish
        // evidence, exactly as an outage-time fallback used to save.
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let storedAt = ISO8601DateFormatter().string(from: .now)
        let staleFile = """
        {"appVersion":"test","schemaGeneration":2,"entries":[
          {"key":"\(key)","storedAt":"\(storedAt)","cardID":"sv10-085","localID":"085","name":"Stale cache card","image":null,"rarity":null,"setID":"sv10","setName":"Destined Rivals","officialCount":\(definition.officialCount),"setCode":"DRI","variants":[]}
        ]}
        """
        try Data(staleFile.utf8).write(to: cacheRoot.appendingPathComponent("ResolvedPokemonCards.json"))

        let set = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "sv10"),
            name: "Destined Rivals",
            code: "DRI",
            logoURL: nil,
            symbolURL: nil,
            cardCount: definition.officialCount,
            releaseDate: nil,
            sortRank: 1
        )
        let summaries: [CatalogCardSummary] = [.normal, .reverse].map { variant in
            CatalogCardSummary(
                game: .pokemon,
                providerID: "sv10-085",
                setID: set.catalogID,
                setName: set.name,
                setCode: set.code,
                name: "Checklist card",
                collectorNumber: "085",
                thumbnailURL: nil,
                imageURL: nil,
                masterSetVariant: variant,
                isExpandedMasterSetVariant: false,
                isSoleSlotForCard: false
            )
        }
        try await writeSnapshot([set: summaries], to: offlineRoot)

        let source = CountingPokemonCardSource(
            primary: .failure(.badResponse),
            fallback: .failure(.badResponse)
        )
        let cache = ResolvedPokemonCardCache(root: cacheRoot, appVersion: "test")
        let catalog = CardCatalog(
            source: source,
            offline: PokemonOfflineCatalog(
                store: PokemonChecklistStore(root: offlineRoot, bundle: nil)
            ),
            resolvedDiskCache: cache,
            tcgdexBreaker: TCGdexCircuitBreaker(cooldown: 0)
        )
        let identifier = ScanIdentifier.pokemon(
            setCode: "DRI",
            cardNumber: "085",
            printedTotal: definition.officialCount,
            setDefinition: definition
        )

        let card = try await catalog.card(for: identifier)

        XCTAssertEqual(card.name, "Checklist card")
        XCTAssertEqual(Set(card.variantEvidence.catalogVariants), Set([.normal, .reverse]))
        switch VariantResolver.resolve(card.variantEvidence) {
        case let .needsChoice(options, _):
            XCTAssertEqual(Set(options), Set([.normal, .reverse]))
        case .resolved:
            XCTFail("A richer offline checklist must reopen the finish picker.")
        }
        let counts = await source.requestCounts()
        XCTAssertEqual(counts.primary, 0)
        XCTAssertEqual(counts.fallback, 0)
        let healedCacheEntry = await cache.card(for: key)
        XCTAssertNil(healedCacheEntry, "variant-less entries self-heal on the next scan")
    }

    func testPriorGenerationResolvedCacheIsIgnored() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheRoot = root.appendingPathComponent("resolved")
        let definition = try XCTUnwrap(SetCodeMap.definitions["DRI"])
        let key = "pokemon|sv10|085|\(definition.officialCount)"

        // A complete entry from the prior format must not survive the schema
        // invalidation merely because it contains usable variant evidence.
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let storedAt = ISO8601DateFormatter().string(from: .now)
        let oldGenerationFile = """
        {"appVersion":"test","schemaGeneration":1,"entries":[
          {"key":"\(key)","storedAt":"\(storedAt)","cardID":"sv10-085","localID":"085","name":"Old generation card","image":null,"rarity":null,"setID":"sv10","setName":"Destined Rivals","officialCount":\(definition.officialCount),"setCode":"DRI","variants":[{"id":"normal","label":"Non-Holo"},{"id":"reverse","label":"Reverse Holo"}]}
        ]}
        """
        try Data(oldGenerationFile.utf8).write(
            to: cacheRoot.appendingPathComponent("ResolvedPokemonCards.json")
        )

        let cache = ResolvedPokemonCardCache(root: cacheRoot, appVersion: "test")
        let cachedEntry = await cache.card(for: key)

        XCTAssertNil(cachedEntry, "A prior cache generation must always be treated as a miss.")
    }

    func testVariantlessStorePreservesAnExistingResolvedCard() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let definition = try XCTUnwrap(SetCodeMap.definitions["DRI"])
        let key = "pokemon|sv10|085|\(definition.officialCount)"
        let cache = ResolvedPokemonCardCache(
            root: root.appendingPathComponent("resolved"),
            appVersion: "test"
        )
        let completeCard = try makeTCGdexCard(setID: "sv10", localID: "085")
        let incompleteCard = try decode(TCGdexCard.self, from: """
        {"id":"sv10-085","localId":"085","name":"Incomplete Card","image":null,
         "set":{"id":"sv10","name":"Destined Rivals","cardCount":{"total":\(definition.officialCount),"official":\(definition.officialCount)}}}
        """)

        await cache.store(
            card: completeCard,
            setCode: "DRI",
            key: key,
            officialCount: definition.officialCount
        )
        await cache.store(
            card: incompleteCard,
            setCode: "DRI",
            key: key,
            officialCount: definition.officialCount
        )
        let storedEntry = await cache.card(for: key)
        let cachedEntry = try XCTUnwrap(storedEntry)

        XCTAssertEqual(cachedEntry.card.name, "Resolved Card")
        XCTAssertEqual(
            Set(cachedEntry.card.catalogVariants),
            Set([.normal, .reverse]),
            "A variant-less response must not evict an existing complete cache entry."
        )
    }

    func testResolvedPokemonIdentitySurvivesAColdCatalogInstance() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheRoot = root.appendingPathComponent("resolved")
        let definition = try XCTUnwrap(SetCodeMap.definitions["DRI"])
        let firstSource = CountingPokemonCardSource(
            primary: .card(try makeTCGdexCard(setID: "sv10", localID: "085")),
            fallback: .failure(.badResponse)
        )
        let first = CardCatalog(
            source: firstSource,
            offline: PokemonOfflineCatalog(
                store: PokemonChecklistStore(root: root.appendingPathComponent("offline"), bundle: nil)
            ),
            resolvedDiskCache: ResolvedPokemonCardCache(root: cacheRoot, appVersion: "test"),
            tcgdexBreaker: TCGdexCircuitBreaker(cooldown: 0)
        )
        let identifier = ScanIdentifier.pokemon(
            setCode: "DRI",
            cardNumber: "085",
            printedTotal: definition.officialCount,
            setDefinition: definition
        )
        _ = try await first.card(for: identifier)

        let secondSource = CountingPokemonCardSource(
            primary: .failure(.badResponse),
            fallback: .failure(.badResponse)
        )
        let second = CardCatalog(
            source: secondSource,
            offline: PokemonOfflineCatalog(
                store: PokemonChecklistStore(root: root.appendingPathComponent("offline"), bundle: nil)
            ),
            resolvedDiskCache: ResolvedPokemonCardCache(root: cacheRoot, appVersion: "test"),
            tcgdexBreaker: TCGdexCircuitBreaker(cooldown: 0)
        )
        let card = try await second.card(for: identifier)

        XCTAssertEqual(card.providerID, "sv10-085")
        let counts = await secondSource.requestCounts()
        XCTAssertEqual(counts.primary, 0)
        XCTAssertEqual(counts.fallback, 0)
    }

    func testSessionCatalogCachePreservesOriginalResolutionTime() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let definition = try XCTUnwrap(SetCodeMap.definitions["DRI"])
        let source = CountingPokemonCardSource(
            primary: .card(try makeTCGdexCard(setID: "sv10", localID: "085")),
            fallback: .failure(.badResponse)
        )
        let catalog = CardCatalog(
            source: source,
            offline: PokemonOfflineCatalog(
                store: PokemonChecklistStore(root: root.appendingPathComponent("offline"), bundle: nil)
            ),
            resolvedDiskCache: ResolvedPokemonCardCache(
                root: root.appendingPathComponent("resolved"),
                appVersion: "test"
            ),
            tcgdexBreaker: TCGdexCircuitBreaker(cooldown: 0)
        )
        let identifier = ScanIdentifier.pokemon(
            setCode: "DRI",
            cardNumber: "085",
            printedTotal: definition.officialCount,
            setDefinition: definition
        )

        let first = try await catalog.resolution(for: identifier)
        let second = try await catalog.resolution(for: identifier)

        XCTAssertEqual(first.retrievedAt, second.retrievedAt)
        let counts = await source.requestCounts()
        XCTAssertEqual(counts.primary, 1)
    }

    private func makeTCGdexCard(setID: String, localID: String) throws -> TCGdexCard {
        try decode(TCGdexCard.self, from: """
        {"id":"\(setID)-\(localID)","localId":"\(localID)","name":"Resolved Card","image":null,
         "set":{"id":"\(setID)","name":"Resolved Set","cardCount":{"total":1,"official":1}},
         "variants":{"firstEdition":false,"holo":false,"normal":true,"reverse":true}}
        """)
    }

    private func pokemonAPIResult(setID: String, number: String) -> PokemonTCGAPICard {
        PokemonTCGAPICard(
            id: "\(setID)-\(CatalogIdentityNormalization.localNumber(number))",
            name: "Fallback Card",
            number: number,
            set: PokemonTCGAPISet(id: setID, name: "Fallback Set", printedTotal: nil),
            images: PokemonTCGAPIImages(
                small: URL(string: "https://example.com/small.png")!,
                large: URL(string: "https://example.com/large.png")!
            )
        )
    }

    func testTCGdexCircuitBreakerSuppressesRequestsDuringCooldown() async {
        let breaker = TCGdexCircuitBreaker(cooldown: 10)
        let now = Date(timeIntervalSince1970: 10_000)

        let initiallyPermitted = await breaker.permitsRequest(now: now)
        XCTAssertTrue(initiallyPermitted)
        await breaker.recordFailure(now: now)
        let blockedDuringCooldown = await breaker.permitsRequest(now: now.addingTimeInterval(1))
        XCTAssertFalse(blockedDuringCooldown)
        let permittedAfterCooldown = await breaker.permitsRequest(now: now.addingTimeInterval(11))
        XCTAssertTrue(permittedAfterCooldown)
    }

    func testBundledChecklistOpensOfflineWithoutCatalogRequests() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundledRoot = root.appendingPathComponent("bundled", isDirectory: true)
        let downloadedRoot = root.appendingPathComponent("downloaded", isDirectory: true)
        let set = sampleSet(id: "sv08.5", name: "Prismatic Evolutions")
        let card = sampleSummary(set: set, name: "Eevee")
        try await writeSnapshot([set: [card]], to: bundledRoot)

        let transport = FakePokemonBrowseTransport()
        let store = PokemonChecklistStore(
            root: downloadedRoot,
            bundle: nil,
            bundledRoot: bundledRoot
        )
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport,
            checklistStore: store
        )

        let sets = try await catalog.sets(for: .pokemon)
        let page = try await catalog.cards(in: try XCTUnwrap(sets.first), cursor: nil)

        XCTAssertEqual(sets, [set])
        XCTAssertEqual(page.items, [card])
        let counts = await transport.requestCounts()
        XCTAssertEqual(counts.directory, 0)
        XCTAssertEqual(counts.set, 0)
        XCTAssertEqual(counts.card, 0)
    }

    func testDownloadedChecklistOverridesBundledAndSurvivesNewCatalogInstance() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundledRoot = root.appendingPathComponent("bundled", isDirectory: true)
        let downloadedRoot = root.appendingPathComponent("downloaded", isDirectory: true)
        let bundledSet = sampleSet(id: "sv08.5", name: "Bundled Name")
        let downloadedSet = sampleSet(id: "sv08.5", name: "Refreshed Name")
        try await writeSnapshot(
            [bundledSet: [sampleSummary(set: bundledSet, name: "Bundled Card")]],
            to: bundledRoot
        )
        try await writeSnapshot(
            [downloadedSet: [sampleSummary(set: downloadedSet, name: "Refreshed Card")]],
            to: downloadedRoot
        )

        let transport = FakePokemonBrowseTransport()
        let store = PokemonChecklistStore(root: downloadedRoot, bundle: nil, bundledRoot: bundledRoot)
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport,
            checklistStore: store
        )
        let sets = try await catalog.sets(for: .pokemon)
        let page = try await catalog.cards(in: try XCTUnwrap(sets.first), cursor: nil)

        XCTAssertEqual(sets.first?.name, "Refreshed Name")
        XCTAssertEqual(page.items.first?.name, "Refreshed Card")
        let counts = await transport.requestCounts()
        XCTAssertEqual(counts.directory, 0)

        let secondStore = PokemonChecklistStore(root: downloadedRoot, bundle: nil, bundledRoot: bundledRoot)
        let secondCatalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages-2")),
            pokemonTransport: transport,
            checklistStore: secondStore
        )
        let secondSets = try await secondCatalog.sets(for: .pokemon)
        XCTAssertEqual(secondSets.first?.name, "Refreshed Name")
    }

    func testOneProviderCardFetchFeedsEveryVirtualPrintRun() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let row = try decode(TCGdexBrowseSet.self, from: """
        {"id":"base1","name":"Base Set","cardCount":{"total":1,"official":1}}
        """)
        let provider = try decode(TCGdexSetCatalog.self, from: """
        {"id":"base1","name":"Base Set","cards":[{"id":"base1-001","localId":"001","name":"Alakazam","image":null}],"cardCount":{"total":1,"official":1,"normal":1,"reverse":0,"holo":0,"firstEd":1}}
        """)
        let detail = try decode(TCGdexCard.self, from: """
        {"id":"base1-001","localId":"001","name":"Alakazam","image":null,"set":{"id":"base1","name":"Base Set","cardCount":{"total":1,"official":1}},"variants":{"firstEdition":true,"holo":true,"normal":false,"reverse":false,"wPromo":false}}
        """)
        let transport = FakePokemonBrowseTransport(
            rows: [row],
            sets: ["base1": provider],
            cards: ["base1-001": detail]
        )
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport,
            checklistStore: PokemonChecklistStore(root: root.appendingPathComponent("checklists"), bundle: nil)
        )

        let sets = try await catalog.sets(for: .pokemon)
        XCTAssertEqual(sets.count, 3)
        for set in sets { _ = try await catalog.cards(in: set, cursor: nil) }

        let counts = await transport.requestCounts()
        XCTAssertEqual(counts.set, 1)
        XCTAssertEqual(counts.card, 1)
    }

    func testCatalogDetailsCoalescesVariantRequestsAndPreservesVariantPrices() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let row = try decode(TCGdexBrowseSet.self, from: """
        {"id":"sv08.5","name":"Prismatic Evolutions","tcgOnline":"PRE","cardCount":{"total":1,"official":1}}
        """)
        let provider = try decode(TCGdexSetCatalog.self, from: """
        {"id":"sv08.5","name":"Prismatic Evolutions","cards":[],"cardCount":{"total":1,"official":1}}
        """)
        let detail = try decode(TCGdexCard.self, from: """
        {
          "id":"sv08.5-001","localId":"001","name":"Eevee","image":null,
          "set":{"id":"sv08.5","name":"Prismatic Evolutions","cardCount":{"total":1,"official":1}},
          "variants":{"firstEdition":false,"holo":false,"normal":true,"reverse":true,"wPromo":false},
          "variants_detailed":[
            {"type":"normal","size":"standard","languages":["en"],"pricing":{"tcgplayer":{"normal":{"marketPrice":1.25}}}},
            {"type":"reverse","size":"standard","languages":["en"],"pricing":{"tcgplayer":{"reverse-holofoil":{"marketPrice":7.5}}}}
          ]
        }
        """)
        let transport = FakePokemonBrowseTransport(
            rows: [row],
            sets: ["sv08.5": provider],
            cards: [detail.id: detail]
        )
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport,
            checklistStore: PokemonChecklistStore(
                root: root.appendingPathComponent("checklists"),
                bundle: nil
            )
        )
        let loadedSets = try await catalog.sets(for: .pokemon)
        let set = try XCTUnwrap(loadedSets.first)
        let normal = CatalogCardSummary(
            game: .pokemon,
            providerID: detail.id,
            setID: set.catalogID,
            setName: set.name,
            setCode: set.code,
            name: detail.name,
            collectorNumber: detail.localId,
            thumbnailURL: nil,
            imageURL: nil,
            masterSetVariant: .normal,
            isSoleSlotForCard: false
        )
        let reverse = CatalogCardSummary(
            game: .pokemon,
            providerID: detail.id,
            setID: set.catalogID,
            setName: set.name,
            setCode: set.code,
            name: detail.name,
            collectorNumber: detail.localId,
            thumbnailURL: nil,
            imageURL: nil,
            masterSetVariant: .reverse,
            isSoleSlotForCard: false
        )

        async let normalDetails = catalog.details(for: normal)
        async let reverseDetails = catalog.details(for: reverse)
        _ = try await (normalDetails, reverseDetails)

        var lastPrices: [String: Double] = [:]
        for await prices in catalog.sortPrices(for: [normal, reverse]) {
            lastPrices = prices
        }

        XCTAssertEqual(lastPrices[normal.id], 1.25)
        XCTAssertEqual(lastPrices[reverse.id], 7.5)
        let counts = await transport.requestCounts()
        XCTAssertEqual(counts.card, 1)
    }

    /// The price prefetch runs on the first page, so a later request routinely
    /// covers fewer slots than the stored map. Writing that narrower map back
    /// would truncate a fully priced set to one page on every cold open, which
    /// is exactly the relaunch cost the sort-price cache exists to remove.
    func testNarrowerSortPriceRequestDoesNotTruncateTheStoredMap() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pagesRoot = root.appendingPathComponent("pages")
        let row = try decode(TCGdexBrowseSet.self, from: """
        {"id":"sv08.5","name":"Prismatic Evolutions","tcgOnline":"PRE","cardCount":{"total":2,"official":2}}
        """)
        let provider = try decode(TCGdexSetCatalog.self, from: """
        {"id":"sv08.5","name":"Prismatic Evolutions","cards":[],"cardCount":{"total":2,"official":2}}
        """)
        func card(id: String, localId: String, price: Double) throws -> TCGdexCard {
            try decode(TCGdexCard.self, from: """
            {
              "id":"\(id)","localId":"\(localId)","name":"Eevee","image":null,
              "set":{"id":"sv08.5","name":"Prismatic Evolutions","cardCount":{"total":2,"official":2}},
              "variants":{"firstEdition":false,"holo":false,"normal":true,"reverse":false,"wPromo":false},
              "variants_detailed":[
                {"type":"normal","size":"standard","languages":["en"],"pricing":{"tcgplayer":{"normal":{"marketPrice":\(price)}}}}
              ]
            }
            """)
        }
        let first = try card(id: "sv08.5-001", localId: "001", price: 1.25)
        let second = try card(id: "sv08.5-002", localId: "002", price: 9.0)
        let transport = FakePokemonBrowseTransport(
            rows: [row],
            sets: ["sv08.5": provider],
            cards: [first.id: first, second.id: second]
        )

        func makeCatalog() -> BrowseCatalog {
            BrowseCatalog(
                cache: CatalogCacheStore(root: pagesRoot),
                pokemonTransport: transport,
                checklistStore: PokemonChecklistStore(
                    root: root.appendingPathComponent("checklists"),
                    bundle: nil
                )
            )
        }

        let warmCatalog = makeCatalog()
        let loadedSets = try await warmCatalog.sets(for: .pokemon)
        let set = try XCTUnwrap(loadedSets.first)
        func summary(for detail: TCGdexCard) -> CatalogCardSummary {
            CatalogCardSummary(
                game: .pokemon,
                providerID: detail.id,
                setID: set.catalogID,
                setName: set.name,
                setCode: set.code,
                name: detail.name,
                collectorNumber: detail.localId,
                thumbnailURL: nil,
                imageURL: nil,
                masterSetVariant: .normal,
                isSoleSlotForCard: true
            )
        }
        let firstSlot = summary(for: first)
        let secondSlot = summary(for: second)

        for await _ in warmCatalog.sortPrices(for: [firstSlot, secondSlot]) {}
        let fullMap = await CatalogCacheStore(root: pagesRoot).sortPrices(for: set.catalogID.id)
        XCTAssertEqual(fullMap?.value[firstSlot.id], 1.25)
        XCTAssertEqual(fullMap?.value[secondSlot.id], 9.0)
        let warmCardRequests = await transport.requestCounts().card

        // A cold catalog sharing the same cache directory, asked for one slot.
        let coldCatalog = makeCatalog()
        for await _ in coldCatalog.sortPrices(for: [firstSlot]) {}

        let mergedMap = await CatalogCacheStore(root: pagesRoot).sortPrices(for: set.catalogID.id)
        XCTAssertEqual(mergedMap?.value[firstSlot.id], 1.25)
        XCTAssertEqual(
            mergedMap?.value[secondSlot.id],
            9.0,
            "The unrequested slot's ordering hint must survive a narrower request"
        )
        let coldCardRequests = await transport.requestCounts().card
        XCTAssertEqual(
            coldCardRequests,
            warmCardRequests,
            "A fresh cached price must not be re-fetched"
        )
    }

    func testSortPriceStreamPublishesIncrementallyForSlowLargeFixture() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let row = try decode(TCGdexBrowseSet.self, from: """
        {"id":"fixture","name":"Slow Fixture","cardCount":{"total":60,"official":60}}
        """)
        let provider = try decode(TCGdexSetCatalog.self, from: """
        {"id":"fixture","name":"Slow Fixture","cards":[],"cardCount":{"total":60,"official":60}}
        """)
        var cards: [String: TCGdexCard] = [:]
        var summaries: [CatalogCardSummary] = []
        for index in 0..<60 {
            let providerID = "fixture-\(String(format: "%03d", index + 1))"
            let detail = try decode(TCGdexCard.self, from: """
            {"id":"\(providerID)","localId":"\(String(format: "%03d", index + 1))","name":"Card \(index)","image":null,
             "set":{"id":"fixture","name":"Slow Fixture","cardCount":{"total":60,"official":60}},
             "variants":{"firstEdition":false,"holo":false,"normal":true,"reverse":false,"wPromo":false},
             "pricing":{"tcgplayer":{"normal":{"marketPrice":\(Double(index + 1))}}}}
            """)
            cards[providerID] = detail
            summaries.append(
                CatalogCardSummary(
                    game: .pokemon,
                    providerID: providerID,
                    setID: CatalogSetID(game: .pokemon, providerID: "fixture"),
                    setName: "Slow Fixture",
                    setCode: "FIX",
                    name: detail.name,
                    collectorNumber: detail.localId,
                    thumbnailURL: nil,
                    imageURL: nil,
                    masterSetVariant: .normal,
                    isSoleSlotForCard: true
                )
            )
        }

        let transport = FakePokemonBrowseTransport(
            rows: [row],
            sets: ["fixture": provider],
            cards: cards,
            cardDelayNanoseconds: 60_000_000
        )
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport,
            checklistStore: PokemonChecklistStore(
                root: root.appendingPathComponent("checklists"),
                bundle: nil
            )
        )

        var emissions: [[String: Double]] = []
        for await prices in catalog.sortPrices(for: summaries) {
            emissions.append(prices)
        }

        XCTAssertGreaterThanOrEqual(emissions.count, 2)
        let expected = Dictionary(uniqueKeysWithValues: summaries.enumerated().map {
            ($0.element.id, Double($0.offset + 1))
        })
        XCTAssertEqual(emissions.last, expected)
    }

    func testCancellingSortPriceStreamCancelsInFlightProviderWork() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let row = try decode(TCGdexBrowseSet.self, from: """
        {"id":"fixture","name":"Slow Fixture","cardCount":{"total":1,"official":1}}
        """)
        let provider = try decode(TCGdexSetCatalog.self, from: """
        {"id":"fixture","name":"Slow Fixture","cards":[],"cardCount":{"total":1,"official":1}}
        """)
        let detail = try decode(TCGdexCard.self, from: """
        {"id":"fixture-001","localId":"001","name":"Card","image":null,
         "set":{"id":"fixture","name":"Slow Fixture","cardCount":{"total":1,"official":1}},
         "variants":{"firstEdition":false,"holo":false,"normal":true,"reverse":false,"wPromo":false},
         "pricing":{"tcgplayer":{"normal":{"marketPrice":1.0}}}}
        """)
        let transport = FakePokemonBrowseTransport(
            rows: [row],
            sets: ["fixture": provider],
            cards: [detail.id: detail],
            cardDelayNanoseconds: 5_000_000_000
        )
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport,
            checklistStore: PokemonChecklistStore(
                root: root.appendingPathComponent("checklists"),
                bundle: nil
            )
        )
        let summary = CatalogCardSummary(
            game: .pokemon,
            providerID: detail.id,
            setID: CatalogSetID(game: .pokemon, providerID: "fixture"),
            setName: "Slow Fixture",
            setCode: "FIX",
            name: detail.name,
            collectorNumber: detail.localId,
            thumbnailURL: nil,
            imageURL: nil,
            masterSetVariant: .normal,
            isSoleSlotForCard: true
        )

        let consumer = Task {
            for await _ in catalog.sortPrices(for: [summary]) { }
        }
        var requestStarted = false
        for _ in 0..<100 {
            if await transport.requestCounts().card > 0 {
                requestStarted = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(requestStarted)
        consumer.cancel()
        await consumer.value

        var cancelled = 0
        for _ in 0..<200 {
            cancelled = await transport.cancelledCardRequestCount()
            if cancelled > 0 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThan(cancelled, 0)
    }

    func testCancellingOneSharedDetailWaiterDoesNotCancelTheOther() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let row = try decode(TCGdexBrowseSet.self, from: """
        {"id":"fixture","name":"Slow Fixture","cardCount":{"total":1,"official":1}}
        """)
        let provider = try decode(TCGdexSetCatalog.self, from: """
        {"id":"fixture","name":"Slow Fixture","cards":[],"cardCount":{"total":1,"official":1}}
        """)
        let detail = try decode(TCGdexCard.self, from: """
        {"id":"fixture-001","localId":"001","name":"Card","image":null,
         "set":{"id":"fixture","name":"Slow Fixture","cardCount":{"total":1,"official":1}},
         "variants":{"firstEdition":false,"holo":false,"normal":true,"reverse":false,"wPromo":false},
         "pricing":{"tcgplayer":{"normal":{"marketPrice":1.0}}}}
        """)
        let transport = FakePokemonBrowseTransport(
            rows: [row],
            sets: ["fixture": provider],
            cards: [detail.id: detail],
            cardDelayNanoseconds: 300_000_000
        )
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport,
            checklistStore: PokemonChecklistStore(
                root: root.appendingPathComponent("checklists"),
                bundle: nil
            )
        )
        let summary = CatalogCardSummary(
            game: .pokemon,
            providerID: detail.id,
            setID: CatalogSetID(game: .pokemon, providerID: "fixture"),
            setName: "Slow Fixture",
            setCode: "FIX",
            name: detail.name,
            collectorNumber: detail.localId,
            thumbnailURL: nil,
            imageURL: nil,
            masterSetVariant: .normal,
            isSoleSlotForCard: true
        )

        let cancelledWaiter = Task { try await catalog.details(for: summary) }
        var requestStarted = false
        for _ in 0..<100 {
            if await transport.requestCounts().card > 0 {
                requestStarted = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(requestStarted)

        let survivingWaiter = Task { try await catalog.details(for: summary) }
        try await Task.sleep(nanoseconds: 20_000_000)
        cancelledWaiter.cancel()

        let cancelledResult = await cancelledWaiter.result
        guard case let .failure(error) = cancelledResult else {
            return XCTFail("The cancelled waiter should not receive a detail result")
        }
        XCTAssertTrue(error is CancellationError)

        let survivingResult = await survivingWaiter.result
        guard case .success = survivingResult else {
            return XCTFail("The remaining waiter should receive the shared detail result")
        }
        let cardRequestCount = await transport.requestCounts().card
        let cancelledCardRequestCount = await transport.cancelledCardRequestCount()
        XCTAssertEqual(cardRequestCount, 1)
        XCTAssertEqual(cancelledCardRequestCount, 0)
    }

    func testBuilderPreservesStandardAndExpandedVariantSlots() throws {
        let provider = try decode(TCGdexSetCatalog.self, from: """
        {
          "id":"sv08.5","name":"Prismatic Evolutions",
          "cards":[{"id":"sv08.5-001","localId":"001","name":"Eevee","image":null}],
          "cardCount":{"total":1,"official":1,"normal":1,"reverse":1,"holo":0,"firstEd":0}
        }
        """)
        let detail = try decode(TCGdexCard.self, from: """
        {
          "id":"sv08.5-001","localId":"001","name":"Eevee","image":null,
          "set":{"id":"sv08.5","name":"Prismatic Evolutions","cardCount":{"total":1,"official":1}},
          "variants":{"firstEdition":false,"holo":false,"normal":true,"reverse":true,"wPromo":false},
          "variants_detailed":[
            {"type":"normal","size":"standard","languages":["en"]},
            {"type":"reverse","foil":"pokeball","size":"standard","languages":["en"]},
            {"type":"reverse","foil":"masterball","size":"standard","languages":["en"]}
          ]
        }
        """)

        let built = try XCTUnwrap(
            try PokemonMasterSetChecklistBuilder.build(
                providerSet: provider,
                baseSet: sampleSet(id: "sv08.5", name: "Prismatic Evolutions"),
                cardDetails: [detail.id: detail]
            ).first
        )

        XCTAssertEqual(built.cards.filter { !$0.isExpandedMasterSetVariant }.count, 2)
        XCTAssertEqual(built.cards.filter(\.isExpandedMasterSetVariant).count, 2)
        XCTAssertEqual(built.standardSlotCount, 2)
        XCTAssertEqual(built.expandedSlotCount, 4)
        XCTAssertEqual(Set(built.cards.compactMap { $0.masterSetVariant?.id }), Set([
            PhysicalVariant.normal.id,
            PhysicalVariant.reverse.id,
            PhysicalVariant.pokemonFoilPattern("pokeball").id,
            PhysicalVariant.pokemonFoilPattern("masterball").id
        ]))
    }

    func testSnapshotEntryDecodesLegacyManifestWithoutSlotCounts() throws {
        let set = sampleSet(id: "legacy", name: "Legacy Set")
        let entry = PokemonChecklistSnapshotEntry(
            set: set,
            providerID: set.providerID,
            providerFingerprint: "fixture",
            officialCount: 12,
            standardSlotCount: 3,
            expandedSlotCount: 4,
            resource: "sets/legacy.json"
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(entry)
            ) as? [String: Any]
        )
        object.removeValue(forKey: "standardSlotCount")
        object.removeValue(forKey: "expandedSlotCount")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            PokemonChecklistSnapshotEntry.self,
            from: legacyData
        )
        XCTAssertNil(decoded.standardSlotCount)
        XCTAssertNil(decoded.expandedSlotCount)
        XCTAssertTrue(
            PokemonChecklistSnapshotManifest(
                schemaVersion: PokemonChecklistSnapshotVersion.schema,
                rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
                generatedAt: .now,
                directoryFingerprint: "fixture",
                entries: [decoded]
            ).isSupported
        )
    }

    func testBundledChecklistManifestCarriesDirectoryDenominatorParity() async throws {
        let root = try makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PokemonChecklistStore(root: root, bundle: Bundle.main)
        let optionalSnapshot = await store.bundledSnapshot()
        let snapshot = try XCTUnwrap(optionalSnapshot)
        XCTAssertEqual(snapshot.manifest.entries.count, 157)
        XCTAssertTrue(
            snapshot.manifest.entries.allSatisfy {
                $0.standardSlotCount != nil && $0.expandedSlotCount != nil
            }
        )

        let builder = CatalogSetCompletionBuilder(checklistStore: store)
        let sets = snapshot.manifest.entries.map(\.set)
        let standard = await builder.build(
            sets: sets,
            ownership: CatalogOwnershipIndex(rows: []),
            tier: .standard
        )
        let expanded = await builder.build(
            sets: sets,
            ownership: CatalogOwnershipIndex(rows: []),
            tier: .expanded
        )

        for entry in snapshot.manifest.entries {
            let optionalChecklist = await store.mergedChecklist(for: entry.set.catalogID)
            let checklist = try XCTUnwrap(optionalChecklist)
            let standardSlots = checklist.filter { !$0.isExpandedMasterSetVariant }
            let standardCompletion = try XCTUnwrap(
                standard.completion(for: entry.set, tier: .standard)
            )
            let expandedCompletion = try XCTUnwrap(
                expanded.completion(for: entry.set, tier: .expanded)
            )
            XCTAssertEqual(
                standardCompletion.total,
                standardSlots.count,
                "standard denominator drifted for \(entry.providerID)"
            )
            XCTAssertEqual(
                expandedCompletion.total,
                checklist.count,
                "expanded denominator drifted for \(entry.providerID)"
            )
        }
    }

    func testCatalogSetCompletionCapsExactChecklistReadsAtFortyCandidates() async {
        var sets: [CatalogSet] = []
        var entries: [PokemonChecklistSnapshotEntry] = []
        var checklists: [String: [CatalogCardSummary]] = [:]
        var ownedCards: [CollectedCard] = []

        for index in 0..<41 {
            let providerID = "fixture\(index)"
            let code = "F\(index)"
            let set = CatalogSet(
                catalogID: CatalogSetID(game: .pokemon, providerID: providerID),
                name: "Fixture \(index)",
                code: code,
                logoURL: nil,
                symbolURL: nil,
                cardCount: 99,
                releaseDate: nil,
                sortRank: index
            )
            let slot = CatalogCardSummary(
                game: .pokemon,
                providerID: "\(providerID)-001",
                setID: set.catalogID,
                setName: set.name,
                setCode: set.code,
                name: "Card \(index)",
                collectorNumber: "001",
                thumbnailURL: nil,
                imageURL: nil,
                masterSetVariant: .normal,
                isSoleSlotForCard: true
            )
            let entry = PokemonChecklistSnapshotEntry(
                set: set,
                providerID: providerID,
                providerFingerprint: "fixture",
                officialCount: 99,
                standardSlotCount: 1,
                expandedSlotCount: 1,
                resource: "sets/\(providerID).json"
            )
            let owned = completionCard(number: "001", variant: .normal)
            owned.collectionKey = "overflow-\(index)"
            owned.providerID = slot.providerID
            owned.setName = set.name
            owned.setCode = set.code

            sets.append(set)
            entries.append(entry)
            checklists[set.id] = [slot]
            ownedCards.append(owned)

            if index == 40 {
                let secondOwned = completionCard(number: "002", variant: .normal)
                secondOwned.collectionKey = "priority-\(index)"
                secondOwned.providerID = "\(providerID)-002"
                secondOwned.setName = set.name
                secondOwned.setCode = set.code
                ownedCards.append(secondOwned)
            }
        }

        let checklistStore = CountingChecklistStore(
            entries: entries,
            checklists: checklists
        )
        let index = await CatalogSetCompletionBuilder(checklistStore: checklistStore).build(
            sets: sets,
            ownership: CatalogOwnershipIndex(ownedCards),
            tier: .standard
        )

        XCTAssertEqual(
            index.completion(for: sets[0], tier: .standard),
            SetCompletion(owned: 1, total: 1, unit: "variations")
        )
        XCTAssertEqual(
            index.completion(for: sets[40], tier: .standard),
            SetCompletion(owned: 1, total: 1, unit: "variations")
        )
        let overflowSets = sets.filter {
            index.completion(for: $0, tier: .standard)?.unit == "cards"
        }
        XCTAssertEqual(overflowSets.count, 1)
        XCTAssertNotEqual(overflowSets.first?.id, sets[40].id)
        let checklistRequests = await checklistStore.checklistRequestCount()
        XCTAssertEqual(checklistRequests, 40)
    }

    func testCatalogSetCompletionUsesManifestDenominatorAndSkipsUnownedChecklistReads() async {
        let set = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "sv08.5"),
            name: "Prismatic Evolutions",
            code: "PRE",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 99,
            releaseDate: nil,
            sortRank: 1
        )
        let normal = CatalogCardSummary(
            game: .pokemon,
            providerID: "sv08.5-001",
            setID: set.catalogID,
            setName: set.name,
            setCode: set.code,
            name: "Eevee",
            collectorNumber: "001",
            thumbnailURL: nil,
            imageURL: nil,
            masterSetVariant: .normal,
            isSoleSlotForCard: false
        )
        let masterBall = CatalogCardSummary(
            game: .pokemon,
            providerID: "sv08.5-001",
            setID: set.catalogID,
            setName: set.name,
            setCode: set.code,
            name: "Eevee",
            collectorNumber: "001",
            thumbnailURL: nil,
            imageURL: nil,
            masterSetVariant: .masterBall,
            isExpandedMasterSetVariant: true,
            isSoleSlotForCard: false
        )
        let entry = PokemonChecklistSnapshotEntry(
            set: set,
            providerID: set.providerID,
            providerFingerprint: "fixture",
            officialCount: 90,
            standardSlotCount: 1,
            expandedSlotCount: 2,
            resource: "sets/fixture.json"
        )
        let checklistStore = CountingChecklistStore(
            entries: [entry],
            checklists: [set.id: [normal, masterBall]]
        )
        let builder = CatalogSetCompletionBuilder(checklistStore: checklistStore)

        let empty = await builder.build(
            sets: [set],
            ownership: CatalogOwnershipIndex(rows: []),
            tier: .standard
        )
        XCTAssertEqual(
            empty.completion(for: set, tier: .standard),
            SetCompletion(owned: 0, total: 1, unit: "variations")
        )
        let emptyChecklistRequests = await checklistStore.checklistRequestCount()
        XCTAssertEqual(emptyChecklistRequests, 0)

        let ownedCard = completionCard(number: "001", variant: .normal)
        let owned = CatalogOwnershipIndex([ownedCard])
        let standard = await builder.build(sets: [set], ownership: owned, tier: .standard)
        XCTAssertEqual(
            standard.completion(for: set, tier: .standard),
            SetCompletionCalculator.progress(for: [normal], cards: [ownedCard])
        )
        XCTAssertEqual(
            standard.completion(for: set, tier: .standard),
            owned.progress(for: [normal])
        )

        let expanded = await builder.build(sets: [set], ownership: owned, tier: .expanded)
        XCTAssertEqual(
            expanded.completion(for: set, tier: .expanded),
            SetCompletionCalculator.progress(
                for: [normal, masterBall],
                cards: [ownedCard]
            )
        )
        XCTAssertEqual(
            expanded.completion(for: set, tier: .expanded),
            owned.progress(for: [normal, masterBall])
        )
        let loadedChecklistRequests = await checklistStore.checklistRequestCount()
        XCTAssertEqual(loadedChecklistRequests, 2)
    }

    func testCatalogSetCompletionIgnoresCaseDuplicateSetIDs() async {
        let upper = sampleSet(id: "FIXTURE", name: "Fixture")
        let lower = sampleSet(id: "fixture", name: "Fixture")
        let slot = sampleSummary(set: upper, name: "Card")
        let entry = PokemonChecklistSnapshotEntry(
            set: upper,
            providerID: upper.providerID,
            providerFingerprint: "fixture",
            officialCount: 1,
            standardSlotCount: 1,
            expandedSlotCount: 1,
            resource: "sets/fixture.json"
        )
        let checklistStore = CountingChecklistStore(
            entries: [entry],
            checklists: [upper.id: [slot]]
        )
        let ownedCard = completionCard(number: "001", variant: .normal)
        ownedCard.providerID = "fixture-001"
        ownedCard.setName = "Fixture"
        ownedCard.setCode = "FIX"

        let index = await CatalogSetCompletionBuilder(checklistStore: checklistStore).build(
            sets: [upper, lower],
            ownership: CatalogOwnershipIndex([ownedCard]),
            tier: .standard
        )

        let expected = SetCompletion(owned: 1, total: 1, unit: "variations")
        XCTAssertEqual(index.completion(for: upper, tier: .standard), expected)
        XCTAssertEqual(index.completion(for: lower, tier: .standard), expected)
        let checklistRequests = await checklistStore.checklistRequestCount()
        XCTAssertEqual(checklistRequests, 1)
    }

    func testSuccessfulRefreshPublishesCompleteChecklistBeforeBrowseUsesIt() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let row = try decode(TCGdexBrowseSet.self, from: """
        {"id":"base1","name":"Base Set","cardCount":{"total":1,"official":1}}
        """)
        let provider = try decode(TCGdexSetCatalog.self, from: """
        {"id":"base1","name":"Base Set","cards":[{"id":"base1-001","localId":"001","name":"Alakazam","image":null}],"cardCount":{"total":1,"official":1,"normal":1,"reverse":0,"holo":0,"firstEd":1}}
        """)
        let detail = try decode(TCGdexCard.self, from: """
        {"id":"base1-001","localId":"001","name":"Alakazam","image":null,"set":{"id":"base1","name":"Base Set","cardCount":{"total":1,"official":1}},"variants":{"firstEdition":true,"holo":true,"normal":false,"reverse":false,"wPromo":false}}
        """)
        let transport = FakePokemonBrowseTransport(
            rows: [row],
            sets: ["base1": provider],
            cards: ["base1-001": detail]
        )
        let checklistRoot = root.appendingPathComponent("checklists")
        let store = PokemonChecklistStore(root: checklistRoot, bundle: nil)
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport,
            checklistStore: store
        )

        await catalog.refreshCatalogNow()
        let sets = try await catalog.sets(for: .pokemon)
        XCTAssertEqual(sets.count, 3)
        for set in sets {
            let page = try await catalog.cards(in: set, cursor: nil)
            XCTAssertFalse(page.items.isEmpty)
        }

        let downloaded = await store.downloadedSnapshot()
        XCTAssertEqual(downloaded?.manifest.entries.count, 3)
        let counts = await transport.requestCounts()
        XCTAssertEqual(counts.set, 1)
        XCTAssertEqual(counts.card, 1)
    }

    func testFailedRefreshLeavesLastCompleteChecklistVisible() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundledRoot = root.appendingPathComponent("bundled", isDirectory: true)
        let set = sampleSet(id: "sv08.5", name: "Prismatic Evolutions")
        let card = sampleSummary(set: set, name: "Eevee")
        try await writeSnapshot([set: [card]], to: bundledRoot)

        let row = try decode(TCGdexBrowseSet.self, from: """
        {"id":"sv08.5","name":"Prismatic Evolutions","cardCount":{"total":1,"official":1}}
        """)
        let transport = FakePokemonBrowseTransport(rows: [row], setError: TestError.failed)
        let store = PokemonChecklistStore(
            root: root.appendingPathComponent("downloaded"),
            bundle: nil,
            bundledRoot: bundledRoot
        )
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport,
            checklistStore: store
        )

        await catalog.refreshCatalogNow()
        let page = try await catalog.cards(in: set, cursor: nil)
        XCTAssertEqual(page.items, [card])
        let sets = try await catalog.sets(for: .pokemon)
        XCTAssertEqual(sets.first?.name, "Prismatic Evolutions")
        let shouldRefreshImmediately = await store.shouldRefresh(now: .now)
        let shouldRefreshAfterBackoff = await store.shouldRefresh(
            now: .now.addingTimeInterval(PokemonChecklistStore.failedRefreshBackoff + 1)
        )
        XCTAssertFalse(shouldRefreshImmediately)
        XCTAssertTrue(shouldRefreshAfterBackoff)
    }

    func testRefreshPublishesSuccessfulSetsWhenALaterSetFails() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let rows = try (1...5).map { index in
            try decode(TCGdexBrowseSet.self, from: """
            {"id":"fixture\(index)","name":"Fixture \(index)","cardCount":{"total":1,"official":1}}
            """)
        }
        var providers: [String: TCGdexSetCatalog] = [:]
        var cards: [String: TCGdexCard] = [:]
        for index in 1...5 {
            let providerID = "fixture\(index)"
            let cardID = "\(providerID)-001"
            providers[providerID] = try decode(TCGdexSetCatalog.self, from: """
            {"id":"\(providerID)","name":"Fixture \(index)","cards":[{"id":"\(cardID)","localId":"001","name":"Card \(index)","image":null}],"cardCount":{"total":1,"official":1}}
            """)
            cards[cardID] = try decode(TCGdexCard.self, from: """
            {"id":"\(cardID)","localId":"001","name":"Card \(index)","image":null,
             "set":{"id":"\(providerID)","name":"Fixture \(index)","cardCount":{"total":1,"official":1}}}
            """)
        }
        let transport = FakePokemonBrowseTransport(
            rows: rows,
            sets: providers,
            cards: cards,
            failingSetIDs: ["fixture3"]
        )
        let store = PokemonChecklistStore(
            root: root.appendingPathComponent("checklists"),
            bundle: nil
        )
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport,
            checklistStore: store
        )

        await catalog.refreshCatalogNow()

        let downloaded = await store.downloadedSnapshot()
        let publishedIDs = Set(downloaded?.manifest.entries.map(\.providerID) ?? [])
        XCTAssertTrue(publishedIDs.contains("fixture1"))
        XCTAssertTrue(publishedIDs.contains("fixture2"))
        XCTAssertFalse(publishedIDs.contains("fixture3"))
        XCTAssertTrue(publishedIDs.contains("fixture4"))
        XCTAssertTrue(publishedIDs.contains("fixture5"))

        await catalog.refreshCatalogNow()
        let fixture1Requests = await transport.setRequestCount("fixture1")
        let fixture2Requests = await transport.setRequestCount("fixture2")
        let fixture3Requests = await transport.setRequestCount("fixture3")
        let fixture4Requests = await transport.setRequestCount("fixture4")
        let fixture5Requests = await transport.setRequestCount("fixture5")
        XCTAssertEqual(fixture1Requests, 1)
        XCTAssertEqual(fixture2Requests, 1)
        XCTAssertEqual(fixture3Requests, 2)
        XCTAssertEqual(fixture4Requests, 1)
        XCTAssertEqual(fixture5Requests, 1)
    }

    func testCorruptChecklistEntryDoesNotHideOtherValidEntries() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = sampleSet(id: "fixture1", name: "Fixture One")
        let second = sampleSet(id: "fixture2", name: "Fixture Two")
        let store = PokemonChecklistStore(root: root, bundle: nil)
        try await writeSnapshot(
            [
                first: [sampleSummary(set: first, name: "First")],
                second: [sampleSummary(set: second, name: "Second")]
            ],
            to: root
        )

        let firstResource = root.appendingPathComponent(
            "sets/\(StableCatalogFingerprint.string(first.id)).json"
        )
        try Data("not-json".utf8).write(to: firstResource, options: .atomic)

        let loaded = await store.downloadedSnapshot()
        XCTAssertEqual(
            Set(loaded?.manifest.entries.map(\.providerID) ?? []),
            Set(["fixture2"])
        )
        XCTAssertEqual(loaded?.checklist(for: second.catalogID)?.first?.name, "Second")
        let firstIsReadable = await store.hasMergedChecklist(for: first.catalogID)
        XCTAssertFalse(firstIsReadable)
    }

    /// The shipping configuration has *both* tiers: the bundle ships every set
    /// and the overlay holds whatever has been refreshed. A readable bundled
    /// copy must not mask a corrupt overlay, or the crawl skips the set as
    /// healthy and the app serves older bundled data for it forever.
    func testCorruptChecklistResourceIsRepublishedByTheNextRefresh() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let set = sampleSet(id: "fixture1", name: "Fixture One")
        let bundledRoot = root.appendingPathComponent("bundled")
        let checklistRoot = root.appendingPathComponent("checklists")
        try await writeSnapshot(
            [set: [sampleSummary(set: set, name: "Bundled Card")]],
            to: bundledRoot
        )
        try await writeSnapshot(
            [set: [sampleSummary(set: set, name: "Old Card")]],
            to: checklistRoot
        )
        let resource = checklistRoot.appendingPathComponent(
            "sets/\(StableCatalogFingerprint.string(set.id)).json"
        )
        try Data("not-json".utf8).write(to: resource, options: .atomic)

        let row = try decode(TCGdexBrowseSet.self, from: """
        {"id":"fixture1","name":"Fixture One","cardCount":{"total":1,"official":1}}
        """)
        let provider = try decode(TCGdexSetCatalog.self, from: """
        {"id":"fixture1","name":"Fixture One","cards":[{"id":"fixture1-001","localId":"001","name":"New Card","image":null}],"cardCount":{"total":1,"official":1}}
        """)
        let detail = try decode(TCGdexCard.self, from: """
        {"id":"fixture1-001","localId":"001","name":"New Card","image":null,
         "set":{"id":"fixture1","name":"Fixture One","cardCount":{"total":1,"official":1}}}
        """)
        let transport = FakePokemonBrowseTransport(
            rows: [row],
            sets: ["fixture1": provider],
            cards: [detail.id: detail]
        )
        let store = PokemonChecklistStore(
            root: checklistRoot,
            bundle: nil,
            bundledRoot: bundledRoot
        )
        let catalog = BrowseCatalog(
            cache: CatalogCacheStore(root: root.appendingPathComponent("pages")),
            pokemonTransport: transport,
            checklistStore: store
        )

        // The overlay owns the merged entry, so its corruption is what decides
        // health — even though a reader can still be served bundled data.
        let isIntactBeforeRefresh = await store.hasMergedChecklist(for: set.catalogID)
        XCTAssertFalse(isIntactBeforeRefresh)
        let servedBeforeRefresh = await store.mergedChecklist(for: set.catalogID)?.first?.name
        XCTAssertEqual(servedBeforeRefresh, "Bundled Card")

        await catalog.refreshCatalogNow()

        let setRequests = await transport.setRequestCount("fixture1")
        let cardName = await store.mergedChecklist(for: set.catalogID)?.first?.name
        let isIntactAfterRefresh = await store.hasMergedChecklist(for: set.catalogID)
        XCTAssertEqual(setRequests, 1)
        XCTAssertEqual(cardName, "New Card")
        XCTAssertTrue(isIntactAfterRefresh)
    }

    func testATransientReadFailureDoesNotPermanentlyMarkASetUnreadable() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let set = sampleSet(id: "fixture1", name: "Fixture One")
        let card = sampleSummary(set: set, name: "Card")
        try await writeSnapshot([set: [card]], to: root)

        let resource = root.appendingPathComponent(
            "sets/\(StableCatalogFingerprint.string(set.id)).json"
        )
        // Keep the manifest entry present, but make the resource temporarily
        // unreadable in the same way an interrupted file operation can.
        try FileManager.default.removeItem(at: resource)
        try FileManager.default.createDirectory(at: resource, withIntermediateDirectories: false)

        let store = PokemonChecklistStore(root: root, bundle: nil)
        let unreadableChecklist = await store.mergedChecklist(for: set.catalogID)
        XCTAssertNil(unreadableChecklist)

        try FileManager.default.removeItem(at: resource)
        try JSONEncoder().encode([card]).write(to: resource, options: .atomic)

        let recoveredChecklist = await store.mergedChecklist(for: set.catalogID)
        XCTAssertEqual(
            recoveredChecklist?.first?.name,
            "Card",
            "a transient read failure must be retried without publishing the set"
        )
    }

    // MARK: - Refresh cadence

    /// A set that fails every crawl must not hold the resume cursor at the end
    /// of the directory forever. Within the interval the next crawl retries
    /// only what is outstanding; past it, the whole directory is swept again.
    func testASweepWithFailuresStillExpiresItsResumeCursor() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let set = sampleSet(id: "fixture1", name: "Fixture One")
        try await writeSnapshot([set: [sampleSummary(set: set, name: "Card")]], to: root)
        let store = PokemonChecklistStore(root: root, bundle: nil)

        await store.recordRefreshProgress(after: "fixture1", failed: true)
        await store.markRefreshSwept()

        let resumeCursor = await store.refreshResumeAfterProviderID()
        XCTAssertEqual(resumeCursor, "fixture1")
        let sweepsImmediately = await store.needsFullSweep(now: .now)
        XCTAssertFalse(sweepsImmediately)
        let sweepsAfterInterval = await store.needsFullSweep(
            now: .now.addingTimeInterval(PokemonChecklistStore.refreshInterval + 1)
        )
        XCTAssertTrue(sweepsAfterInterval)
        // The failure is still recorded, so the expired sweep retries it as
        // part of the ordinary pass rather than forgetting it happened.
        let failed = await store.refreshFailedProviderIDs()
        XCTAssertEqual(failed, Set(["fixture1"]))
    }

    /// Ordinary progress is not a failed attempt. The crawl is cancelled by
    /// every `inactive` scene transition, and a user who opened the app for two
    /// seconds must not be locked out of refreshing for an hour.
    func testProgressWithoutFailureDoesNotArmTheFailureBackoff() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let set = sampleSet(id: "fixture1", name: "Fixture One")
        try await writeSnapshot([set: [sampleSummary(set: set, name: "Card")]], to: root)
        let store = PokemonChecklistStore(root: root, bundle: nil)

        await store.recordRefreshProgress(after: "fixture1")
        let shouldRefreshAfterProgress = await store.shouldRefresh(now: .now)
        XCTAssertTrue(shouldRefreshAfterProgress)

        await store.recordRefreshProgress(after: "fixture2", failed: true)
        let shouldRefreshAfterFailure = await store.shouldRefresh(now: .now)
        XCTAssertFalse(shouldRefreshAfterFailure)
    }

    /// A timestamp in the future means the device clock moved backwards. That
    /// is a reason to distrust the state, never a reason to call the catalog
    /// fresh — the old polarity suppressed every refresh until wall-clock time
    /// caught up.
    func testAFutureTimestampDoesNotSuppressRefreshing() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let set = sampleSet(id: "fixture1", name: "Fixture One")
        try await writeSnapshot([set: [sampleSummary(set: set, name: "Card")]], to: root)
        let store = PokemonChecklistStore(root: root, bundle: nil)

        let future = Date.now.addingTimeInterval(60 * 60 * 24 * 30)
        await store.markRefreshSucceeded(at: future)

        let shouldRefresh = await store.shouldRefresh(now: .now)
        XCTAssertTrue(shouldRefresh)
        let needsFullSweep = await store.needsFullSweep(now: .now)
        XCTAssertTrue(needsFullSweep)
    }

    func testLimitlessArtworkNormalizesPrintedKeys() throws {
        let cases: [(code: String, number: String, key: String)] = [
            ("SLG", "1", "SLG_001"),
            ("BRS", "TG01", "BRS_TG1"),
            ("CRZ", "GG01", "CRZ_GG1"),
            ("SHF", "SV001", "SHF_SV1"),
            ("CEL", "CC001", "CEL_CC1"),
            ("PBL", "119", "PBL_119")
        ]

        for value in cases {
            let urls = LimitlessArtwork.urls(
                setCode: value.code,
                collectorNumber: value.number
            )
            XCTAssertNotNil(urls)
            XCTAssertEqual(
                urls?.small.absoluteString,
                "https://limitlesstcg.nyc3.cdn.digitaloceanspaces.com/tpci/\(value.code)/\(value.key)_R_EN_XS.png"
            )
            XCTAssertEqual(
                urls?.full.absoluteString,
                "https://limitlesstcg.nyc3.cdn.digitaloceanspaces.com/tpci/\(value.code)/\(value.key)_R_EN.png"
            )
        }

        XCTAssertNil(LimitlessArtwork.urls(setCode: "AQ", collectorNumber: "050a"))
        XCTAssertNil(LimitlessArtwork.urls(setCode: "PBL", collectorNumber: "050a"))

        let mee = try XCTUnwrap(
            LimitlessArtwork.urls(setCode: "MEE", collectorNumber: "001")
        )
        XCTAssertTrue(mee.small.absoluteString.hasSuffix("MEE/MEE_001_R_EN_XS.png"))
        XCTAssertTrue(mee.full.absoluteString.hasSuffix("MEE/MEE_001_R_EN.png"))
    }

    func testGalleryArtworkInheritsParentLogoAndKeepsProviderIdentity() throws {
        let provider = try decode(TCGdexSetCatalog.self, from: """
        {"id":"swsh10tg","name":"Lost Origin Trainer Gallery","cards":[],"cardCount":{"total":0,"official":0}}
        """)
        let base = sampleSet(id: "swsh10tg", name: "Lost Origin Trainer Gallery")

        let enriched = PokemonMasterSetChecklistBuilder.enrichedSet(base, providerSet: provider)

        XCTAssertEqual(enriched.providerID, "swsh10tg")
        XCTAssertEqual(
            enriched.logoURL?.absoluteString,
            "https://assets.tcgdex.net/en/swsh/swsh10/logo.png"
        )
        XCTAssertNil(enriched.symbolURL)
    }

    func testArtworkSourceOrdersProviderThenLimitlessFallbacks() {
        let thumbnail = URL(string: "https://example.com/thumbnail.png")!
        let full = URL(string: "https://example.com/full.png")!
        let source = CatalogCardArtworkSource(
            game: .pokemon,
            setCode: "BRS",
            collectorNumber: "TG01",
            thumbnailURL: thumbnail,
            imageURL: full,
            prefersFullSize: true
        )

        XCTAssertEqual(source.primaryURL, full)
        XCTAssertEqual(source.fallbacks.first, thumbnail)
        XCTAssertEqual(
            source.fallbacks.last?.absoluteString,
            "https://limitlesstcg.nyc3.cdn.digitaloceanspaces.com/tpci/BRS/BRS_TG1_R_EN.png"
        )

        let repeated = URL(string: "https://example.com/repeated.png")!
        let duplicateSource = CatalogCardArtworkSource(
            game: nil,
            setCode: nil,
            collectorNumber: nil,
            thumbnailURL: repeated,
            imageURL: repeated,
            prefersFullSize: true
        )
        XCTAssertEqual(duplicateSource.remoteCandidates, [.remote(repeated)])
    }

    func testSetArtworkSourceUsesRequestedKindForKnownSnapshotGap() {
        let logoURL = URL(string: "https://assets.tcgdex.net/en/sv/sv08.5/logo.png")!
        let set = sampleSet(
            id: "sv08.5",
            name: "Prismatic Evolutions",
            logoURL: logoURL,
            symbolURL: nil
        )

        let logoSource = PokemonArtworkFallbacks.setSource(for: set, kind: .logo)
        XCTAssertEqual(logoSource.candidates.first, .remote(logoURL))
        XCTAssertEqual(
            logoSource.candidates.dropFirst().map { $0 },
            [
                .bundled("PokemonSetArtwork_sv08_5_logo"),
                .bundled("PokemonSetArtwork_sv08_5_symbol")
            ]
        )

        let symbolSource = PokemonArtworkFallbacks.setSource(for: set, kind: .symbol)
        XCTAssertEqual(
            symbolSource.candidates,
            [
                .bundled("PokemonSetArtwork_sv08_5_symbol"),
                .remote(logoURL),
                .bundled("PokemonSetArtwork_sv08_5_logo")
            ]
        )
    }

    func testSetArtworkSourcePreservesCallerRequestedOrdering() {
        let logoURL = URL(string: "https://example.com/logo.png")!
        let symbolURL = URL(string: "https://example.com/symbol.png")!
        let set = sampleSet(
            id: "sv08.5",
            name: "Prismatic Evolutions",
            logoURL: logoURL,
            symbolURL: symbolURL
        )

        let logoSource = PokemonArtworkFallbacks.setSource(for: set, kind: .logo)
        XCTAssertEqual(
            logoSource.candidates,
            [
                .remote(logoURL),
                .bundled("PokemonSetArtwork_sv08_5_logo"),
                .remote(symbolURL),
                .bundled("PokemonSetArtwork_sv08_5_symbol")
            ]
        )

        let symbolSource = PokemonArtworkFallbacks.setSource(for: set, kind: .symbol)
        XCTAssertEqual(
            symbolSource.candidates,
            [
                .remote(symbolURL),
                .bundled("PokemonSetArtwork_sv08_5_symbol"),
                .remote(logoURL),
                .bundled("PokemonSetArtwork_sv08_5_logo")
            ]
        )
    }

    func testSetArtworkSourcePrefersRequestedLogoRemoteWhenBothURLsExist() {
        let logoURL = URL(string: "https://example.com/logo.png")!
        let symbolURL = URL(string: "https://example.com/symbol.png")!
        let set = sampleSet(
            id: "fixture",
            name: "Fixture",
            logoURL: logoURL,
            symbolURL: symbolURL
        )

        XCTAssertEqual(
            PokemonArtworkFallbacks.setSource(for: set, kind: .logo).candidates,
            [.remote(logoURL), .remote(symbolURL)]
        )
    }

    func testSetArtworkSourcePrefersBundledLogoBeforeRemoteSymbol() {
        let symbolURL = URL(string: "https://example.com/symbol.png")!
        let set = sampleSet(
            id: "sv08.5",
            name: "Prismatic Evolutions",
            logoURL: nil,
            symbolURL: symbolURL
        )

        let candidates = PokemonArtworkFallbacks.setSource(for: set, kind: .logo).candidates
        XCTAssertEqual(candidates.first, .bundled("PokemonSetArtwork_sv08_5_logo"))
        XCTAssertEqual(candidates.dropFirst().first, .remote(symbolURL))
    }

    func testSetArtworkSourceUsesCel25ccParentLogoBeforeBundledArtwork() {
        let set = sampleSet(id: "cel25cc", name: "Celebrations Classic Collection")
        let candidates = PokemonArtworkFallbacks.setSource(for: set, kind: .logo).candidates
        let parent = PokemonArtworkFallbacks.parentLogoURL(forProviderID: "cel25cc")

        XCTAssertEqual(candidates.first, parent.map(PokemonArtworkFallbacks.Candidate.remote))
        XCTAssertEqual(candidates.dropFirst().first, .bundled("PokemonSetArtwork_cel25cc_logo"))
    }

    func testCatalogCachedImageSkipsMissingBundledCandidate() {
        let remote = URL(string: "https://example.com/fallback.png")!
        let candidates: [PokemonArtworkFallbacks.Candidate] = [
            .bundled("PokemonSetArtwork_that_does_not_exist"),
            .remote(remote)
        ]

        XCTAssertEqual(
            CatalogCachedImage.candidatesSkippingMissingBundledAssets(candidates),
            [.remote(remote)]
        )
    }

    func testMagicSetArtworkSourceHasNoBundledOrParentCandidates() {
        let set = CatalogSet(
            catalogID: CatalogSetID(game: .magic, providerID: "me02"),
            name: "Magic fixture",
            code: "MEE",
            logoURL: URL(string: "https://example.com/logo.svg"),
            symbolURL: URL(string: "https://example.com/symbol.svg"),
            cardCount: 1,
            releaseDate: nil,
            sortRank: 1
        )

        let candidates = PokemonArtworkFallbacks.setSource(for: set, kind: .logo).candidates
        XCTAssertTrue(candidates.allSatisfy { if case .remote = $0 { return true }; return false })
        XCTAssertFalse(candidates.contains { if case .bundled = $0 { return true }; return false })
    }

    func testBundledSnapshotImageURLLessRowsHaveExplicitLimitlessCoverage() async throws {
        let root = try makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PokemonChecklistStore(
            root: root,
            bundle: Bundle.main
        )
        let bundledSnapshot = await store.bundledSnapshot()
        let snapshot = try XCTUnwrap(bundledSnapshot)
        let imageURLLessCodes = snapshot.manifest.entries.compactMap { entry -> String? in
            guard snapshot.checklist(for: entry.set.catalogID)?.contains(where: { $0.imageURL == nil }) == true
            else { return nil }
            return entry.set.code.uppercased()
        }

        for code in Set(imageURLLessCodes) {
            XCTAssertTrue(
                LimitlessArtwork.supportedSetCodes.contains(code)
                    || LimitlessArtwork.knownUncoveredSetCodes.contains(code),
                "Uncovered image-less code needs an explicit artwork decision: \(code)"
            )
        }
    }

    func testCatalogCardDisplayGroupRejectsEmptySummaries() {
        let identity = CatalogCardDisplayIdentity(
            game: .pokemon,
            setID: CatalogSetID(game: .pokemon, providerID: "sv08"),
            providerID: "card-1",
            collectorNumber: "001"
        )

        XCTAssertNil(CatalogCardDisplayGroup(identity: identity, summaries: []))
    }

    private func writeSnapshot(
        _ values: [CatalogSet: [CatalogCardSummary]],
        to root: URL
    ) async throws {
        let entries = values.keys.sorted { $0.id < $1.id }.map { set in
            PokemonChecklistSnapshotEntry(
                set: set,
                providerID: set.providerID,
                providerFingerprint: "fixture-\(set.providerID)",
                resource: "sets/\(StableCatalogFingerprint.string(set.id)).json"
            )
        }
        let manifest = PokemonChecklistSnapshotManifest(
            schemaVersion: PokemonChecklistSnapshotVersion.schema,
            rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
            generatedAt: .now,
            directoryFingerprint: "fixture",
            entries: entries
        )
        let snapshot = PokemonChecklistSnapshot(
            manifest: manifest,
            checklists: Dictionary(uniqueKeysWithValues: values.map { ($0.key.id, $0.value) })
        )
        try await PokemonChecklistStore(root: root, bundle: nil).publish(snapshot)
    }

    private func sampleSet(
        id: String,
        name: String,
        logoURL: URL? = nil,
        symbolURL: URL? = nil
    ) -> CatalogSet {
        CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: id),
            name: name,
            code: "FIX",
            logoURL: logoURL,
            symbolURL: symbolURL,
            cardCount: 1,
            releaseDate: nil,
            sortRank: 1
        )
    }

    private func sampleSummary(set: CatalogSet, name: String) -> CatalogCardSummary {
        CatalogCardSummary(
            game: .pokemon,
            providerID: "\(set.providerID)-001",
            setID: set.catalogID,
            setName: set.name,
            setCode: set.code,
            name: name,
            collectorNumber: "001",
            thumbnailURL: nil,
            imageURL: nil,
            masterSetVariant: .normal,
            isExpandedMasterSetVariant: false,
            isSoleSlotForCard: true
        )
    }

    private func makeTemporaryCacheDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func completionCard(
        number: String,
        variant: PhysicalVariant,
        quantity: Int = 1
    ) -> CollectedCard {
        CollectedCard(
            collectionKey: "test:\(number)#\(variant.id)",
            game: .pokemon,
            providerID: "sv08.5-\(number)",
            name: "Card \(number)",
            setName: "Prismatic Evolutions",
            setCode: "PRE",
            cardNumber: number,
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: variant,
            variantResolution: .userConfirmed,
            quantity: quantity
        )
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from string: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(string.utf8))
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private enum TestError: Error { case failed }

private actor CountingChecklistStore: CatalogSetCompletionChecklistStore {
    private let entries: [PokemonChecklistSnapshotEntry]
    private let checklists: [String: [CatalogCardSummary]]
    private var checklistRequests = 0

    init(
        entries: [PokemonChecklistSnapshotEntry],
        checklists: [String: [CatalogCardSummary]]
    ) {
        self.entries = entries
        self.checklists = checklists
    }

    func mergedEntries() async -> [PokemonChecklistSnapshotEntry] {
        entries
    }

    func mergedChecklist(for setID: CatalogSetID) async -> [CatalogCardSummary]? {
        checklistRequests += 1
        return checklists[setID.id]
    }

    func checklistRequestCount() -> Int {
        checklistRequests
    }
}

private actor RecordingJustTCGProviding: SealedBrowseProviding {
    private let productsByGame: [CardGame: [SealedProductSummary]]
    private var sealedSearches = 0
    private var searchedGames: [CardGame] = []

    init(productsByGame: [CardGame: [SealedProductSummary]] = [:]) {
        self.productsByGame = productsByGame
    }

    func searchSealedProducts(
        game: CardGame,
        setID: String?,
        query: String?,
        offset: Int
    ) async throws -> MarketCatalogPage<SealedProductSummary> {
        sealedSearches += 1
        searchedGames.append(game)
        let items = productsByGame[game] ?? []
        return MarketCatalogPage(
            items: items,
            total: items.count,
            offset: offset,
            limit: JustTCGQuota.maximumPageSize,
            hasMore: false
        )
    }

    func sealedSets(game: CardGame) async throws -> [SealedSetSummary] {
        throw TestError.failed
    }

    func sealedSearchCount() -> Int { sealedSearches }
    func sealedSearchGames() -> [CardGame] { searchedGames }
}

private actor EmptyBrowseCatalog: BrowseCatalogProviding {
    private var searches = 0

    func sets(for game: CardGame) async throws -> [CatalogSet] { [] }

    func cards(in set: CatalogSet, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        CatalogPage(items: [], nextCursor: nil)
    }

    func searchCards(
        named query: String,
        game: CardGame,
        setIDs: Set<CatalogSetID>,
        cursor: String?
    ) async throws -> CatalogPage<CatalogCardSummary> {
        searches += 1
        return CatalogPage(items: [], nextCursor: nil)
    }

    func details(for summary: CatalogCardSummary) async throws -> CatalogCardDetails {
        throw TestError.failed
    }

    nonisolated func sortPrices(for cards: [CatalogCardSummary]) -> AsyncStream<[String: Double]> {
        AsyncStream { continuation in continuation.finish() }
    }
    func prepareCatalog() async {}

    func searchCount() -> Int { searches }
}

private actor PagingBrowseCatalog: BrowseCatalogProviding {
    private let first: CatalogCardSummary
    private let second: CatalogCardSummary
    private var cursors: [String?] = []

    init(first: CatalogCardSummary, second: CatalogCardSummary) {
        self.first = first
        self.second = second
    }

    func sets(for game: CardGame) async throws -> [CatalogSet] { [] }

    func cards(in set: CatalogSet, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        CatalogPage(items: [], nextCursor: nil)
    }

    func searchCards(
        named query: String,
        game: CardGame,
        setIDs: Set<CatalogSetID>,
        cursor: String?
    ) async throws -> CatalogPage<CatalogCardSummary> {
        cursors.append(cursor)
        if cursor == nil {
            return CatalogPage(items: [first], nextCursor: "next")
        }
        return CatalogPage(items: [second], nextCursor: nil)
    }

    func details(for summary: CatalogCardSummary) async throws -> CatalogCardDetails {
        throw TestError.failed
    }

    nonisolated func sortPrices(for cards: [CatalogCardSummary]) -> AsyncStream<[String: Double]> {
        AsyncStream { continuation in continuation.finish() }
    }
    func prepareCatalog() async {}

    func requestedCursors() -> [String?] { cursors }
}

private actor FakePokemonBrowseTransport: PokemonBrowseTransport {
    private let rows: [TCGdexBrowseSet]
    private let setValues: [String: TCGdexSetCatalog]
    private let cardValues: [String: TCGdexCard]
    private let setError: Error?
    private let failingSetIDs: Set<String>
    private let cardDelayNanoseconds: UInt64
    private var directoryRequests = 0
    private var setRequests = 0
    private var cardRequests = 0
    private var cancelledCardRequests = 0
    private var setRequestIDs: [String: Int] = [:]

    init(
        rows: [TCGdexBrowseSet] = [],
        sets: [String: TCGdexSetCatalog] = [:],
        cards: [String: TCGdexCard] = [:],
        setError: Error? = nil,
        failingSetIDs: Set<String> = [],
        cardDelayNanoseconds: UInt64 = 0
    ) {
        self.rows = rows
        self.setValues = sets
        self.cardValues = cards
        self.setError = setError
        self.failingSetIDs = Set(failingSetIDs.map { $0.lowercased() })
        self.cardDelayNanoseconds = cardDelayNanoseconds
    }

    func fetchSetDirectory() async throws -> [TCGdexBrowseSet] {
        directoryRequests += 1
        return rows
    }

    func fetchPocketSetIDs() async throws -> Set<String> { [] }

    func fetchSet(id: String) async throws -> TCGdexSetCatalog {
        setRequests += 1
        let key = id.lowercased()
        setRequestIDs[key, default: 0] += 1
        if let setError { throw setError }
        if failingSetIDs.contains(key) { throw TestError.failed }
        return try XCTUnwrap(setValues[key])
    }

    func fetchCard(id: String) async throws -> TCGdexCard {
        cardRequests += 1
        if cardDelayNanoseconds > 0 {
            do {
                try await Task.sleep(nanoseconds: cardDelayNanoseconds)
            } catch {
                cancelledCardRequests += 1
                throw error
            }
        }
        return try XCTUnwrap(cardValues[id])
    }

    func requestCounts() -> (directory: Int, set: Int, card: Int) {
        (directoryRequests, setRequests, cardRequests)
    }

    func setRequestCount(_ id: String) -> Int {
        setRequestIDs[id.lowercased(), default: 0]
    }

    func cancelledCardRequestCount() -> Int {
        cancelledCardRequests
    }
}

private actor CountingPokemonCardSource: PokemonCardSource {
    enum PrimaryResponse: Sendable {
        case card(TCGdexCard)
        case failure(TCGdexError)
    }

    enum FallbackResponse: Sendable {
        case card(PokemonTCGAPICard)
        case failure(TCGdexError)
        case empty
    }

    private let primaryResponse: PrimaryResponse
    private let fallbackResponse: FallbackResponse
    private var primaryRequests = 0
    private var fallbackRequests = 0

    init(primary: PrimaryResponse, fallback: FallbackResponse) {
        self.primaryResponse = primary
        self.fallbackResponse = fallback
    }

    func fetchTCGdexCard(setID: String, localID: String) async throws -> TCGdexCard {
        primaryRequests += 1
        switch primaryResponse {
        case let .card(card): return card
        case let .failure(error): throw error
        }
    }

    func fetchPokemonTCGCard(setID: String, cardNumber: String) async throws -> PokemonTCGAPICard? {
        fallbackRequests += 1
        switch fallbackResponse {
        case let .card(card): return card
        case let .failure(error): throw error
        case .empty: return nil
        }
    }

    func requestCounts() -> (primary: Int, fallback: Int) {
        (primaryRequests, fallbackRequests)
    }
}
