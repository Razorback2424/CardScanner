import XCTest
@testable import TradingCardScanner

final class PricingTests: XCTestCase {
    private func pokemonCard(
        variantsJSON: String = #"{ "firstEdition": false, "holo": false, "normal": true, "reverse": true }"#,
        pricingJSON: String? = #"""
        { "tcgplayer": {
            "updated": "2026-08-23T13:07:00.000Z",
            "normal": { "marketPrice": 0.42 },
            "reverse-holofoil": { "marketPrice": 3.75 }
        } }
        """#
    ) throws -> IdentifiedCard {
        let pricing = pricingJSON.map { ", \"pricing\": \($0)" } ?? ""
        let json = """
        {
          "id": "sv08.5-074",
          "localId": "074",
          "name": "Eevee",
          "image": "https://assets.tcgdex.net/en/sv/sv08.5/074",
          "set": { "id": "sv08.5", "name": "Prismatic Evolutions",
                   "cardCount": { "total": 180, "official": 131 } },
          "variants": \(variantsJSON)\(pricing)
        }
        """
        return .pokemon(try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8)), setCode: "PRE")
    }

    private func magicCard() throws -> IdentifiedCard {
        let json = """
        {
          "id": "3f0a1f52-0000-4000-8000-000000000001",
          "name": "Llanowar Elves",
          "set": "ecl", "set_name": "Eclipse", "collector_number": "218",
          "lang": "en", "digital": false, "frame": "2015",
          "released_at": "2026-02-06",
          "finishes": ["nonfoil", "foil"],
          "prices": { "usd": "1.25", "usd_foil": "6.40", "usd_etched": null }
        }
        """
        return .magic(try JSONDecoder().decode(ScryfallCard.self, from: Data(json.utf8)))
    }

    // MARK: - A price belongs to printing *and* variant

    func testReverseHoloReadsTheReverseHoloListing() throws {
        guard case let .price(price) = CardPricing.price(for: try pokemonCard(), variant: .reverse) else {
            return XCTFail("Expected a price")
        }

        XCTAssertEqual(price.unitMarketPriceUSD, 3.75)
        XCTAssertEqual(price.sourceVariantID, "reverse-holofoil")
        XCTAssertEqual(price.source, .tcgplayer)
    }

    /// The heart of the pricing promise: a Master Ball parallel has no listing of
    /// its own, so it gets no price rather than the reverse holo's.
    func testUnmappedVariantIsUnavailableRatherThanBorrowingAnotherFinishesPrice() throws {
        let card = try pokemonCard()

        XCTAssertEqual(CardPricing.price(for: card, variant: .masterBall), .unavailable(.tcgplayer))
        XCTAssertEqual(CardPricing.price(for: card, variant: .pokeBall), .unavailable(.tcgplayer))
        XCTAssertNil(CardPricing.tcgplayerListing(for: .masterBall))
    }

    func testUnknownFinishGetsNoPrice() throws {
        XCTAssertEqual(CardPricing.price(for: try pokemonCard(), variant: nil), .unavailable(.tcgplayer))
    }

    func testCardWithNoPricingAtAllIsUnavailable() throws {
        let card = try pokemonCard(pricingJSON: nil)

        XCTAssertEqual(CardPricing.price(for: card, variant: .reverse), .unavailable(nil))
        XCTAssertTrue(card.marketPrices.isEmpty)
    }

    func testPublishedPricesOnlyCoverVariantsTheCatalogSaysExist() throws {
        // The catalog publishes a holofoil price but says this printing has no
        // holo version, so the holo price is not advertised.
        let card = try pokemonCard(
            variantsJSON: #"{ "firstEdition": false, "holo": false, "normal": true, "reverse": true }"#,
            pricingJSON: #"""
            { "tcgplayer": {
                "normal": { "marketPrice": 0.42 },
                "holofoil": { "marketPrice": 99.0 },
                "reverse-holofoil": { "marketPrice": 3.75 }
            } }
            """#
        )

        XCTAssertEqual(card.marketPrices.map(\.value), [0.42, 3.75])
    }

    // MARK: - Magic

    func testMagicFinishesMapOntoScryfallPriceKeys() throws {
        let card = try magicCard()

        guard case let .price(foil) = CardPricing.price(for: card, variant: .foil) else {
            return XCTFail("Expected a foil price")
        }
        XCTAssertEqual(foil.unitMarketPriceUSD, 6.40)
        XCTAssertEqual(foil.sourceVariantID, "usd_foil")
        // Scryfall publishes no "current through" stamp, so the app may only ever
        // report when it checked.
        XCTAssertNil(foil.sourceUpdatedAt)
        XCTAssertFalse(PriceSource.scryfall.publishesSourceTimestamp)
    }

    func testMagicEtchedIsUnavailableWhenScryfallHasNoNumberForIt() throws {
        XCTAssertEqual(CardPricing.price(for: try magicCard(), variant: .etched), .unavailable(.scryfall))
    }

    func testMagicReleaseDateDrivesSetOrdering() throws {
        XCTAssertGreaterThan(try magicCard().setReleaseOrder, 20_000)
    }

    // MARK: - Freshness is a separate fact from the price

    func testSourceTimestampIsPreferredOverFetchTimeForFreshness() {
        let fetched = Date(timeIntervalSince1970: 1_000_000)
        let sourceUpdated = Date(timeIntervalSince1970: 900_000)
        let display = PriceDisplay(
            amount: 42,
            source: .tcgplayer,
            sourceUpdatedAt: sourceUpdated,
            fetchedAt: fetched,
            lastCheckedAt: fetched
        )

        XCTAssertEqual(display.effectiveAsOf, sourceUpdated)
    }

    func testPriceGoesStaleAgainstTheSourceTimestampNotTheFetchTime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // Checked seconds ago, but the market data behind it is three days old.
        let display = PriceDisplay(
            amount: 42,
            source: .tcgplayer,
            sourceUpdatedAt: now.addingTimeInterval(-3 * 24 * 60 * 60),
            fetchedAt: now,
            lastCheckedAt: now
        )

        XCTAssertEqual(display.state(now: now), .stale)
    }

    func testNeverCheckedIsNotTheSameAsUnavailable() {
        XCTAssertEqual(PriceDisplay.unknown.state(), .unknown)

        let asked = PriceDisplay(amount: nil, source: .tcgplayer, fetchedAt: .now, lastCheckedAt: .now)
        XCTAssertEqual(asked.state(), .unavailable)
    }

    /// Offline should not turn yesterday's price into nothing.
    func testFailedRefreshKeepsThePreviousPrice() {
        let record = PriceRecord(key: "k", game: .pokemon, printingID: "sv08.5-074", variantID: "reverse")
        let yesterday = Date.now.addingTimeInterval(-24 * 60 * 60)
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 42.81,
                currencyCode: "USD",
                source: .tcgplayer,
                sourceVariantID: "reverse-holofoil",
                sourceUpdatedAt: yesterday,
                fetchedAt: yesterday
            )
        )

        record.recordFailure(at: .now)

        XCTAssertEqual(record.unitMarketPriceUSD, 42.81)
        XCTAssertEqual(record.fetchedAt, yesterday)
        XCTAssertTrue(record.display.refreshFailed)
    }

    func testSuccessfulRefreshClearsAPreviousFailure() {
        let record = PriceRecord(key: "k", game: .pokemon, printingID: "sv08.5-074", variantID: "reverse")
        record.recordFailure(at: .now)
        record.applyUnavailable(source: .tcgplayer, at: .now)

        XCTAssertFalse(record.display.refreshFailed)
        XCTAssertEqual(record.display.state(), .unavailable)
    }

    // MARK: - Refresh scheduling

    /// A target that already has a price and was checked minutes ago is left
    /// alone; one that is overdue, or has never been asked about, is not.
    private func pricedTarget(
        _ printingID: String,
        variantID: String = "reverse",
        lastCheckedAt: Date?
    ) -> PriceTarget {
        PriceTarget(
            game: .pokemon,
            printingID: printingID,
            catalogPrintingID: nil,
            setCode: "PRE",
            variantID: variantID,
            importedIdentity: nil,
            catalogMetadataCheckedAt: nil,
            lastFailureAt: nil,
            hasPrice: true,
            lastCheckedAt: lastCheckedAt
        )
    }

    func testAutomaticRefreshSkipsPricesCheckedRecently() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let targets = [
            pricedTarget("a", lastCheckedAt: now.addingTimeInterval(-60)),
            pricedTarget("b", lastCheckedAt: now.addingTimeInterval(-12 * 60 * 60)),
            pricedTarget("c", variantID: "normal", lastCheckedAt: nil)
        ]

        XCTAssertEqual(
            PriceRefreshController.staleTargets(from: targets, now: now).map(\.printingID),
            ["b", "c"]
        )
    }

    /// Every owned copy of a printing-and-variant shares one price record, so a
    /// refresh asks once no matter how many copies are owned.
    func testPriceKeyIsPerPrintingAndVariant() {
        XCTAssertEqual(
            PriceRecord.key(game: .pokemon, printingID: "sv08.5-074", variantID: "masterBall"),
            "pokemon:sv08.5-074:masterBall"
        )
        XCTAssertNotEqual(
            PriceRecord.key(game: .pokemon, printingID: "sv08.5-074", variantID: "masterBall"),
            PriceRecord.key(game: .pokemon, printingID: "sv08.5-074", variantID: "reverse")
        )
    }

    // MARK: - Provider timestamps

    func testProviderTimestampsParseLeniently() {
        XCTAssertNotNil(FlexibleDate.parse("2026-08-23T13:07:00.000Z"))
        XCTAssertNotNil(FlexibleDate.parse("2026-08-23T13:07:00Z"))
        XCTAssertNotNil(FlexibleDate.parse("2026-08-23"))
        // An unrecognised format must not become a false freshness claim.
        XCTAssertNil(FlexibleDate.parse("last Tuesday"))
        XCTAssertNil(FlexibleDate.parse(""))
    }

    func testTCGdexUpdatedTimestampReachesThePrice() throws {
        guard case let .price(price) = CardPricing.price(for: try pokemonCard(), variant: .normal) else {
            return XCTFail("Expected a price")
        }

        XCTAssertNotNil(price.sourceUpdatedAt)
        XCTAssertNotEqual(price.sourceUpdatedAt, price.fetchedAt)
    }

    // MARK: - Parallel patterns (variants_detailed)

    /// Shaped exactly like TCGdex's live response for a Prismatic Evolutions
    /// card: three `reverse` entries, told apart only by `foil` and by the
    /// marketplace product id inside each entry's own pricing block.
    private func ballPatternCard() throws -> IdentifiedCard {
        let json = """
        {
          "id": "sv08.5-001",
          "localId": "001",
          "name": "Exeggcute",
          "set": { "id": "sv08.5", "name": "Prismatic Evolutions",
                   "cardCount": { "total": 180, "official": 131 } },
          "variants": { "firstEdition": false, "holo": false, "normal": true, "reverse": true },
          "variants_detailed": [
            { "type": "normal", "size": "standard", "variantId": "endfynwn4n10gzq",
              "pricing": { "tcgplayer": { "updated": "2026-08-24T08:03:25.798Z",
                "normal": { "productId": 610356, "marketPrice": 0.02 } } } },
            { "type": "reverse", "size": "standard", "variantId": "cm4kqul3x1bwlz1f",
              "pricing": { "tcgplayer": { "updated": "2026-08-24T08:03:25.798Z",
                "reverse-holofoil": { "productId": 610356, "marketPrice": 0.16 } } } },
            { "type": "reverse", "size": "standard", "foil": "pokeball",
              "variantId": "3739bbtj3i910y5ynn9xc6ryf",
              "pricing": { "tcgplayer": { "updated": "2026-08-24T08:03:25.798Z",
                "holofoil": { "productId": 610536, "marketPrice": 0.32 } } } },
            { "type": "reverse", "size": "standard", "foil": "masterball",
              "variantId": "2asus05yghmpd1ud1sdmlq3as4e",
              "pricing": { "tcgplayer": { "updated": "2026-08-24T08:03:25.798Z",
                "holofoil": { "productId": 610637, "marketPrice": 1.04 } } } }
          ]
        }
        """
        return .pokemon(try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8)), setCode: "PRE")
    }

    func testEachBallPatternGetsItsOwnPrice() throws {
        let card = try ballPatternCard()

        guard case let .price(pokeBall) = CardPricing.price(for: card, variant: .pokeBall),
              case let .price(masterBall) = CardPricing.price(for: card, variant: .masterBall) else {
            return XCTFail("Expected a price for each ball pattern")
        }

        XCTAssertEqual(pokeBall.unitMarketPriceUSD, 0.32)
        XCTAssertEqual(masterBall.unitMarketPriceUSD, 1.04)
        XCTAssertEqual(pokeBall.source, .tcgplayer)
    }

    /// The reason the flat pricing object could not do this job: three distinct
    /// objects, three distinct prices, none of them borrowed from another.
    func testBallPatternsDoNotShareThePlainReversePrice() throws {
        let card = try ballPatternCard()

        let amounts = [PhysicalVariant.reverse, .pokeBall, .masterBall].map { variant -> Double? in
            guard case let .price(price) = CardPricing.price(for: card, variant: variant) else { return nil }
            return price.unitMarketPriceUSD
        }

        XCTAssertEqual(amounts, [0.16, 0.32, 1.04])
        XCTAssertEqual(Set(amounts.compactMap { $0 }).count, 3)
    }

    func testParallelPatternsAppearAsCatalogVariants() throws {
        guard case let .pokemon(card, _) = try ballPatternCard() else { return XCTFail("Expected Pokémon") }

        XCTAssertTrue(card.catalogVariants.contains(.pokeBall))
        XCTAssertTrue(card.catalogVariants.contains(.masterBall))
    }

    /// An unrecognised pattern is a real object this build cannot label. It must
    /// keep its own identity rather than answering to plain reverse, or a reverse
    /// holo would inherit a scarcer parallel's price.
    func testUnrecognisedFoilPatternDoesNotCollapseOntoReverse() throws {
        let json = """
        {
          "id": "sv08.5-002", "localId": "002", "name": "Vaporeon",
          "set": { "id": "sv08.5", "name": "Prismatic Evolutions",
                   "cardCount": { "total": 180, "official": 131 } },
          "variants": { "firstEdition": false, "holo": false, "normal": false, "reverse": true },
          "variants_detailed": [
            { "type": "reverse", "size": "standard", "variantId": "cm4kqul3x1bwlz1f",
              "pricing": { "tcgplayer": { "reverse-holofoil": { "marketPrice": 0.20 } } } },
            { "type": "reverse", "size": "standard", "foil": "confetti",
              "variantId": "zzz", "pricing": { "tcgplayer": { "holofoil": { "marketPrice": 88.0 } } } }
          ]
        }
        """
        let card = IdentifiedCard.pokemon(
            try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8)),
            setCode: "PRE"
        )

        guard case let .price(reverse) = CardPricing.price(for: card, variant: .reverse) else {
            return XCTFail("Expected a reverse price")
        }
        XCTAssertEqual(reverse.unitMarketPriceUSD, 0.20)

        guard case let .price(confetti) = CardPricing.price(
            for: card,
            variant: PhysicalVariant.pokemonFoilPattern("confetti")
        ) else {
            return XCTFail("Expected the unnamed pattern to keep its own price")
        }
        XCTAssertEqual(confetti.unitMarketPriceUSD, 88.0)
    }

    func testMultipleTCGdexStampsRemainOneExactPhysicalVariant() throws {
        let json = """
        {
          "id": "svp-999", "localId": "999", "name": "Test Promo",
          "set": { "id": "svp", "name": "Scarlet & Violet Promos",
                   "cardCount": { "total": 999, "official": 0 } },
          "variants": { "firstEdition": false, "holo": true, "normal": false, "reverse": false },
          "variants_detailed": [
            { "type": "holo", "size": "standard", "languages": ["en"],
              "pricing": { "tcgplayer": { "holofoil": { "marketPrice": 1.0 } } } },
            { "type": "holo", "size": "standard", "stamp": ["set-logo"],
              "languages": ["en"], "thirdParty": { "tcgplayer": 100 },
              "pricing": { "tcgplayer": { "holofoil": { "marketPrice": 2.0 } } } },
            { "type": "holo", "size": "standard", "stamp": ["staff", "set-logo"],
              "languages": ["en"], "thirdParty": { "tcgplayer": 101 },
              "pricing": { "tcgplayer": { "holofoil": { "marketPrice": 20.0 } } } }
          ]
        }
        """
        let pokemon = try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8))
        let options = pokemon.catalogVariants
        XCTAssertEqual(options.count, 3)
        XCTAssertTrue(options.contains(.holo))
        XCTAssertTrue(options.contains { $0.label == "Holo · Set Logo" })
        let staff = try XCTUnwrap(options.first { $0.label == "Holo · Set Logo + Staff" })
        XCTAssertEqual(PokemonCatalogStampVariant.decode(staff.id)?.stamps, ["set-logo", "staff"])
        XCTAssertEqual(pokemon.variantsDetailed?[2].thirdParty?.tcgplayer, 101)

        let card = IdentifiedCard.pokemon(pokemon, setCode: "SVP")
        guard case .needsChoice = VariantResolver.resolve(
            card.variantEvidence,
            finishLock: .holo
        ) else {
            return XCTFail("A finish lock must not silently answer the stamp question")
        }
        guard case let .price(price) = CardPricing.price(for: card, variant: staff) else {
            return XCTFail("Expected the Staff object's exact price")
        }
        XCTAssertEqual(price.unitMarketPriceUSD, 20.0)
        XCTAssertEqual(PhysicalVariant.named(staff.id), staff)
    }

    func testLoneStampedCatalogRecordDoesNotInventAChoice() throws {
        let json = """
        {
          "id": "mep-083", "localId": "083", "name": "Slowbro",
          "set": { "id": "mep", "name": "Mega Evolution Promos",
                   "cardCount": { "total": 89, "official": 0 } },
          "variants": { "firstEdition": false, "holo": true, "normal": false, "reverse": false },
          "variants_detailed": [
            { "type": "holo", "size": "standard", "stamp": ["set-logo"] }
          ]
        }
        """
        let card = try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8))
        XCTAssertEqual(card.catalogVariants, [.holo])
    }

    func testFirstEditionStampStaysInExistingPrintRunArchitecture() throws {
        let json = """
        {
          "id": "base1-4", "localId": "4", "name": "Charizard",
          "set": { "id": "base1", "name": "Base Set",
                   "cardCount": { "total": 102, "official": 102 } },
          "variants": { "firstEdition": true, "holo": true, "normal": false, "reverse": false },
          "variants_detailed": [
            { "type": "holo", "subtype": "unlimited", "size": "standard" },
            { "type": "holo", "subtype": "shadowless", "size": "standard",
              "stamp": ["1st-edition"] }
          ]
        }
        """
        let card = try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8))
        XCTAssertEqual(card.catalogVariants, [.holo, .firstEdition])
        XCTAssertFalse(card.catalogVariants.contains { $0.id.hasPrefix("pokemonStamp|") })
    }

    // MARK: - Cardmarket stands in only where TCGplayer is silent

    private func promoCard(tcgplayerJSON: String = "null") throws -> IdentifiedCard {
        let json = """
        {
          "id": "mep-008", "localId": "008", "name": "Golduck",
          "set": { "id": "mep", "name": "Mega Evolution Promos",
                   "cardCount": { "total": 60, "official": 60 } },
          "variants": { "firstEdition": false, "holo": true, "normal": false, "reverse": false },
          "pricing": {
            "tcgplayer": \(tcgplayerJSON),
            "cardmarket": { "updated": "2026-08-24T08:03:06.951Z", "unit": "EUR",
                            "avg": 0.53, "trend": 0.49, "avg7": 0.47, "avg30": 0.52 }
          }
        }
        """
        return .pokemon(try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8)), setCode: "MEP")
    }

    func testCardmarketFillsInWhereTCGplayerPublishesNothing() throws {
        guard case let .price(price) = CardPricing.price(for: try promoCard(), variant: .holo) else {
            return XCTFail("Expected a Cardmarket price")
        }

        XCTAssertEqual(price.unitMarketPriceUSD, 0.49)
        XCTAssertEqual(price.source, .cardmarket)
        XCTAssertNotNil(price.sourceUpdatedAt)
    }

    /// A euro figure is reported as euros. Labelling it USD would misstate a
    /// number by whatever the exchange rate happens to be that day.
    func testCardmarketPriceKeepsItsOwnCurrency() throws {
        guard case let .price(price) = CardPricing.price(for: try promoCard(), variant: .holo) else {
            return XCTFail("Expected a Cardmarket price")
        }

        XCTAssertEqual(price.currencyCode, "EUR")
        XCTAssertNotEqual(price.currencyCode, "USD")
    }

    func testTCGplayerStillWinsWhenItHasAPriceForTheVariant() throws {
        let card = try promoCard(tcgplayerJSON: #"{ "holofoil": { "marketPrice": 3.10 } }"#)

        guard case let .price(price) = CardPricing.price(for: card, variant: .holo) else {
            return XCTFail("Expected the TCGplayer price")
        }

        XCTAssertEqual(price.unitMarketPriceUSD, 3.10)
        XCTAssertEqual(price.source, .tcgplayer)
        XCTAssertEqual(price.currencyCode, "USD")
    }
}
