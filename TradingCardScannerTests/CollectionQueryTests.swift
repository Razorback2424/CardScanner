import XCTest
@testable import TradingCardScanner

final class CollectionQueryTests: XCTestCase {
    private func row(
        id: String = UUID().uuidString,
        game: CardGame = .pokemon,
        name: String = "Eevee",
        setCode: String = "PRE",
        setName: String = "Prismatic Evolutions",
        release: Int = 11,
        number: String = "074",
        variant: PhysicalVariant? = .reverse,
        quantity: Int = 1,
        price: Double?,
        treatmentIDs: [String] = [],
        asOf: Date? = .now
    ) -> CollectionRow {
        CollectionRow(
            id: id,
            game: game,
            name: name,
            setCode: setCode,
            setName: setName,
            setReleaseOrder: release,
            cardNumber: number,
            variantID: variant?.id,
            variantLabel: variant?.label,
            quantity: quantity,
            dateAdded: .now,
            price: PriceDisplay(
                amount: price,
                source: .tcgplayer,
                sourceUpdatedAt: price == nil ? nil : asOf,
                fetchedAt: asOf,
                lastCheckedAt: asOf
            ),
            magicTreatmentIDsRaw: treatmentIDs
        )
    }

    // MARK: - Collector numbers are not integers

    func testCardNumberSortIsNumericNotLexical() {
        let rows = ["100", "009", "010", "002"].map { row(number: $0, price: 1) }
        let sorted = CollectionQuery.sort(rows, by: .cardNumber)

        XCTAssertEqual(sorted.map(\.cardNumber), ["002", "009", "010", "100"])
    }

    func testCollectorNumberSuffixesAndPrefixesSortNaturally() {
        XCTAssertEqual(CollectorNumber.compare("218", "218a"), .orderedAscending)
        XCTAssertEqual(CollectorNumber.compare("525", "525a"), .orderedAscending)
        XCTAssertEqual(CollectorNumber.compare("525a", "525b"), .orderedAscending)
        XCTAssertEqual(CollectorNumber.compare("525b", "526"), .orderedAscending)
        XCTAssertEqual(CollectorNumber.compare("GG01", "GG10"), .orderedAscending)
        XCTAssertEqual(CollectorNumber.compare("0218", "218"), .orderedSame)
        // A purely alphabetic identifier has no number to compare, so it sorts
        // after the numbered ones rather than being treated as zero.
        XCTAssertEqual(CollectorNumber.compare("SWSH", "010"), .orderedDescending)
    }

    func testCardNumberSortKeepsBareNumberBeforeItsSuffixes() {
        let rows = ["525b", "525", "525a"].map {
            row(id: $0, number: $0, price: 1)
        }

        XCTAssertEqual(
            CollectionQuery.sort(rows, by: .cardNumber).map(\.cardNumber),
            ["525", "525a", "525b"]
        )
    }

    func testCompletionCanonicalNumberStripsPaddingBeforeSuffix() {
        XCTAssertEqual(SetCompletionCalculator.canonicalNumber("0523a"), "523a")
        XCTAssertEqual(SetCompletionCalculator.canonicalNumber("0523B"), "523b")
        XCTAssertEqual(SetCompletionCalculator.canonicalNumber("0523"), "523")
    }

    // MARK: - Set + card number

    func testSetAndCardNumberGroupsNewestSetFirstThenBinderOrder() {
        let rows = [
            row(id: "a", setCode: "OBF", release: 2, number: "010", price: 1),
            row(id: "b", setCode: "PRE", release: 11, number: "020", price: 1),
            row(id: "c", setCode: "PRE", release: 11, number: "003", price: 1)
        ]

        XCTAssertEqual(
            CollectionQuery.sort(rows, by: .setAndCardNumber).map(\.id),
            ["c", "b", "a"]
        )
    }

    /// Pokémon release indexes and Magic release dates live on different scales,
    /// so they are never compared against each other.
    func testSetAndCardNumberGroupsByGameBeforeReleaseOrder() {
        let rows = [
            row(id: "magic", game: .magic, setCode: "ECL", release: 20_400, number: "218", variant: .foil, price: 1),
            row(id: "pokemon", game: .pokemon, setCode: "PRE", release: 11, number: "074", price: 1)
        ]

        let sorted = CollectionQuery.sort(rows, by: .setAndCardNumber)
        XCTAssertEqual(sorted.map(\.game), [.magic, .pokemon])
    }

