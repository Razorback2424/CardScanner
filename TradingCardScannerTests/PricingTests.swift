import XCTest
@testable import TradingCardScanner

final class PricingTests: XCTestCase {
    func testEligibleUnitPriceIsTheSingleUSDGate() {
        XCTAssertEqual(
            PortfolioPriceEligibility.eligibleUnitPrice(amount: 12.3456, currencyCode: "USD"),
            Money(rounding: 12.3456)
        )
        XCTAssertNil(
            PortfolioPriceEligibility.eligibleUnitPrice(amount: 12.3456, currencyCode: "EUR")
        )
        XCTAssertNil(PortfolioPriceEligibility.eligibleUnitPrice(amount: nil, currencyCode: "USD"))
        XCTAssertNil(PortfolioPriceEligibility.eligibleUnitPrice(amount: .nan, currencyCode: "USD"))
    }

    func testLegacyCardmarketObservationRemainsVisibleInItsNativeCurrency() {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let record = PriceRecord(
            key: "pokemon:promo-078:cosmos",
            game: .pokemon,
            printingID: "promo-078",
            variantID: "cosmos"
        )
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 1.43,
                currencyCode: "EUR",
                source: .cardmarket,
                sourceVariantID: "cardmarket",
                sourceUpdatedAt: fetchedAt,
                fetchedAt: fetchedAt
            )
        )

        record.applyUnavailable(source: .tcgplayer, at: fetchedAt.addingTimeInterval(60))

        XCTAssertEqual(record.unitMarketPriceUSD, 1.43)
        XCTAssertEqual(record.currencyCode, "EUR")
        XCTAssertEqual(record.source, .cardmarket)
        XCTAssertNil(record.effectiveUnitMarketPriceUSD)
        XCTAssertEqual(record.display.amount, 1.43)
        XCTAssertEqual(record.display.currencyCode, "EUR")
        XCTAssertEqual(record.display.source, .cardmarket)
        XCTAssertEqual(record.display.state(now: fetchedAt.addingTimeInterval(60)), .current)
    }

    @MainActor
    func testSharedPriceSnapshotKeepsLegacyEURVisibleWithoutUsingItForUSDValuation() {
        let record = PriceRecord(
            key: "pokemon:promo-078:cosmos",
            game: .pokemon,
            printingID: "promo-078",
            variantID: "cosmos"
        )
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 1.43,
                currencyCode: "EUR",
                source: .cardmarket,
                sourceVariantID: "cardmarket",
                sourceUpdatedAt: nil,
                fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
        record.recordFailure(at: Date(timeIntervalSince1970: 1_800_000_060))

        let snapshot = PriceSnapshotStore()
        snapshot.apply([PriceDelta(key: record.key, display: record.display)])
        let displayed = snapshot.display(for: record.key)

        XCTAssertEqual(record.unitMarketPriceUSD, 1.43)
        XCTAssertEqual(record.currencyCode, "EUR")
        XCTAssertEqual(record.source, .cardmarket)
        XCTAssertNil(record.effectiveUnitMarketPriceUSD)
        XCTAssertEqual(displayed?.currencyCode, "EUR")
        XCTAssertEqual(displayed?.amount, 1.43)
        XCTAssertEqual(displayed?.source, .cardmarket)
        XCTAssertEqual(displayed?.state(), .current)
    }

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

    private func magicCard(promoType: String? = nil) throws -> IdentifiedCard {
        let promoTypes = promoType.map { ", \"promo_types\": [\"\($0)\"]" } ?? ""
        let json = """
        {
          "id": "3f0a1f52-0000-4000-8000-000000000001",
          "name": "Llanowar Elves",
          "set": "ecl", "set_name": "Eclipse", "collector_number": "218",
          "lang": "en", "digital": false, "frame": "2015"\(promoTypes),
          "released_at": "2026-02-06",
          "finishes": ["nonfoil", "foil"],
          "prices": { "usd": "1.25", "usd_foil": "6.40", "usd_etched": null }
        }
        """
        return .magic(try JSONDecoder().decode(ScryfallCard.self, from: Data(json.utf8)))
    }

    // MARK: - A price belongs to printing *and* variant

    func testReverseHoloReadsTheReverseHoloListing() throws {
        guard case let .price(price) = CardPricing.price(
            for: try pokemonCard(),
            variant: .reverse,
            magicTreatments: []
        ) else {
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

        XCTAssertEqual(
            CardPricing.price(for: card, variant: .masterBall, magicTreatments: []),
            .unavailable(.tcgplayer)
        )
        XCTAssertEqual(
            CardPricing.price(for: card, variant: .pokeBall, magicTreatments: []),
            .unavailable(.tcgplayer)
        )
        XCTAssertNil(CardPricing.tcgplayerListing(for: .masterBall))
    }

    func testUnknownFinishGetsNoPrice() throws {
        XCTAssertEqual(
            CardPricing.price(for: try pokemonCard(), variant: nil, magicTreatments: []),
            .unavailable(.tcgplayer)
        )
    }

    func testCardWithNoPricingAtAllIsUnavailable() throws {
        let card = try pokemonCard(pricingJSON: nil)

        XCTAssertEqual(
            CardPricing.price(for: card, variant: .reverse, magicTreatments: []),
            .unavailable(nil)
        )
        // Every catalog finish is still listed — as a stated gap. A card whose
        // finishes silently vanish reads as a card that has no finishes.
        XCTAssertFalse(card.marketPrices.isEmpty)
        XCTAssertTrue(card.marketPrices.allSatisfy(\.isGap))
        XCTAssertTrue(card.marketPrices.allSatisfy { $0.value == nil })
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

        XCTAssertEqual(card.marketPrices.compactMap(\.value), [0.42, 3.75])
        // The holo listing exists at the marketplace but not in this printing,
        // so it produces no row at all — priced or otherwise.
        XCTAssertEqual(card.marketPrices.count, 2)
    }

    // MARK: - Magic

    func testMagicFinishesMapOntoScryfallPriceKeys() throws {
        let card = try magicCard()

        guard case let .price(foil) = CardPricing.price(
            for: card,
            variant: .foil,
            magicTreatments: []
        ) else {
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
        XCTAssertEqual(
            CardPricing.price(for: try magicCard(), variant: .etched, magicTreatments: []),
            .unavailable(.scryfall)
        )

    }

    func testCatalogSortResolutionRequiresPricingSourceEvidenceForNegative() throws {
        let pokemonWithoutPricing = try pokemonCard(pricingJSON: nil)
        let unqueried = CardPricing.price(
            for: pokemonWithoutPricing,
            variant: .normal,
            magicTreatments: []
        )
        XCTAssertEqual(unqueried, .unavailable(nil))
        XCTAssertEqual(
            CatalogSortPriceResolution.exactLookup(unqueried),
            .unresolved
        )

        let checkedGap = CardPricing.price(
            for: try magicCard(),
            variant: .etched,
            magicTreatments: []
        )
        XCTAssertEqual(checkedGap, .unavailable(.scryfall))
        XCTAssertEqual(
            CatalogSortPriceResolution.exactLookup(checkedGap),
            .noUSDQuote
        )

        let priced = CardPricing.price(
            for: try pokemonCard(),
            variant: .reverse,
            magicTreatments: []
        )
        XCTAssertEqual(
            CatalogSortPriceResolution.exactLookup(priced),
            .priced(3.75)
        )
    }

    func testCachedNilPriceDoesNotResolveSlot() {
        XCTAssertNil(CatalogSortPriceResolution.cachedPrice(nil))
        XCTAssertEqual(
            CatalogSortPriceResolution.cachedPrice(2.5),
            .priced(2.5)
        )
    }

    func testAggregateSortResolutionUsesKnownPriceAndKeepsUnknownsRetryable() throws {
        XCTAssertEqual(
            CatalogSortPriceResolution.aggregate([
                .unavailable(.tcgplayer),
                .unavailable(nil)
            ]),
            .unresolved
        )
        XCTAssertEqual(
            CatalogSortPriceResolution.aggregate([
                .unavailable(.tcgplayer),
                .unavailable(.scryfall)
            ]),
            .noUSDQuote
        )
        XCTAssertEqual(
            CatalogSortPriceResolution.aggregate([
                .unavailable(nil),
                CardPricing.price(
                    for: try pokemonCard(),
                    variant: .normal,
                    magicTreatments: []
                )
            ]),
            .priced(0.42)
        )
    }

    func testMagicTreatmentUsesTheExactPrintingFoilPrice() throws {
        let card = try magicCard(promoType: "surgefoil")
        let foilTreatments = card.magicTreatments(for: .foil)
        let nonfoilTreatments = card.magicTreatments(for: .nonfoil)

        XCTAssertEqual(foilTreatments, [.surgeFoil])
        XCTAssertTrue(nonfoilTreatments.isEmpty)
        guard case let .price(foil) = CardPricing.price(
            for: card,
            variant: .foil,
            magicTreatments: foilTreatments
        ) else {
            return XCTFail("The exact treated printing should retain usd_foil")
        }
        XCTAssertEqual(foil.unitMarketPriceUSD, 6.40)
        XCTAssertEqual(foil.sourceVariantID, "usd_foil")
        guard case let .price(nonfoil) = CardPricing.price(
            for: card,
            variant: .nonfoil,
            magicTreatments: nonfoilTreatments
        ) else {
            return XCTFail("The nonfoil copy has no treatment and should retain usd")
        }
        XCTAssertEqual(nonfoil.unitMarketPriceUSD, 1.25)
        XCTAssertEqual(nonfoil.sourceVariantID, "usd")
    }

    func testUnclassifiedMagicTreatmentUsesTheExactPrintingPrice() throws {
        guard case let .price(price) = CardPricing.price(
            for: try magicCard(),
            variant: .foil,
            magicTreatments: [.unclassified("future-treatment")]
        ) else {
            return XCTFail("An exact printing price should not depend on the treatment enum")
        }
        XCTAssertEqual(price.unitMarketPriceUSD, 6.40)
    }

    func testPreviouslyStoredMagicTreatmentPriceRemainsEffectiveEvidence() {
        let record = PriceRecord(
            key: PriceRecord.key(
                game: .magic,
                printingID: "printing",
                variantID: PhysicalVariant.foil.id,
                treatmentIDs: ["surgefoil"]
            ),
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id,
            magicTreatmentIDs: ["surgefoil"]
        )
        record.apply(
            NormalizedPrice(
                unitMarketPriceUSD: 6.40,
                currencyCode: "USD",
                source: .scryfall,
                sourceVariantID: "usd_foil",
                sourceUpdatedAt: nil,
                fetchedAt: .now
            )
        )

        // This is the regression guard: a price already stored under the
        // treatment-qualified key remains visible after the quarantine is lifted.
        XCTAssertEqual(record.unitMarketPriceUSD, 6.40)
        XCTAssertEqual(record.effectiveUnitMarketPriceUSD, 6.40)
        XCTAssertEqual(record.display.amount, 6.40)
    }

    func testPreviouslyStoredMagicTreatmentObservationCanValuePortfolio() throws {
        // Model the row exactly as an older build could have left it: the
        // treatment marker is in the canonical key, while the mirrored model
        // column is still empty and the observation contains Scryfall's generic
        // usd_foil amount.
        let key = PriceRecord.key(
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id,
            treatmentIDs: ["surgefoil"]
        )
        let record = PriceRecord(
            key: key,
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id
        )
        record.unitMarketPriceUSD = 6.40
        record.sourceRaw = PriceSource.scryfall.rawValue
        record.sourceVariantID = "usd_foil"
        record.fetchedAt = Date(timeIntervalSince1970: 100)

        let observedAmount = try XCTUnwrap(Money(rounding: 6.40))
        let observation = PriceObservation(
            instrumentKey: key,
            kind: .marketUpdate,
            amount: observedAmount,
            source: .scryfall,
            sourceVariantID: "usd_foil",
            marketVariantID: nil,
            effectiveAt: Date(timeIntervalSince1970: 100),
            receivedAt: Date(timeIntervalSince1970: 100),
            isSourceStamped: false
        )

        XCTAssertEqual(PortfolioEngine.observationEntry(from: observation).amount, observedAmount)
        XCTAssertEqual(
            InventoryLedger.resolveValuation(
                observation: observation,
                record: record
            ).unitPrice,
            observedAmount
        )
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

    func testFailedFirstPriceCheckRemainsUnknown() {
        let failedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let record = PriceRecord(
            key: "pokemon:sv08.5-074:reverse",
            game: .pokemon,
            printingID: "sv08.5-074",
            variantID: "reverse"
        )
        record.recordFailure(at: failedAt)

        XCTAssertEqual(record.display.state(now: failedAt), .unknown)
        XCTAssertTrue(record.display.refreshFailed)
    }

    func testNonJustTCGObservationsCannotMoveJustTCGDeltaEvidence() {
        let justTCGAt = Date(timeIntervalSince1970: 1_700_000_000)
        let record = PriceRecord(
            key: "pokemon:sv08.5-074:reverse",
            game: .pokemon,
            printingID: "sv08.5-074",
            variantID: "reverse"
        )
        XCTAssertTrue(record.apply(NormalizedPrice(
            unitMarketPriceUSD: 5,
            currencyCode: "USD",
            source: .justTCG,
            sourceVariantID: "justtcg-reverse",
            sourceUpdatedAt: justTCGAt,
            fetchedAt: justTCGAt
        )))
        record.justTCGFetchedAt = justTCGAt

        record.applyUnavailable(source: .tcgdex, at: justTCGAt.addingTimeInterval(3_600))
        XCTAssertEqual(record.justTCGFetchedAt, justTCGAt)

        XCTAssertTrue(record.apply(NormalizedPrice(
            unitMarketPriceUSD: 6,
            currencyCode: "USD",
            source: .justTCG,
            sourceVariantID: "browse-cached-variant",
            sourceUpdatedAt: justTCGAt,
            fetchedAt: justTCGAt.addingTimeInterval(7_200)
        )))
        XCTAssertNil(record.justTCGFetchedAt, "Browse quotes are not live refresh evidence")
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
        guard case let .price(price) = CardPricing.price(
            for: try pokemonCard(),
            variant: .normal,
            magicTreatments: []
        ) else {
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

        guard case let .price(pokeBall) = CardPricing.price(
                  for: card,
                  variant: .pokeBall,
                  magicTreatments: []
              ),
              case let .price(masterBall) = CardPricing.price(
                  for: card,
                  variant: .masterBall,
                  magicTreatments: []
              ) else {
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
            guard case let .price(price) = CardPricing.price(
                for: card,
                variant: variant,
                magicTreatments: []
            ) else { return nil }
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

        guard case let .price(reverse) = CardPricing.price(
            for: card,
            variant: .reverse,
            magicTreatments: []
        ) else {
            return XCTFail("Expected a reverse price")
        }
        XCTAssertEqual(reverse.unitMarketPriceUSD, 0.20)

        guard case let .price(confetti) = CardPricing.price(
            for: card,
            variant: PhysicalVariant.pokemonFoilPattern("confetti"),
            magicTreatments: []
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
        guard case let .price(price) = CardPricing.price(
            for: card,
            variant: staff,
            magicTreatments: []
        ) else {
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

    // MARK: - Cardmarket remains separate from canonical USD pricing

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

    /// Cardmarket publishes a euro figure for the promo catalogue where
    /// TCGplayer publishes nothing. That number is not a weaker dollar price,
    /// it is a different marketplace in a different currency, and this app has
    /// no exchange-rate policy that could turn one into the other. So it is not
    /// consulted at all: the honest answer is that this finish has no USD quote.
    func testCardmarketIsNeverUsedAsAPriceWhenTCGplayerIsSilent() throws {
        XCTAssertEqual(
            CardPricing.price(for: try promoCard(), variant: .holo, magicTreatments: []),
            .unavailable(.tcgplayer)
        )
    }

    /// The regression this rule exists for: a euro amount rendered beside
    /// dollar amounts in the same panel, inviting a comparison neither figure
    /// supports.
    func testNoPublishedPriceRowEverCarriesAForeignCurrencyAmount() throws {
        let published = try promoCard().marketPrices

        XCTAssertFalse(published.isEmpty)
        XCTAssertTrue(published.allSatisfy(\.isGap))
        for row in published {
            XCTAssertEqual(row.availability, .noUSDQuote(.tcgplayer))
        }
    }

    /// A gap is recorded where someone can act on it rather than only absent
    /// from the screen.
    func testAnUnpricedFinishIsRecordedAsACoverageGap() throws {
        PriceCoverageGapLog.shared.reset()
        defer { PriceCoverageGapLog.shared.reset() }

        _ = try promoCard().marketPrices

        let gaps = PriceCoverageGapLog.shared.currentGaps()
        XCTAssertFalse(gaps.isEmpty)
        XCTAssertTrue(gaps.allSatisfy { $0.consultedSource == .tcgplayer })
        XCTAssertTrue(gaps.allSatisfy { $0.setCode == "MEP" })
    }

    func testTCGplayerStillWinsWhenItHasAPriceForTheVariant() throws {
        let card = try promoCard(tcgplayerJSON: #"{ "holofoil": { "marketPrice": 3.10 } }"#)

        guard case let .price(price) = CardPricing.price(
            for: card,
            variant: .holo,
            magicTreatments: []
        ) else {
            return XCTFail("Expected the TCGplayer price")
        }

        XCTAssertEqual(price.unitMarketPriceUSD, 3.10)
        XCTAssertEqual(price.source, .tcgplayer)
        XCTAssertEqual(price.currencyCode, "USD")
    }

    func testDetailedCosmosVariantUsesItsTCGplayerUSDPrice() throws {
        let json = #"""
        {
          "id": "mep-078", "localId": "078", "name": "Toxel",
          "set": { "id": "mep", "name": "Mega Evolution Promos",
                   "cardCount": { "total": 80, "official": 80 } },
          "variants": { "firstEdition": false, "holo": true, "normal": false, "reverse": false },
          "variants_detailed": [
            { "type": "reverse", "foil": "cosmos",
              "pricing": { "tcgplayer": {
                "updated": "2026-09-20T12:00:00.000Z",
                "holofoil": { "marketPrice": 2.34 }
              } }
            }
          ]
        }
        """#
        let card = IdentifiedCard.pokemon(
            try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8)),
            setCode: "MEP"
        )

        guard case let .price(price) = CardPricing.price(
            for: card,
            variant: .pokemonFoilPattern("cosmos"),
            magicTreatments: []
        ) else {
            return XCTFail("Expected the detailed Cosmos TCGplayer price")
        }

        XCTAssertEqual(price.unitMarketPriceUSD, 2.34)
        XCTAssertEqual(price.currencyCode, "USD")
        XCTAssertEqual(price.source, .tcgplayer)
    }
}

final class PriceHistoryChartModelTests: XCTestCase {
    private let instrumentKey = "pokemon:test-set-001:normal"
    private let timeZone = TimeZone(secondsFromGMT: 0)!

    private var calendar: Calendar {
        PortfolioCalendar.calendar(in: timeZone)
    }

    private func date(day: Int, hour: Int = 1) -> Date {
        let secondsPerDay: TimeInterval = 24 * 60 * 60
        let offset = TimeInterval(day) * secondsPerDay + TimeInterval(hour) * 60 * 60
        let base = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        return base.addingTimeInterval(offset)
    }

    private func observation(
        day: Int,
        amount: Double,
        kind: PriceObservationKind = .marketUpdate
    ) throws -> PriceObservation {
        PriceObservation(
            instrumentKey: instrumentKey,
            kind: kind,
            amount: try XCTUnwrap(Money(rounding: amount)),
            source: .tcgplayer,
            sourceVariantID: "normal",
            marketVariantID: "normal",
            effectiveAt: date(day: day),
            receivedAt: date(day: day),
            isSourceStamped: true
        )
    }

    private func checkDay(day: Int) -> PriceCheckDay {
        PriceCheckDay(
            instrumentKey: instrumentKey,
            portfolioDay: calendar.startOfDay(for: date(day: day)),
            lastSuccessfulCheckAt: date(day: day, hour: 2),
            source: .tcgplayer
        )
    }

    private func makeModel(
        observations: [PriceObservation],
        checks: [PriceCheckDay],
        nowDay: Int = 5,
        range: PortfolioHistoryRange = .all
    ) -> PriceHistoryChartModel {
        PriceHistoryChartModel.make(
            observations: observations,
            checkDays: checks,
            currencyCode: "USD",
            range: range,
            now: date(day: nowDay, hour: 12),
            timeZone: timeZone
        )
    }

    func testNoObservationShowsRecordingState() {
        let model = makeModel(observations: [], checks: [])

        XCTAssertTrue(model.samples.isEmpty)
        XCTAssertEqual(model.segments.count, 0)
    }

    func testOneObservationRemainsAPointWithoutALine() throws {
        let model = makeModel(
            observations: [try observation(day: 0, amount: 10)],
            checks: [checkDay(day: 0), checkDay(day: 1)]
        )

        XCTAssertEqual(model.observationCount, 1)
        XCTAssertFalse(model.segments.contains { $0.samples.count > 1 })
        XCTAssertEqual(model.segments.count, 1)
    }

    func testCheckedDaysConnectChangedPricesWithAFlatStep() throws {
        let model = makeModel(
            observations: [
                try observation(day: 0, amount: 10),
                try observation(day: 2, amount: 12)
            ],
            checks: [checkDay(day: 0), checkDay(day: 1), checkDay(day: 2)]
        )

        XCTAssertEqual(model.observationCount, 2)
        XCTAssertEqual(model.segments.count, 1)
        XCTAssertGreaterThanOrEqual(model.segments[0].samples.count, 3)
        XCTAssertFalse(model.hasGaps)
    }

    func testUncheckedDaysCreateAVisibleGap() throws {
        let model = makeModel(
            observations: [
                try observation(day: 0, amount: 10),
                try observation(day: 3, amount: 12)
            ],
            checks: [checkDay(day: 0), checkDay(day: 3)]
        )

        XCTAssertEqual(model.observationCount, 2)
        XCTAssertEqual(model.segments.count, 2)
        XCTAssertTrue(model.hasGaps)
        XCTAssertTrue(model.segments.allSatisfy { $0.samples.count == 1 })
    }

    func testClusteredObservationsUseTheirSpanForThePlotDomain() throws {
        let model = makeModel(
            observations: [
                try observation(day: 28, amount: 10),
                try observation(day: 29, amount: 12)
            ],
            checks: [checkDay(day: 28), checkDay(day: 29)],
            nowDay: 30,
            range: .oneMonth
        )

        let requestedSpan = model.rangeEnd.timeIntervalSince(model.rangeStart)
        let plotSpan = model.plotRangeEnd.timeIntervalSince(model.plotRangeStart)
        XCTAssertLessThan(plotSpan, requestedSpan * 0.5)
        XCTAssertTrue(model.isPlotRangeFitted)
        XCTAssertLessThanOrEqual(model.plotRangeStart, model.samples.first?.date ?? .distantFuture)
        XCTAssertGreaterThanOrEqual(model.plotRangeEnd, model.samples.last?.date ?? .distantPast)
        XCTAssertEqual(
            PriceHistoryChartModel.recommendedXAxisTickCount(
                for: plotSpan,
                isAccessibilitySize: false
            ),
            2
        )
        XCTAssertEqual(
            PriceHistoryChartModel.recommendedXAxisTickCount(
                for: plotSpan,
                isAccessibilitySize: true
            ),
            2
        )
        XCTAssertTrue(PriceHistoryChartModel.usesShortXAxisLabels(for: 36 * 60 * 60))
        XCTAssertFalse(PriceHistoryChartModel.usesShortXAxisLabels(for: 2 * 24 * 60 * 60))
    }

    func testSourceRestatementIsAnnotatedAsNonMarket() throws {
        let model = makeModel(
            observations: [
                try observation(day: 0, amount: 10),
                try observation(day: 1, amount: 9, kind: .sourceRestatement)
            ],
            checks: [checkDay(day: 0), checkDay(day: 1)]
        )

        XCTAssertEqual(model.samples.last?.annotationLabel, "Source restatement")
    }

    func testNearFlatExpensiveHistoryUsesMinimumVisualEnvelope() throws {
        let model = makeModel(
            observations: [
                try observation(day: 0, amount: 603.51),
                try observation(day: 1, amount: 603.00)
            ],
            checks: [checkDay(day: 0), checkDay(day: 1)]
        )

        let domain = model.yDomain
        XCTAssertGreaterThanOrEqual(domain.upperBound - domain.lowerBound, 603.00 * 0.02)
        XCTAssertLessThanOrEqual(domain.lowerBound, 603.00)
        XCTAssertGreaterThanOrEqual(domain.upperBound, 603.51)
    }

    func testMeaningfulDeclineStillDeterminesTheChartScale() throws {
        let model = makeModel(
            observations: [
                try observation(day: 0, amount: 100),
                try observation(day: 1, amount: 20)
            ],
            checks: [checkDay(day: 0), checkDay(day: 1)]
        )

        let domain = model.yDomain
        XCTAssertGreaterThan(domain.upperBound - domain.lowerBound, 80)
        XCTAssertLessThanOrEqual(domain.lowerBound, 20)
        XCTAssertGreaterThanOrEqual(domain.upperBound, 100)
    }

    func testFlatHistoryHasASensibleNonzeroDomain() throws {
        let model = makeModel(
            observations: [
                try observation(day: 0, amount: 42),
                try observation(day: 1, amount: 42)
            ],
            checks: [checkDay(day: 0), checkDay(day: 1)]
        )

        let domain = model.yDomain
        XCTAssertGreaterThan(domain.upperBound, domain.lowerBound)
        XCTAssertLessThanOrEqual(domain.lowerBound, 42)
        XCTAssertGreaterThanOrEqual(domain.upperBound, 42)
    }

    func testLowPricesNeverProduceANegativeDomain() throws {
        let model = makeModel(
            observations: [
                try observation(day: 0, amount: 0.01),
                try observation(day: 1, amount: 0.02)
            ],
            checks: [checkDay(day: 0), checkDay(day: 1)]
        )

        let domain = model.yDomain
        XCTAssertGreaterThanOrEqual(domain.lowerBound, 0)
        XCTAssertGreaterThan(domain.upperBound, domain.lowerBound)
        XCTAssertGreaterThanOrEqual(domain.upperBound, 0.02)
    }
}
