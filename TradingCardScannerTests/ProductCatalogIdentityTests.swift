import XCTest
@testable import TradingCardScanner

private actor DirectoryLoadCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

/// Every case here is taken from the live coverage spike. The rejections are
/// real wrong answers the vendor returned, not invented ones.
final class ProductCatalogIdentityTests: XCTestCase {
    func testCardLevelReviewedMagicAliasesResolveOnlyExactProducts() throws {
        struct Proof: Decodable {
            struct Card: Decodable { let name, number, productID: String }
            struct Case: Decodable {
                let code, catalogName, vendorName, groupID: String
                let cards, products: [Card]
            }
            let cases: [Case]
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "magic-product-proof", withExtension: "json",
            subdirectory: "TradingCards/SetPricingAudit"))
        let proof = try JSONDecoder().decode(Proof.self, from: Data(contentsOf: url))
        let directoryURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "vendor-groups", withExtension: "json",
            subdirectory: "TradingCards/SetPricingAudit"))
        let inventory = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directoryURL)) as? [String: Any])
        let groups = try XCTUnwrap(inventory["groups"] as? [[String: Any]])
        let directory = ProductSetDirectory(sets: try groups.filter { $0["game"] as? String == "magic" }.map {
            (id: try XCTUnwrap($0["id"] as? String), name: try XCTUnwrap($0["name"] as? String))
        })
        var failures: [String] = []
        XCTAssertEqual(proof.cases.count, 10)
        XCTAssertEqual(proof.cases.reduce(0) { $0 + $1.cards.count }, 594)
        for entry in proof.cases {
            if directory.slug(forCatalogSetName: entry.catalogName, game: .magic) != entry.groupID {
                failures.append("\(entry.code): unresolved alias")
            }
            // IDs are opaque TCGplayer group/product IDs in this fixture, not
            // asserted JustTCG slugs/UUIDs. Test real names and printed numbers
            // against every product in the independently captured group.
            let candidates = try entry.products.map { product in
                try JSONDecoder().decode(JustTCGV2Card.self, from: JSONSerialization.data(withJSONObject: [
                    "id": product.productID, "name": product.name, "number": product.number,
                    "game": ["id": "magic-the-gathering"], "set": ["id": entry.groupID, "name": entry.vendorName]
                ]))
            }
            for card in entry.cards {
                let identity = GradedCardIdentity(name: card.name, setName: entry.catalogName, collectorNumber: card.number)
                let matches = candidates.filter { identity.matches($0, game: .magic, expectedSetSlug: entry.groupID) }
                if matches.map(\.id) != [card.productID] {
                    failures.append("\(entry.code) / \(card.name) \(card.number): nonunique or wrong product")
                }
            }
        }
        XCTAssertEqual(failures, [], "Aliases need full card-level membership, collector-number and uniqueness proof")
    }

    func testSystematicReviewedSetAliasesResolveWithoutMergingNeighboringReleases() throws {
        struct Inventory: Decodable {
            struct Group: Decodable { let game, id, name: String }
            let groups: [Group]
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "vendor-groups", withExtension: "json",
            subdirectory: "TradingCards/SetPricingAudit"))
        let groups = try JSONDecoder().decode(Inventory.self, from: Data(contentsOf: url)).groups
        let magic = ProductSetDirectory(sets: groups.filter { $0.game == "magic" }.map { (id: $0.id, name: Optional($0.name)) })
        for (name, id) in [
            ("Tenth Edition", "1"), ("Seventh Edition", "2"), ("Eighth Edition", "3"), ("Ninth Edition", "4"),
            ("Limited Edition Alpha", "7"), ("Limited Edition Beta", "17"),
            ("Magic 2010", "68"), ("Magic 2011", "69"), ("Magic 2012", "70"),
            ("Magic 2013", "364"), ("Magic 2014", "1113"), ("Magic 2015", "1293"),
            ("Commander 2011", "25"), ("Midnight Hunt Commander", "2893"),
            ("New Capenna Commander", "3031"), ("Neon Dynasty Commander", "2967"), ("Crimson Vow Commander", "2900"),
            ("The Brothers' War Retro Artifacts", "17665"), ("Game Night", "2359"),
            ("Game Night 2019", "2562"), ("Game Night: Free-for-All", "3129"),
            ("The Lord of the Rings: Tales of Middle-earth", "23019")
        ] {
            XCTAssertEqual(magic.slug(forCatalogSetName: name, game: .magic), id, name)
        }
        let pokemon = ProductSetDirectory(sets: groups.filter { $0.game == "pokemon" }.map { (id: $0.id, name: Optional($0.name)) })
        XCTAssertEqual(pokemon.slug(forCatalogSetName: "Scarlet & Violet Energy", game: .pokemon), "24382")
        XCTAssertEqual(pokemon.slug(forCatalogSetName: "Pokémon Rumble", game: .pokemon), "1433")
        for (left, right) in [
            ("Magic 2010", "Magic 2010 (M11)"), ("Limited Edition Alpha", "Limited Edition Beta"),
            ("Game Night", "Game Night 2019"), ("New Capenna Commander", "Streets of New Capenna"),
            ("Duel Decks Anthology: Elves vs. Goblins", "Duel Decks: Elves vs. Goblins"),
            ("Friday Night Magic 2000", "FNM Promos"),
            ("GRN Guild Kit", "RNA Guild Kit"), ("GRN Guild Kit", "Guilds of Ravnica"),
            ("Time Spiral Timeshifted", "Time Spiral"), ("Universes Within", "Secret Lair Drop Series"),
            ("Marvel Universe", "Marvel's Spider-Man"), ("Ugin's Fate", "Fate Reforged"),
            ("Modern Event Deck 2014", "Modern Masters 2015")
        ] {
            XCTAssertNotEqual(CatalogIdentityNormalization.canonicalSetName(left, game: .magic),
                CatalogIdentityNormalization.canonicalSetName(right, game: .magic), "\(left) / \(right)")
        }
    }

    func testRumbleAliasMatchesEveryIndependentlyCapturedCatalogCard() throws {
        try assertPokemonWholeSetProof("rumble-proof", cardCount: 16)
    }

    func testCreatorPackAliasMatchesAllFiveCardsAndExcludesTheSealedPack() throws {
        try assertPokemonWholeSetProof("creator-pack-proof", cardCount: 5)
        XCTAssertNotEqual(CatalogIdentityNormalization.canonicalSetName("Poké Card Creator Pack", game: .pokemon),
            CatalogIdentityNormalization.canonicalSetName("EX Hidden Legends", game: .pokemon))
    }

    private func assertPokemonWholeSetProof(_ resource: String, cardCount: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        struct Proof: Decodable {
            struct Card: Decodable { let name, number: String }
            let catalogName, vendorName, groupID: String
            let cards, products: [Card]
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: resource, withExtension: "json",
            subdirectory: "TradingCards/SetPricingAudit"))
        let proof = try JSONDecoder().decode(Proof.self, from: Data(contentsOf: url))
        let directory = ProductSetDirectory(sets: [(id: proof.groupID, name: proof.vendorName)])
        let resolved = try XCTUnwrap(directory.slug(forCatalogSetName: proof.catalogName, game: .pokemon))
        XCTAssertEqual(resolved, proof.groupID)
        XCTAssertEqual(proof.cards.count, cardCount, file: file, line: line)
        for card in proof.cards {
            let matches = proof.products.filter {
                ProductCatalogIdentity.isSameCard(requestedName: card.name, requestedNumber: card.number,
                    requestedSetSlug: resolved, candidateName: $0.name, candidateNumber: $0.number,
                    candidateSetSlug: proof.groupID)
            }
            XCTAssertEqual(matches.count, 1, card.name)
        }
    }


    func testSetDirectoryProviderCachesPerGameUntilTTL() async throws {
        let provider = ProductSetDirectoryProvider(ttl: 60)
        let counter = DirectoryLoadCounter()
        let directory = ProductSetDirectory(sets: [
            (id: "base-set-pokemon", name: "Base Set")
        ])
        let first = Date(timeIntervalSince1970: 1_000)

        _ = try await provider.directory(for: .pokemon, now: first) {
            await counter.increment()
            return directory
        }
        _ = try await provider.directory(
            for: .pokemon,
            now: first.addingTimeInterval(59)
        ) {
            await counter.increment()
            return directory
        }
        _ = try await provider.directory(
            for: .pokemon,
            now: first.addingTimeInterval(60)
        ) {
            await counter.increment()
            return directory
        }

        let loads = await counter.count
        XCTAssertEqual(loads, 2)
    }

    // MARK: - Set slugs

    func testCancelledDirectoryWaiterLeavesSharedLoadAndCacheIntact() async throws {
        let provider = ProductSetDirectoryProvider()
        let counter = DirectoryLoadCounter()
        let directory = ProductSetDirectory(sets: [(id: "base-set-pokemon", name: "Base Set")])
        let release = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        defer { release.continuation.yield(()); release.continuation.finish() }
        let started = expectation(description: "Shared directory download started")
        let cancelled = expectation(description: "Cancelled waiter exits before the download finishes")
        let original = Task {
            do {
                _ = try await provider.directory(for: .pokemon) {
                    await counter.increment()
                    started.fulfill()
                    for await _ in release.stream { break }
                    return directory
                }
                XCTFail("A cancelled waiter must not return a directory")
            } catch is CancellationError {
                cancelled.fulfill()
            } catch { XCTFail("Unexpected error: \(error)") }
        }
        await fulfillment(of: [started], timeout: 2)
        original.cancel()
        await fulfillment(of: [cancelled], timeout: 1)
        let remaining = Task {
            try await provider.directory(for: .pokemon) {
                await counter.increment()
                return ProductSetDirectory(sets: [])
            }
        }
        release.continuation.yield(())
        release.continuation.finish()
        let value = try await remaining.value
        await original.value
        XCTAssertEqual(value.slugs, ["base-set-pokemon"])
        let cached = try await provider.directory(for: .pokemon) {
            await counter.increment()
            return ProductSetDirectory(sets: [])
        }
        XCTAssertEqual(cached.slugs, value.slugs)
        let loads = await counter.count
        XCTAssertEqual(loads, 1)
    }

    func testFailedSharedDirectoryLoadCanBeRetried() async throws {
        let provider = ProductSetDirectoryProvider()
        do {
            _ = try await provider.directory(for: .pokemon) { throw URLError(.notConnectedToInternet) }
            XCTFail("Expected the download failure")
        } catch let error as URLError { XCTAssertEqual(error.code, .notConnectedToInternet) }
        let directory = try await provider.directory(for: .pokemon) {
            ProductSetDirectory(sets: [(id: "base-set-pokemon", name: "Base Set")])
        }
        XCTAssertEqual(directory.slugs, ["base-set-pokemon"])
    }

    func testEnglish151SetAliasResolvesThePublishedVendorSlug() {
        let slug = "sv-scarlet-violet-151-pokemon"
        let directory = ProductSetDirectory(sets: [
            (id: slug, name: "SV: Scarlet & Violet 151")
        ])

        for name in ["151", "SV: 151", "Scarlet & Violet—151", "SV: Scarlet & Violet 151"] {
            XCTAssertEqual(ProductCatalogIdentity.setSlug(
                setName: name, japaneseSetID: nil, game: .pokemon, directory: directory
            ), slug, name)
            XCTAssertEqual(CatalogIdentityNormalization.canonicalSetName(name, game: .pokemon), "151")
        }
        XCTAssertNotEqual(CatalogIdentityNormalization.canonicalSetName("Scarlet & Violet", game: .pokemon), "151")
        XCTAssertNotEqual(CatalogIdentityNormalization.canonicalSetName("Pokemon Card 151", game: .pokemon), "151")
    }

    func testEnglish151AliasRefusesAmbiguousVendorSets() {
        let directory = ProductSetDirectory(sets: [
            (id: "vendor-151-one", name: "SV: Scarlet & Violet 151"),
            (id: "vendor-151-two", name: "Scarlet & Violet—151")
        ])
        XCTAssertNil(ProductCatalogIdentity.setSlug(
            setName: "151", japaneseSetID: nil, game: .pokemon, directory: directory
        ))
    }

    func testMagicCommanderAliasesKeepMainExpansionsAndGamesDistinct() {
        for (commander, expansion) in [
            ("Forgotten Realms Commander", "Adventures in the Forgotten Realms"),
            ("Tales of Middle-earth Commander", "The Lord of the Rings: Tales of Middle-earth"),
            ("Warhammer 40,000 Commander", "Universes Beyond: Fallout")
        ] {
            XCTAssertNotEqual(CatalogIdentityNormalization.canonicalSetName(commander, game: .magic),
                CatalogIdentityNormalization.canonicalSetName(expansion, game: .magic))
        }
        XCTAssertNotEqual(CatalogIdentityNormalization.canonicalSetName("Warhammer 40,000 Commander", game: .pokemon),
            CatalogIdentityNormalization.canonicalSetName("Universes Beyond: Warhammer 40,000", game: .pokemon))
    }

    func testPokemonEraAliasesKeepExpansionsAndPromosDistinct() {
        for (catalog, other) in [
            ("Sword & Shield", "Base Set"),
            ("Evolving Skies", "SWSH08: Fusion Strike"),
            ("Sun & Moon", "SM - Cosmic Eclipse"),
            ("Sun & Moon", "Base Set"),
            ("Sun & Moon", "SM Promos"),
            ("Paldea Evolved", "SV04: Paradox Rift"),
            ("Paldea Evolved", "SVunknown: Paldea Evolved"),
            ("XY", "XY - Roaring Skies")
        ] {
            XCTAssertNotEqual(CatalogIdentityNormalization.canonicalSetName(catalog, game: .pokemon),
                CatalogIdentityNormalization.canonicalSetName(other, game: .pokemon), "\(catalog) / \(other)")
        }
        XCTAssertEqual(CatalogIdentityNormalization.canonicalSetName("SM Promos", game: .pokemon), "sm promo")
        XCTAssertEqual(CatalogIdentityNormalization.canonicalSetName("SWSH Black Star Promos", game: .pokemon),
            "sword and shield promo")
    }

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

    func testAmbiguousJapanesePrefixCannotBeOverriddenByANameMatch() {
        let directory = ProductSetDirectory(sets: [
            (id: "sv3-one-pokemon-japan", name: "Requested Set"),
            (id: "sv3-two-pokemon-japan", name: "Another Set")
        ])

        XCTAssertNil(ProductCatalogIdentity.setSlug(setName: "Requested Set", japaneseSetID: "SV3",
                                                    game: .pokemonJapan, directory: directory))
    }

    func testDuplicateJapaneseDirectoryRowsAreNotConflictingSets() {
        let slug = "sv3-one-pokemon-japan"
        let directory = ProductSetDirectory(sets: [(id: slug, name: nil), (id: slug, name: nil)])

        XCTAssertEqual(ProductCatalogIdentity.setSlug(setName: "Unrelated Provider Name", japaneseSetID: "SV3",
                                                      game: .pokemonJapan, directory: directory), slug)
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

    func testAmbiguousExactNamesCannotFallBackToAnEraStrippedAlias() {
        let directory = ProductSetDirectory(sets: [
            (id: "first-dragon-pokemon", name: "Dragon"),
            (id: "second-dragon-pokemon", name: "Dragon"),
            (id: "ex-dragon-pokemon", name: "EX Dragon")
        ])

        XCTAssertNil(directory.slug(forCatalogSetName: "Dragon", game: .pokemon))
    }

    func testAmbiguousPublishedNamesCannotFallBackToADerivedSlug() {
        let directory = ProductSetDirectory(sets: [
            (id: "dragon-pokemon", name: "Dragon"),
            (id: "other-dragon-pokemon", name: "Dragon")
        ])

        XCTAssertNil(directory.slug(forCatalogSetName: "Dragon", game: .pokemon))
    }

    /// An exact name beats an era-stripped one, so a set whose real name
    /// collides with another's suffix cannot be displaced by it.
    func testExactNameOutranksAnEraStrippedMatch() {
        let directory = ProductSetDirectory(sets: [
            (id: "ex-dragon-pokemon", name: "EX Dragon"),
            (id: "sv-dragon-pokemon", name: "SV Dragon"),
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