    // MARK: - Price sorting

    /// Unknown is not worthless. An unpriced card sinks in both directions.
    func testUnpricedCardsSortLastInBothPriceDirections() {
        let rows = [
            row(id: "cheap", price: 1),
            row(id: "unpriced", price: nil),
            row(id: "dear", price: 90)
        ]

        XCTAssertEqual(
            CollectionQuery.sort(rows, by: .priceHighToLow).map(\.id),
            ["dear", "cheap", "unpriced"]
        )
        XCTAssertEqual(
            CollectionQuery.sort(rows, by: .priceLowToHigh).map(\.id),
            ["cheap", "dear", "unpriced"]
        )
    }

    // MARK: - Price filtering

    /// Ten copies of a $2 card is still a $2 card.
    func testPriceFilterUsesUnitPriceNotHoldingValue() {
        let rows = [row(id: "bulk", quantity: 10, price: 2)]
        var filters = CollectionFilters.none
        filters.price = .band(.tenToTwentyFive)

        XCTAssertTrue(CollectionQuery.filter(rows, with: filters).isEmpty)
    }

    func testPriceBandsTileWithoutOverlapping() {
        XCTAssertTrue(PriceFilter.band(.fiveToTen).matches(5))
        XCTAssertFalse(PriceFilter.band(.fiveToTen).matches(10))
        XCTAssertTrue(PriceFilter.band(.tenToTwentyFive).matches(10))
        XCTAssertTrue(PriceFilter.band(.hundredPlus).matches(4_000))
    }

    /// Someone who types 25 means to see the $25 card.
    func testCustomRangeIncludesItsMaximum() {
        XCTAssertTrue(PriceFilter.custom(min: 10, max: 25).matches(25))
        XCTAssertFalse(PriceFilter.custom(min: 10, max: 25).matches(25.01))
    }

    func testUnpricedCardNeverSatisfiesAPriceQuestion() {
        XCTAssertFalse(PriceFilter.band(.underOne).matches(nil))
        XCTAssertFalse(PriceFilter.custom(min: nil, max: 1_000_000).matches(nil))
    }

    /// The one filter that inverts the rule above: it asks which cards are still
    /// missing a price, so only a missing price satisfies it.
    func testUnpricedFilterMatchesOnlyRowsWithNoPrice() {
        XCTAssertTrue(PriceFilter.unpriced.matches(nil))
        XCTAssertFalse(PriceFilter.unpriced.matches(0.01))
        XCTAssertFalse(PriceFilter.unpriced.matches(4_000))
    }

    func testUnpricedFilterNarrowsTheCollectionToWhatIsMissing() {
        let rows = [
            row(id: "priced", setCode: "PRE", variant: .reverse, price: 3.75),
            row(id: "missing", setCode: "PRE", variant: .masterBall, price: nil),
            row(id: "alsoMissing", setCode: "OBF", variant: .normal, price: nil)
        ]
        var filters = CollectionFilters.none
        filters.price = .unpriced

        XCTAssertEqual(
            CollectionQuery.filter(rows, with: filters).map(\.id).sorted(),
            ["alsoMissing", "missing"]
        )
    }

    // MARK: - Composing filters

    func testFiltersComposeIntoOneQuery() {
        let rows = [
            row(id: "wanted", setCode: "PRE", variant: .masterBall, price: 18),
            row(id: "wrongFinish", setCode: "PRE", variant: .reverse, price: 18),
            row(id: "wrongSet", setCode: "OBF", variant: .masterBall, price: 18),
            row(id: "wrongPrice", setCode: "PRE", variant: .masterBall, price: 4),
            row(id: "wrongGame", game: .magic, setCode: "PRE", variant: .masterBall, price: 18)
        ]

        var filters = CollectionFilters.none
        filters.game = .pokemon
        filters.setCodes = [rows[0].setFilterID]
        filters.variantIDs = [PhysicalVariant.masterBall.id]
        filters.price = .band(.tenToTwentyFive)

        XCTAssertEqual(CollectionQuery.filter(rows, with: filters).map(\.id), ["wanted"])
    }

