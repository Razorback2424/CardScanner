import XCTest
@testable import TradingCardScanner

/// Every case here is taken from the live coverage spike. The rejections are
/// real wrong answers the vendor returned, not invented ones.
final class ProductCatalogIdentityTests: XCTestCase {

    // MARK: - Set slugs

    /// Their Japanese slugs are `<tcgdex-ja-id>-<name>-pokemon-japan`, so the id
    /// already resolved for the catalog is an exact key. Verified unique across
    /// all 441 of their Japanese sets.
    func testJapaneseSetSlugComesFromTheCatalogSetID() {
        let slugs = [
            "m2-inferno-x-pokemon-japan",
            "sv3-ruler-of-the-black-flame-pokemon-japan",
            "sv-ruler-of-the-black-flame-deck-build-box-pokemon-japan",
            "sv8a-terastal-fest-ex-pokemon-japan"
        ]

        XCTAssertEqual(
            ProductCatalogIdentity.setSlug(
                setName: "Inferno X", japaneseSetID: "M2",
                game: .pokemonJapan, directory: ProductSetDirectory(sets: slugs.map { (id: $0, name: nil) })),
            "m2-inferno-x-pokemon-japan"
        )
    }

    /// The decoy the name matcher could not resolve: a set and its Deck Build
    /// Box share every word. The `sv3-` prefix separates them; `sv-` does not.
    func testJapanesePrefixRejectsTheDeckBuildBoxDecoy() {
        let slugs = [
            "sv3-ruler-of-the-black-flame-pokemon-japan",
            "sv-ruler-of-the-black-flame-deck-build-box-pokemon-japan"
        ]

        XCTAssertEqual(
            ProductCatalogIdentity.setSlug(
                setName: "Ruler of the Black Flame", japaneseSetID: "SV3",
                game: .pokemonJapan, directory: ProductSetDirectory(sets: slugs.map { (id: $0, name: nil) })),
            "sv3-ruler-of-the-black-flame-pokemon-japan"
        )
    }

    /// Their name for SV8a is "Terastal Fest ex", ours is "Terastal Festival
    /// ex". The id is what makes that irrelevant.
    func testJapaneseSlugSurvivesADifferentSetName() {
        XCTAssertEqual(
            ProductCatalogIdentity.setSlug(
                setName: "Terastal Festival ex", japaneseSetID: "SV8a",
                game: .pokemonJapan,
                directory: ProductSetDirectory(sets: ["sv8a-terastal-fest-ex-pokemon-japan"].map { (id: $0, name: nil) })),
            "sv8a-terastal-fest-ex-pokemon-japan"
        )
    }

    /// Ambiguity is refused rather than guessed at.
    func testAmbiguousJapanesePrefixResolvesToNothing() {
        XCTAssertNil(
            ProductCatalogIdentity.setSlug(
                setName: "Whatever", japaneseSetID: "SV3",
                game: .pokemonJapan,
                directory: ProductSetDirectory(sets: ["sv3-one-pokemon-japan", "sv3-two-pokemon-japan"].map { (id: $0, name: nil) }))
        )
    }

    func testEnglishSetSlugIsBuiltFromTheSetName() {
        let cases: [(String, ProductCatalogIdentity.Game, String)] = [
            ("Art Series: FINAL FANTASY", .magic, "art-series-final-fantasy-magic-the-gathering"),
            ("Avatar: The Last Airbender", .magic, "avatar-the-last-airbender-magic-the-gathering"),
            ("Trick or Trade BOOster Bundle 2023", .pokemon, "trick-or-trade-booster-bundle-2023-pokemon"),
            ("Jumbo Cards", .pokemon, "jumbo-cards-pokemon")
        ]

        for (name, game, expected) in cases {
            XCTAssertEqual(
                ProductCatalogIdentity.setSlug(
                    setName: name, japaneseSetID: nil, game: game, directory: ProductSetDirectory(sets: [].map { (id: $0, name: nil) })),
                expected,
                "\(name)"
            )
        }
    }

