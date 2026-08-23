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

    func testAutomaticRefreshSkipsPricesCheckedRecently() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let targets = [
            PriceTarget(game: .pokemon, printingID: "a", setCode: "PRE", variantID: "reverse",
                        lastCheckedAt: now.addingTimeInterval(-60)),
            PriceTarget(game: .pokemon, printingID: "b", setCode: "PRE", variantID: "reverse",
                        lastCheckedAt: now.addingTimeInterval(-12 * 60 * 60)),
            PriceTarget(game: .pokemon, printingID: "c", setCode: "PRE", variantID: "normal",
                        lastCheckedAt: nil)
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
}
