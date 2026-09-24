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
        currencyCode: String = "USD",
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
                currencyCode: currencyCode,
                source: .tcgplayer,
                sourceUpdatedAt: price == nil ? nil : asOf,
                fetchedAt: asOf,
                lastCheckedAt: asOf
            ),
            magicTreatmentIDsRaw: treatmentIDs
        )
    }

    func testCollectionShownValueUsesTheSharedUSDValuationRule() {
        let rows = [
            row(id: "usd", quantity: 2, price: 12.3456),
            row(id: "eur", quantity: 4, price: 99, currencyCode: "EUR"),
            row(id: "missing", quantity: 1, price: nil)
        ]

        XCTAssertEqual(
            CollectionValuation.shownValue(for: rows),
            Money(rounding: 24.6912)
        )
    }

    func testCollectionFooterCountsVisibleLogicalItemsButAllExcludedCopies() {
        let priced = row(id: "priced", quantity: 4, price: 12)
        let unpriced = row(id: "unpriced", quantity: 7, price: nil)

        let footer = CollectionView.CollectionFooterPresentation.make(
            visibleRows: [priced],
            collectionRows: [priced, unpriced],
            isNarrowed: true
        )

        XCTAssertEqual(footer.visibleLogicalItemCount, 1)
        XCTAssertEqual(footer.excludedFromValueCopyCount, 7)
        XCTAssertEqual(footer.itemSummary, "1 item shown")
        XCTAssertEqual(footer.exclusionSummary, "7 copies unpriced, not included in the total.")
    }

    func testCollectionFooterUsesGenericWordingForNonUSDExcludedQuotes() {
        let foreignQuote = row(
            id: "eur",
            quantity: 2,
            price: 9,
            currencyCode: "EUR"
        )

        let footer = CollectionView.CollectionFooterPresentation.make(
            visibleRows: [foreignQuote],
            collectionRows: [foreignQuote],
            isNarrowed: false
        )

        XCTAssertEqual(footer.excludedFromValueCopyCount, 2)
        XCTAssertEqual(
            footer.exclusionSummary,
            "2 copies are not included in the collection value."
        )

        let singularFooter = CollectionView.CollectionFooterPresentation.make(
            visibleRows: [row(id: "eur-singular", quantity: 1, price: 9, currencyCode: "EUR")],
            collectionRows: [row(id: "eur-singular", quantity: 1, price: 9, currencyCode: "EUR")],
            isNarrowed: false
        )
        XCTAssertEqual(
            singularFooter.exclusionSummary,
            "1 copy is not included in the collection value."
        )
    }

    func testCollectionFooterOmitsExclusionNoteWhenEveryCopyIsValued() {
        let footer = CollectionView.CollectionFooterPresentation.make(
            visibleRows: [row(id: "priced", quantity: 1, price: 2)],
            collectionRows: [row(id: "priced", quantity: 1, price: 2)],
            isNarrowed: false
        )

        XCTAssertEqual(footer.itemSummary, "1 item")
        XCTAssertNil(footer.exclusionSummary)
    }

    func testCollectionRefreshStatusUsesTerminalFacts() {
        let changedSummary = PriceRefreshController.Summary(
            checkedAt: .now,
            priced: 1,
            failed: 0,
            latestSourceUpdate: nil,
            checkedUnstampedProvider: false,
            changedPrices: true,
            foundNothingNewer: false
        )
        var outcome = CollectionRefreshOutcome(
            status: .finished(changedSummary),
            fallbackStatus: .idle
        )

        XCTAssertEqual(
            CollectionRefreshStatusResolver.presentation(for: outcome)?.message,
            "Prices updated"
        )

        let currentSummary = PriceRefreshController.Summary(
            checkedAt: .now,
            priced: 1,
            failed: 0,
            latestSourceUpdate: nil,
            checkedUnstampedProvider: false,
            changedPrices: false,
            foundNothingNewer: true
        )
        outcome = CollectionRefreshOutcome(
            status: .finished(currentSummary),
            fallbackStatus: .idle
        )
        XCTAssertEqual(
            CollectionRefreshStatusResolver.presentation(for: outcome)?.message,
            "Prices checked — already current"
        )

        outcome = CollectionRefreshOutcome(
            status: .finished(currentSummary),
            fallbackStatus: .budgetReached(pending: 2, resetAt: .now)
        )
        XCTAssertEqual(
            CollectionRefreshStatusResolver.presentation(for: outcome)?.message,
            "Some prices couldn’t be refreshed"
        )

        let reconciledSummary = PriceRefreshController.Summary(
            checkedAt: .now,
            priced: 1,
            failed: 2,
            latestSourceUpdate: nil,
            checkedUnstampedProvider: false,
            changedPrices: true,
            foundNothingNewer: false,
            repairedFinishes: 3,
            backfilledFinishes: 4
        )
        outcome = CollectionRefreshOutcome(
            status: .finished(reconciledSummary),
            fallbackStatus: .budgetReached(pending: 2, resetAt: .now)
        )
        XCTAssertEqual(
            CollectionRefreshStatusResolver.presentation(for: outcome)?.message,
            "Some prices couldn’t be refreshed · Catalog corrected 3 card finishes · Finish added to 4 cards"
        )

        outcome = CollectionRefreshOutcome(
            status: .reconciling(completed: 2, total: 5),
            fallbackStatus: .idle
        )
        XCTAssertEqual(
            CollectionRefreshStatusResolver.presentation(for: outcome)?.message,
            "Reconciling card finishes 2 of 5…"
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

    func testNativeCurrencyPricesSortFilterAndValueLikeUnpricedRows() {
        let usd = row(id: "usd", quantity: 2, price: 30)
        let eur = row(id: "eur", quantity: 3, price: 99, currencyCode: "EUR")
        let rows = [eur, usd]

        XCTAssertEqual(
            CollectionQuery.sort(rows, by: .priceHighToLow).map(\.id),
            ["usd", "eur"]
        )
        var filters = CollectionFilters.none
        filters.price = .band(.twentyFiveToFifty)
        XCTAssertEqual(CollectionQuery.filter(rows, with: filters).map(\.id), ["usd"])
        XCTAssertEqual(CollectionValuation.shownValue(for: rows), Money(rounding: 60))
        XCTAssertEqual(eur.price.amount, 99, "the row keeps its native amount for display")
        XCTAssertEqual(eur.price.currencyCode, "EUR")
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

    func testMinimumQuantityFilterMatchesRowsAtOrAboveThreshold() {
        let rows = [
            row(id: "single", quantity: 1, price: 1),
            row(id: "double", quantity: 2, price: 1),
            row(id: "triple", quantity: 3, price: 1)
        ]
        var filters = CollectionFilters.none
        filters.minimumQuantity = 2

        XCTAssertTrue(filters.isActive)
        XCTAssertEqual(
            Set(CollectionQuery.filter(rows, with: filters).map(\.id)),
            ["double", "triple"]
        )
    }

    func testNoMinimumQuantityFilterLeavesEveryQuantityVisible() {
        let rows = [
            row(id: "single", quantity: 1, price: 1),
            row(id: "bulk", quantity: 12, price: 1)
        ]

        XCTAssertFalse(CollectionFilters.none.isActive)
        XCTAssertEqual(CollectionQuery.filter(rows, with: .none).map(\.id), ["single", "bulk"])
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

    // MARK: - Collection tile status

    func testCollectionStatusPrioritizesSlabsAndSealedProducts() {
        var graded = row(
            id: "graded",
            game: .magic,
            variant: .foil,
            price: 42,
            treatmentIDs: [MagicTreatment.surgeFoil.id]
        )
        graded.itemKind = .gradedCard
        graded.itemKindLabel = "PSA 10"

        var sealed = row(id: "sealed", variant: nil, price: 18)
        sealed.itemKind = .sealedProduct
        sealed.itemKindLabel = "Sealed"

        XCTAssertEqual(
            CollectionFinishStatus.resolve(row: graded),
            CollectionFinishStatus(kind: .flat, label: "PSA 10")
        )
        XCTAssertEqual(
            CollectionFinishStatus.resolve(row: sealed),
            CollectionFinishStatus(kind: .flat, label: "Sealed")
        )
    }

    func testCollectionStatusShowsTreatmentAndExtraCountBeforeFinish() {
        let treated = row(
            id: "treated",
            game: .magic,
            variant: .foil,
            price: 9,
            treatmentIDs: [MagicTreatment.surgeFoil.id, MagicTreatment.neonInk.id, "future-treatment"]
        )

        XCTAssertEqual(
            CollectionFinishStatus.resolve(row: treated),
            CollectionFinishStatus(kind: .treatment, label: "Surge Foil +2")
        )
    }

    func testCollectionStatusCanHideDefaultPlainFinish() {
        let plain = row(id: "plain", variant: .normal, price: 1)

        XCTAssertEqual(
            CollectionFinishStatus.resolve(row: plain),
            CollectionFinishStatus(kind: .plain, label: "Normal")
        )
        XCTAssertNil(CollectionFinishStatus.resolve(row: plain, showDefaultFinish: false))
    }

    func testSpecularFinishMatchesRawSurfaceAndTreatmentEvidence() {
        XCTAssertTrue(row(id: "foil", variant: .foil, price: 1).hasSpecularFinish)
        XCTAssertTrue(row(id: "reverse", variant: .reverse, price: 1).hasSpecularFinish)
        XCTAssertFalse(row(id: "normal", variant: .normal, price: 1).hasSpecularFinish)

        let foilTreatment = row(
            id: "foil-treatment",
            game: .magic,
            variant: .foil,
            price: 1,
            treatmentIDs: [MagicTreatment.surgeFoil.id]
        )
        let wrongFinishTreatment = row(
            id: "nonfoil-treatment",
            game: .magic,
            variant: .nonfoil,
            price: 1,
            treatmentIDs: [MagicTreatment.surgeFoil.id]
        )
        XCTAssertTrue(foilTreatment.hasSpecularFinish)
        XCTAssertFalse(wrongFinishTreatment.hasSpecularFinish)

        var graded = row(id: "graded", variant: .foil, price: 1)
        graded.itemKind = .gradedCard
        XCTAssertFalse(graded.hasSpecularFinish)
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