    /// The vendor drops `&`; `canonicalText` expands it to "and". Using the
    /// wrong one here yields a slug that does not exist.
    func testAmpersandIsDroppedNotExpanded() {
        XCTAssertEqual(
            ProductCatalogIdentity.slugify("Miscellaneous Cards & Products"),
            "miscellaneous-cards-products"
        )
        XCTAssertTrue(
            CatalogIdentityNormalization.canonicalText("Miscellaneous Cards & Products")
                .contains("and"),
            "the catalog normalizer expands & — the two must stay different"
        )
    }

    // MARK: - Accepting a result

    /// The spike's worst answer: right name, wrong set, wrong decade, $5.45 for
    /// a card worth pennies.
    func testRejectsTheWrongSetEvenWhenTheNameIsExact() {
        XCTAssertFalse(
            ProductCatalogIdentity.isSameCard(
                requestedName: "Oddish",
                requestedNumber: "001/080",
                requestedSetSlug: "m2-inferno-x-pokemon-japan",
                candidateName: "Oddish",
                candidateNumber: "005/128",
                candidateSetSlug: "base-expansion-pack-pokemon-japan"
            )
        )
    }

    /// The subtle one. Same set, same name, and `localNumber` reduces both
    /// `001/086` and `001/114` to "1" — so the set total is the only thing that
    /// tells these two Snivys apart.
    func testRejectsASameNumberedCardFromADifferentPrintRun() {
        XCTAssertFalse(
            ProductCatalogIdentity.numbersMatch("001/086", "001/114"),
            "001/086 and 001/114 are different cards"
        )
        XCTAssertEqual(
            CatalogIdentityNormalization.localNumber("001/086"),
            CatalogIdentityNormalization.localNumber("001/114"),
            "localNumber cannot separate them, which is why it is not used here"
        )

        XCTAssertFalse(
            ProductCatalogIdentity.isSameCard(
                requestedName: "Snivy",
                requestedNumber: "001/086",
                requestedSetSlug: "miscellaneous-cards-products-pokemon",
                candidateName: "Snivy - 1/114 (Cosmos Holo)",
                candidateNumber: "001/114",
                candidateSetSlug: "miscellaneous-cards-products-pokemon"
            )
        )
    }

    func testAcceptsTheMatchesTheSpikeGotRight() {
        XCTAssertTrue(
            ProductCatalogIdentity.isSameCard(
                requestedName: "Trevenant",
                requestedNumber: "017/196",
                requestedSetSlug: "trick-or-trade-booster-bundle-2023-pokemon",
                candidateName: "Trevenant",
                candidateNumber: "017/196",
                candidateSetSlug: "trick-or-trade-booster-bundle-2023-pokemon"
            )
        )
        XCTAssertTrue(
            ProductCatalogIdentity.isSameCard(
                requestedName: "Venusaur ex (Stellar Crown Stamp)",
                requestedNumber: "001/142",
                requestedSetSlug: "miscellaneous-cards-products-pokemon",
                candidateName: "Venusaur ex (Stellar Crown Stamp)",
                candidateNumber: "001/142",
                candidateSetSlug: "miscellaneous-cards-products-pokemon"
            )
        )
    }

    /// Double-faced tokens print as "13 // 11". That is one identifier, not a
    /// number over a total, and it has to survive comparison intact.
    func testDoubleFacedTokenNumbersSurvive() {
        XCTAssertTrue(ProductCatalogIdentity.numbersMatch("13 // 11", "13 // 11"))
        XCTAssertTrue(ProductCatalogIdentity.numbersMatch("2 // 11", "02 // 11"))
        XCTAssertFalse(ProductCatalogIdentity.numbersMatch("13 // 11", "13 // 12"))

        XCTAssertTrue(
            ProductCatalogIdentity.isSameCard(
                requestedName: "Ballistic Boulder // Soldier (0011) Double-Sided Token",
                requestedNumber: "13 // 11",
                requestedSetSlug: "avatar-the-last-airbender-magic-the-gathering",
                candidateName: "Ballistic Boulder // Soldier (0011) Double-Sided Token",
                candidateNumber: "13 // 11",
                candidateSetSlug: "avatar-the-last-airbender-magic-the-gathering"
            )
        )
    }

    func testLeadingZerosAreNotIdentity() {
        XCTAssertTrue(ProductCatalogIdentity.numbersMatch("011", "11"))
        XCTAssertTrue(ProductCatalogIdentity.numbersMatch("001/080", "1/80"))
    }