    func testSetFilterDoesNotCrossGameNamespacesWhenCodesMatch() {
        let pokemon = row(id: "pokemon", game: .pokemon, setCode: "PAR", price: 1)
        let magic = row(id: "magic", game: .magic, setCode: "PAR", variant: .foil, price: 1)
        var filters = CollectionFilters.none
        filters.setCodes = [pokemon.setFilterID]

        XCTAssertEqual(CollectionQuery.filter([pokemon, magic], with: filters).map(\.id), ["pokemon"])
    }

    func testMultipleFinishesCanBeSelectedAtOnce() {
        let rows = [
            row(id: "master", variant: .masterBall, price: 1),
            row(id: "poke", variant: .pokeBall, price: 1),
            row(id: "reverse", variant: .reverse, price: 1)
        ]

        var filters = CollectionFilters.none
        filters.variantIDs = [PhysicalVariant.masterBall.id, PhysicalVariant.pokeBall.id]

        XCTAssertEqual(
            Set(CollectionQuery.filter(rows, with: filters).map(\.id)),
            ["master", "poke"]
        )
    }

    func testTreatmentFilterRequiresTheSelectedTreatment() {
        let rows = [
            row(id: "generic", game: .magic, variant: .foil, price: 1),
            row(
                id: "surge",
                game: .magic,
                variant: .foil,
                price: nil,
                treatmentIDs: [MagicTreatment.surgeFoil.id]
            ),
            row(
                id: "future",
                game: .magic,
                variant: .foil,
                price: nil,
                treatmentIDs: ["Future Treatment"]
            )
        ]
        var filters = CollectionFilters.none
        filters.treatmentIDs = [MagicTreatment.surgeFoil.id]

        XCTAssertTrue(filters.isActive)
        XCTAssertEqual(CollectionQuery.filter(rows, with: filters).map(\.id), ["surge"])
    }

    func testUnknownTreatmentCanBeFilteredWithoutBecomingAFinish() {
        let row = row(
            id: "future",
            game: .magic,
            variant: .foil,
            price: nil,
            treatmentIDs: ["Future Treatment"]
        )
        XCTAssertEqual(row.magicTreatments, [.unclassified("Future Treatment")])
        XCTAssertEqual(row.variant, .foil)

        var filters = CollectionFilters.none
        filters.treatmentIDs = ["future treatment"]
        XCTAssertEqual(CollectionQuery.filter([row], with: filters).map(\.id), ["future"])
    }

    func testKnownTreatmentOnTheWrongFinishIsNotShownOrFilterable() {
        let row = row(
            id: "contradictory",
            game: .magic,
            variant: .nonfoil,
            price: nil,
            treatmentIDs: [MagicTreatment.surgeFoil.id]
        )

        XCTAssertTrue(row.magicTreatments.contains(.surgeFoil))
        XCTAssertTrue(row.displayedMagicTreatments.isEmpty)

        var filters = CollectionFilters.none
        filters.treatmentIDs = [MagicTreatment.surgeFoil.id]
        XCTAssertTrue(CollectionQuery.filter([row], with: filters).isEmpty)
    }

    /// An entry whose finish was never resolved cannot answer a finish question.
    func testUnknownFinishIsExcludedByAFinishFilter() {
        let rows = [row(id: "unknown", variant: nil, price: 1)]
        var filters = CollectionFilters.none
        filters.variantIDs = [PhysicalVariant.reverse.id]

        XCTAssertTrue(CollectionQuery.filter(rows, with: filters).isEmpty)
    }

    func testNoFiltersLeavesEverythingVisible() {
        let rows = [row(price: 1), row(price: nil), row(game: .magic, variant: .foil, price: 3)]

        XCTAssertFalse(CollectionFilters.none.isActive)
        XCTAssertEqual(CollectionQuery.filter(rows, with: .none).count, 3)
    }

    // MARK: - Name search

    func testSearchMatchesAnySubstringOfTheCardName() {
        XCTAssertTrue(CardNameSearch.matches(name: "Charizard ex", normalizedQuery: "charizard"))
        XCTAssertTrue(CardNameSearch.matches(name: "Charizard VMAX", normalizedQuery: "charizard"))
        XCTAssertTrue(CardNameSearch.matches(name: "Flying Pikachu", normalizedQuery: "pikachu"))
        XCTAssertTrue(CardNameSearch.matches(name: "The One Ring", normalizedQuery: "one ring"))
    }