    /// A vendor that omits the denominator is not claiming a different print
    /// run, so a bare number still matches one that carries a total.
    func testAMissingTotalIsNotADisagreement() {
        XCTAssertTrue(ProductCatalogIdentity.numbersMatch("011", "011/165"))
        XCTAssertTrue(ProductCatalogIdentity.numbersMatch("011/165", "011"))
    }

    func testEmptyNumberNeverMatches() {
        XCTAssertFalse(ProductCatalogIdentity.numbersMatch("", ""))
        XCTAssertFalse(ProductCatalogIdentity.numbersMatch("", "11"))
    }

    // MARK: - Game routing

    /// A Japanese printing is a separate product line, not a locale.
    func testJapaneseCardsRouteToTheJapaneseProductLine() {
        XCTAssertEqual(
            ProductCatalogIdentity.game(for: .pokemon, catalogID: "M2-001"),
            .pokemonJapan
        )
        XCTAssertEqual(
            ProductCatalogIdentity.game(for: .pokemon, catalogID: "sv08.5-001"),
            .pokemon
        )
        XCTAssertEqual(
            ProductCatalogIdentity.game(for: .magic, catalogID: nil),
            .magic
        )
    }

    // MARK: - Matching the vendor's own set names

    /// The vendor prefixes sets by era; TCGdex names carry no prefix. Deriving
    /// the slug from the catalog name resolved 55 of 163 browsable Pokémon sets,
    /// so two thirds of the catalogue failed set resolution before a request was
    /// made — the reason a collection could sit on hundreds of euro-only prices
    /// while the fallback reported progress and changed nothing.
    func testVendorSetsAreFoundByPublishedName() {
        let directory = ProductSetDirectory(sets: [
            (id: "sv-prismatic-evolutions-pokemon", name: "SV: Prismatic Evolutions"),
            (id: "ex-dragon-pokemon", name: "EX Dragon"),
            (id: "swsh01-sword-shield-base-set-pokemon", name: "SWSH01: Sword & Shield Base Set"),
            (id: "base-set-pokemon", name: "Base Set")
        ])

        // Colon-prefixed era label.
        XCTAssertEqual(
            directory.slug(forCatalogSetName: "Prismatic Evolutions", game: .pokemon),
            "sv-prismatic-evolutions-pokemon"
        )
        // Bare era token.
        XCTAssertEqual(
            directory.slug(forCatalogSetName: "Dragon", game: .pokemon),
            "ex-dragon-pokemon"
        )
        XCTAssertEqual(
            directory.slug(forCatalogSetName: "Sword & Shield", game: .pokemon),
            "swsh01-sword-shield-base-set-pokemon"
        )
        // Exact names still match, and still win.
        XCTAssertEqual(
            directory.slug(forCatalogSetName: "Base Set", game: .pokemon),
            "base-set-pokemon"
        )
    }

    /// A key two different sets both claim is dropped rather than guessed —
    /// picking either is how a 1996 printing gets returned for a 2025 card.
    func testAmbiguousSetNamesResolveToNothing() {
        let directory = ProductSetDirectory(sets: [
            (id: "ex-dragon-pokemon", name: "EX Dragon"),
            (id: "sv-dragon-pokemon", name: "SV Dragon")
        ])

        XCTAssertNil(directory.slug(forCatalogSetName: "Dragon", game: .pokemon))
    }

    /// An exact name beats an era-stripped one, so a set whose real name
    /// collides with another's suffix cannot be displaced by it.
    func testExactNameOutranksAnEraStrippedMatch() {
        let directory = ProductSetDirectory(sets: [
            (id: "ex-dragon-pokemon", name: "EX Dragon"),
            (id: "dragon-pokemon", name: "Dragon")
        ])

        XCTAssertEqual(
            directory.slug(forCatalogSetName: "Dragon", game: .pokemon),
            "dragon-pokemon"
        )
    }

    /// A set the vendor does not carry stays unresolved rather than falling
    /// back to a derived slug that does not exist.
    func testUnknownSetStaysUnresolved() {
        let directory = ProductSetDirectory(sets: [
            (id: "base-set-pokemon", name: "Base Set")
        ])

        XCTAssertNil(directory.slug(forCatalogSetName: "Some Set", game: .pokemon))
    }
}