    func testSearchIsNarrowedByTypingMore() {
        let query = CardNameSearch.normalize("charizard ex")
        XCTAssertTrue(CardNameSearch.matches(name: "Charizard ex", normalizedQuery: query))
        XCTAssertFalse(CardNameSearch.matches(name: "Charizard VMAX", normalizedQuery: query))
    }

    /// Users are not punished for formatting differences.
    func testSearchIgnoresCasePunctuationAndAccents() {
        XCTAssertTrue(CardNameSearch.matches(name: "Urza's Saga", normalizedQuery: CardNameSearch.normalize("urzas saga")))
        XCTAssertTrue(CardNameSearch.matches(name: "Urza's Saga", normalizedQuery: CardNameSearch.normalize("Urza’s  Saga")))
        XCTAssertTrue(CardNameSearch.matches(name: "Ho-Oh", normalizedQuery: CardNameSearch.normalize("ho oh")))
        XCTAssertTrue(CardNameSearch.matches(name: "Ho-Oh", normalizedQuery: CardNameSearch.normalize("HO-OH")))
        XCTAssertTrue(CardNameSearch.matches(name: "Flabébé", normalizedQuery: CardNameSearch.normalize("flabebe")))
    }

    /// A typo returns nothing rather than quietly deciding what was meant.
    func testSearchIsNotFuzzy() {
        XCTAssertFalse(CardNameSearch.matches(name: "Charizard", normalizedQuery: "charzard"))
    }

    /// Name only. The box answers "which card name", the chips answer "which
    /// version" — mixing them would make both unpredictable.
    func testSearchNeverMatchesAnythingButTheName() {
        let row = row(name: "Charizard ex", setCode: "OBF", setName: "Obsidian Flames",
                      number: "223", variant: .reverse, price: 12)

        for query in ["obf", "obsidian", "223", "reverse", "12", "rare"] {
            XCTAssertTrue(
                CollectionQuery.filter([row], nameQuery: query, with: .none).isEmpty,
                "\(query) must not match a card named Charizard ex"
            )
        }
        XCTAssertEqual(CollectionQuery.filter([row], nameQuery: "charizard", with: .none).count, 1)
    }

    func testEmptySearchNarrowsNothing() {
        let rows = [row(name: "Charizard ex", price: 1), row(name: "Pikachu", price: 2)]

        XCTAssertEqual(CollectionQuery.filter(rows, nameQuery: "", with: .none).count, 2)
        XCTAssertEqual(CollectionQuery.filter(rows, nameQuery: "   ", with: .none).count, 2)
    }

    /// Search narrows whatever view is already set up; it is not a mode.
    func testSearchComposesWithTheFilterChips() {
        let rows = [
            row(id: "wanted", name: "Pikachu ex", setCode: "PRE", variant: .masterBall, price: 30),
            row(id: "otherName", name: "Eevee", setCode: "PRE", variant: .masterBall, price: 30),
            row(id: "otherFinish", name: "Pikachu ex", setCode: "PRE", variant: .reverse, price: 30),
            row(id: "otherSet", name: "Pikachu ex", setCode: "OBF", variant: .masterBall, price: 30)
        ]

        var filters = CollectionFilters.none
        filters.setCodes = [rows[0].setFilterID]
        filters.variantIDs = [PhysicalVariant.masterBall.id]

        XCTAssertEqual(
            CollectionQuery.filter(rows, nameQuery: "pikachu", with: filters).map(\.id),
            ["wanted"]
        )
    }

    /// Owning several versions of one named card gives several results. The
    /// search identifies names; the collection still represents physical objects.
    func testSearchDoesNotCollapseVariantsOfTheSameName() {
        let rows = [
            row(id: "master", name: "Pikachu", variant: .masterBall, price: 40),
            row(id: "reverse", name: "Pikachu", variant: .reverse, price: 3)
        ]

        XCTAssertEqual(CollectionQuery.filter(rows, nameQuery: "pikachu", with: .none).count, 2)
    }

    /// "Which of my Charizards is worth the most?" in two controls.
    func testSortingAppliesToTheSearchedSubset() {
        let rows = [
            row(id: "cheap", name: "Charizard ex", price: 12),
            row(id: "dear", name: "Charizard VMAX", price: 180),
            row(id: "other", name: "Pikachu", price: 900)
        ]

        XCTAssertEqual(
            CollectionQuery.apply(nameQuery: "charizard", filters: .none, sort: .priceHighToLow, to: rows).map(\.id),
            ["dear", "cheap"]
        )
    }
}
