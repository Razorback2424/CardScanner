import XCTest
@testable import TradingCardScanner

/// Slice 1: the wire contract, pinned against fixtures.
///
/// These exist because the expensive mistakes in this layer are silent ones — a
/// batch item with two identifiers, a response correlated by position, a delta
/// omission read as "no price". None of those throw; they just produce wrong
/// numbers in someone's collection.
final class JustTCGContractTests: XCTestCase {
    func testMarketplaceArtworkUsesTheCanonicalProductCDN() {
        XCTAssertEqual(
            JustTCGV1Client.productImageURL(tcgplayerID: "515661")?.absoluteString,
            "https://tcgplayer-cdn.tcgplayer.com/product/515661_400w.jpg"
        )
        XCTAssertNil(JustTCGV1Client.productImageURL(tcgplayerID: "  "))
        XCTAssertEqual(
            JustTCGV1Client.migratedProductImageURL(
                from: "https://product-images.tcgplayer.com/fit-in/1000x1000/515661.jpg"
            )?.absoluteString,
            "https://tcgplayer-cdn.tcgplayer.com/product/515661_400w.jpg"
        )
    }


    // MARK: - Batch request encoding

    /// Each item carries exactly one identifier. The enum makes two impossible,
    /// but the *encoding* has to prove it too.
    func testEachBatchItemEncodesExactlyOneIdentifier() throws {
        let items: [JustTCGBatchLookup] = [
            .variantID("v-1"),
            .tcgplayerID("12345"),
            .scryfallID("abc-def")
        ]
        let data = try JSONEncoder().encode(
            JustTCGBatchRequest(items: items, includePriceHistory: false, updatedAfter: nil)
        )
        let decoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [[String: String]]
        )

        XCTAssertEqual(decoded.count, 3)
        for object in decoded {
            XCTAssertEqual(object.count, 1, "one identifier per item: \(object)")
        }
        // The *request* key is `variantId`, even though the *response* field
        // carrying the same value is `uuid`. The asymmetry is the vendor's, and
        // conflating the two is what made the first contract run send nothing.
        XCTAssertEqual(decoded[0], ["variantId": "v-1"])
        XCTAssertEqual(decoded[1], ["tcgplayerId": "12345"])
        XCTAssertEqual(decoded[2], ["scryfallId": "abc-def"])
    }

    /// The vendor's documented precedence, fastest first.
    func testIdentifierPrecedenceFollowsTheVendorOrder() {
        let ordered: [JustTCGBatchLookup] = [
            .variantID("a"), .tcgplayerSKUID("b"), .tcgplayerID("c"),
            .mtgjsonID("d"), .scryfallID("e"), .cardID("f")
        ]
        XCTAssertEqual(ordered.map(\.precedence), [0, 1, 2, 3, 4, 5])

        // Given a choice, the variant id always wins: it is the only identifier
        // at the same granularity the app prices at.
        let best = JustTCGBatchLookup.best(from: [
            .cardID("f"), .scryfallID("e"), .variantID("a")
        ])
        XCTAssertEqual(best, .variantID("a"))
    }

    /// Routine collection pricing must never ask for history — it is an order of
    /// magnitude more data for a number the collection does not show.
    func testRoutineRefreshNeverRequestsHistory() {
        let request = JustTCGBatchRequest(
            items: [.variantID("v-1")],
            includePriceHistory: false,
            updatedAfter: nil
        )
        let query = Dictionary(uniqueKeysWithValues: request.queryItems)

        XCTAssertEqual(query["include_price_history"], "false")
        XCTAssertNil(query["updated_after"])
    }

    func testDeltaCutoffIsSentAsUnixSeconds() {
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        let request = JustTCGBatchRequest(
            items: [.variantID("v-1")],
            includePriceHistory: false,
            updatedAfter: cutoff
        )
        let query = Dictionary(uniqueKeysWithValues: request.queryItems)

        XCTAssertEqual(query["updated_after"], "1700000000")
    }

    /// Pinned from a live response.
    ///
    /// The request *parameter* is called `variantId`; the response *field* is
    /// called `uuid`. Decoding the parameter name finds nothing, which is
    /// exactly what happened on the first contract run — every batch would have
    /// had nothing to send.
    func testVariantIdentifierComesFromUUIDNotVariantId() throws {
        let json = """
        { "data": [ { "id": "card-slug", "uuid": "card-uuid", "variants": [
            { "id": "variant-slug", "uuid": "variant-uuid",
              "condition": "Near Mint", "printing": "Holofoil", "price": 106.39,
              "tcgplayerSkuId": "1247795" } ] } ] }
        """
        let response = try JSONDecoder().decode(
            JustTCGBatchResponse.self, from: Data(json.utf8)
        )
        let variant = try XCTUnwrap(response.data.first?.variants?.first)

        XCTAssertEqual(variant.uuid, "variant-uuid")
        XCTAssertEqual(variant.variantId, "variant-uuid", "the UUID is what batches send")
        XCTAssertEqual(variant.tcgplayerSkuId, "1247795")
        XCTAssertNotNil(response.variantsByID["variant-uuid"])
    }

    /// Sealed products carry the literal string `N/A` as their number. Treating
    /// that as a collector number would make every sealed product compare equal.
    func testSealedProductNumberNAIsNotACollectorNumber() throws {
        let json = """
        { "data": [ { "id": "box", "uuid": "box-uuid", "number": "N/A",
            "set_name": "Legendary Treasures", "variants": [] } ] }
        """
        let card = try XCTUnwrap(
            JSONDecoder().decode(JustTCGBatchResponse.self, from: Data(json.utf8)).data.first
        )

        XCTAssertNil(card.printedNumber)
        XCTAssertEqual(card.setName, "Legendary Treasures")
    }

    // MARK: - Response correlation

    private let batchFixture = """
    { "data": [
      { "id": "card-1", "name": "Trevenant", "set": "trick-or-trade-2023",
        "number": "017/196",
        "variants": [
          { "uuid": "v-nm-holo", "condition": "Near Mint",
            "printing": "Holofoil", "price": 0.16, "lastUpdated": 1700000000 },
          { "uuid": "v-hp-holo", "condition": "Heavily Played",
            "printing": "Holofoil", "price": 0.35 }
        ] },
      { "id": "card-2", "name": "Legendary Treasures Booster Box",
        "set": "legendary-treasures",
        "variants": [
          { "uuid": "v-sealed", "condition": "Sealed", "price": 184.99 }
        ] }
    ] }
    """

    /// Correlation is by identifier, never by array position — the vendor is not
    /// obliged to preserve request order, and matching by index would attach one
    /// card's price to another.
    func testVariantsAreCorrelatedByIDNotPosition() throws {
        let response = try JSONDecoder().decode(
            JustTCGBatchResponse.self, from: Data(batchFixture.utf8)
        )
        let byID = response.variantsByID

        XCTAssertEqual(byID["v-nm-holo"]?.variant.price, 0.16)
        XCTAssertEqual(byID["v-hp-holo"]?.variant.price, 0.35)
        XCTAssertEqual(byID["v-nm-holo"]?.card.name, "Trevenant")
        XCTAssertNil(byID["not-requested"])
    }

    /// Sealed products live in the same `/cards` dataset, distinguished by the
    /// condition. That is what lets one batch path price a booster box and a
    /// single with the same code.
    func testSealedProductsAreIdentifiedByCondition() throws {
        let response = try JSONDecoder().decode(
            JustTCGBatchResponse.self, from: Data(batchFixture.utf8)
        )
        let sealed = try XCTUnwrap(response.variantsByID["v-sealed"])

        XCTAssertTrue(sealed.variant.isSealed)
        XCTAssertEqual(sealed.variant.price, 184.99)
        XCTAssertFalse(try XCTUnwrap(response.variantsByID["v-nm-holo"]).variant.isSealed)
    }

    /// A null price is a real answer — "no reliable market price" — and must not
    /// decode as zero, which would read as a free card.
    func testNullPriceDecodesAsAbsentNotZero() throws {
        let json = """
        { "data": [ { "id": "c", "variants": [
            { "uuid": "v", "condition": "Near Mint", "price": null } ] } ] }
        """
        let response = try JSONDecoder().decode(
            JustTCGBatchResponse.self, from: Data(json.utf8)
        )

        XCTAssertNil(response.variantsByID["v"]?.variant.price)
    }

    // MARK: - Graded shape (v2 beta)

    func testGradedVariantsDecodeGraderGradeAndQualifier() throws {
        let json = """
        { "data": [ { "id": "card-1", "variants": [
          { "uuid": "g-psa10", "price": 500.0,
            "grading": { "company": "PSA", "grade": 10 } },
          { "uuid": "g-psa10oc", "price": 300.0,
            "grading": { "company": "PSA", "grade": 10, "qualifier": "OC" } },
          { "uuid": "g-bgs10bl", "price": 2500.0,
            "grading": { "company": "BGS", "grade": 10, "label": "Black Label" } },
          { "uuid": "g-auth", "price": 40.0,
            "grading": { "company": "CGC", "grade": null, "label": "Authentic" } }
        ] } ] }
        """
        let response = try JSONDecoder().decode(
            JustTCGBatchResponse.self, from: Data(json.utf8)
        )
        let byID = response.variantsByID

        let psa10 = try XCTUnwrap(byID["g-psa10"]?.variant.grading)
        XCTAssertEqual(psa10.gradingCompany, .psa)
        XCTAssertEqual(psa10.gradeText, "10", "a 10 must not render as 10.0")
        XCTAssertEqual(psa10.cardGrade.display(company: .psa), "PSA 10")

        // A qualifier makes a different object, not a footnote on the same one.
        let oc = try XCTUnwrap(byID["g-psa10oc"]?.variant.grading)
        XCTAssertEqual(oc.cardGrade.display(company: .psa), "PSA 10 OC")
        XCTAssertNotEqual(oc.cardGrade.identityFragment, psa10.cardGrade.identityFragment)

        let blackLabel = try XCTUnwrap(byID["g-bgs10bl"]?.variant.grading)
        XCTAssertEqual(blackLabel.cardGrade.display(company: .bgs), "BGS 10 Black Label")

        // Authentic has no number, and the vendor models that rather than
        // inventing one.
        let authentic = try XCTUnwrap(byID["g-auth"]?.variant.grading)
        XCTAssertNil(authentic.gradeText)
        XCTAssertEqual(authentic.cardGrade.display(company: .cgc), "CGC Authentic")
    }

    func testHalfGradesSurvive() throws {
        let json = """
        { "data": [ { "id": "c", "variants": [ { "uuid": "v",
            "grading": { "company": "BGS", "grade": 9.5 } } ] } ] }
        """
        let response = try JSONDecoder().decode(
            JustTCGBatchResponse.self, from: Data(json.utf8)
        )

        XCTAssertEqual(response.variantsByID["v"]?.variant.grading?.gradeText, "9.5")
    }

    // MARK: - Quota arithmetic

    /// The whole justification for the refactor: twenty variants, one request.
    func testTwentyVariantsCostOneRequest() {
        XCTAssertEqual(JustTCGQuota.requestsNeeded(forVariants: 20), 1)
        XCTAssertEqual(JustTCGQuota.requestsNeeded(forVariants: 1), 1)
        XCTAssertEqual(JustTCGQuota.requestsNeeded(forVariants: 21), 2)
        XCTAssertEqual(JustTCGQuota.requestsNeeded(forVariants: 100), 5)
        XCTAssertEqual(JustTCGQuota.requestsNeeded(forVariants: 500), 25)
        XCTAssertEqual(JustTCGQuota.requestsNeeded(forVariants: 2_000), 100)
        XCTAssertEqual(JustTCGQuota.requestsNeeded(forVariants: 0), 0)
    }

    func testChunkingNeverExceedsThePlanBatchSize() {
        let lookups = (0..<47).map { JustTCGBatchLookup.variantID("v-\($0)") }
        let chunks = lookups.chunked(into: JustTCGQuota.batchSize)

        XCTAssertEqual(chunks.count, 3)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= JustTCGQuota.batchSize })
        XCTAssertEqual(chunks.flatMap { $0 }.count, 47, "nothing may be dropped")
    }

    // MARK: - Deduplication

    /// Eight owned copies of one printing are one lookup. Quantities never
    /// multiply requests.
    func testDuplicateCopiesCollapseToOneLookup() {
        let targets = (0..<8).map { index in
            MarketPriceTarget(
                priceKey: "key-\(index)",
                game: .pokemon,
                printingID: "sv08.5-001",
                variantID: "normal",
                itemKind: .rawCard,
                marketVariantID: "shared-variant",
                lookupCandidates: [],
                currentAmount: nil,
                lastCheckedAt: nil
            )
        }

        let (batched, unresolved) = JustTCGRefreshCoordinator.deduplicate(targets)

        XCTAssertEqual(batched.count, 1, "one variant, one lookup")
        XCTAssertEqual(batched[.variantID("shared-variant")]?.count, 8)
        XCTAssertTrue(unresolved.isEmpty)
    }

    /// A target with no usable identifier is reported, not silently dropped:
    /// "never asked" and "vendor has nothing" are different diagnoses.
    func testTargetsWithoutAnIdentifierAreReportedNotDropped() {
        let resolvable = MarketPriceTarget(
            priceKey: "a", game: .magic, printingID: "p", variantID: nil,
            itemKind: .rawCard, marketVariantID: nil,
            lookupCandidates: [.scryfallID("s-1")],
            currentAmount: nil, lastCheckedAt: nil
        )
        let unresolvable = MarketPriceTarget(
            priceKey: "b", game: .magic, printingID: "q", variantID: nil,
            itemKind: .rawCard, marketVariantID: nil,
            lookupCandidates: [],
            currentAmount: nil, lastCheckedAt: nil
        )

        let (batched, unresolved) = JustTCGRefreshCoordinator.deduplicate([resolvable, unresolvable])

        XCTAssertEqual(batched.count, 1)
        XCTAssertEqual(unresolved.map(\.priceKey), ["b"])
    }

    func testUnmappedExplicitFinishDoesNotBorrowAnUnqualifiedListing() throws {
        let json = """
        { "data": [ { "uuid": "card-1", "variants": [
          { "uuid": "variant-1", "condition": "Near Mint", "printing": "Normal", "price": 1.0 }
        ] } ] }
        """
        let response = try JSONDecoder().decode(
            JustTCGBatchResponse.self,
            from: Data(json.utf8)
        )
        let target = MarketPriceTarget(
            priceKey: "key",
            game: .pokemon,
            printingID: "sv01-001",
            variantID: PhysicalVariant.masterBall.id,
            itemKind: .rawCard,
            marketVariantID: nil,
            lookupCandidates: [.cardID("card-1")],
            currentAmount: nil,
            lastCheckedAt: nil
        )

        guard case .noExactListing = JustTCGRefreshCoordinator.exactListing(
            lookup: .cardID("card-1"),
            owners: [target],
            response: response
        ) else {
            return XCTFail("an unmapped explicit finish must not inherit Normal")
        }
    }

    func testTreatmentQualifiedVendorListingIsNotAcceptedAsExact() throws {
        let json = """
        { "data": [ { "uuid": "card-1", "variants": [
          { "uuid": "variant-1", "condition": "Near Mint", "printing": "Foil", "price": 8.0 }
        ] } ] }
        """
        let response = try JSONDecoder().decode(
            JustTCGBatchResponse.self,
            from: Data(json.utf8)
        )
        func target(treatmentIDs: [String]) -> MarketPriceTarget {
            MarketPriceTarget(
                priceKey: "key",
                game: .magic,
                printingID: "printing",
                variantID: PhysicalVariant.foil.id,
                itemKind: .rawCard,
                marketVariantID: nil,
                lookupCandidates: [.cardID("card-1")],
                currentAmount: nil,
                lastCheckedAt: nil,
                magicTreatmentIDsRaw: treatmentIDs
            )
        }

        guard case .noExactListing = JustTCGRefreshCoordinator.exactListing(
            lookup: .cardID("card-1"),
            owners: [target(treatmentIDs: ["surgefoil"])],
            response: response
        ) else {
            return XCTFail("a generic Foil listing must not answer Surge Foil")
        }

        guard case .matched = JustTCGRefreshCoordinator.exactListing(
            lookup: .cardID("card-1"),
            owners: [target(treatmentIDs: [])],
            response: response
        ) else {
            return XCTFail("the same ordinary Foil listing should remain usable")
        }
    }

    // MARK: - Which identifier the vendor can actually resolve

    /// Verified live, one batch, two identifiers:
    ///
    ///     scryfallId  -> returned nothing
    ///     tcgplayerId -> returned the card
    ///
    /// The Scryfall id is a documented request parameter, but the vendor does
    /// not hold the mapping. Sending it produced an empty result, and because an
    /// absent variant is deliberately left alone rather than cleared, the whole
    /// failure was silent.
    func testScryfallIDIsNotAResolvableIdentifierForThisVendor() {
        // Still encodable — the parameter exists and other catalogues use it —
        // but nothing in the app may choose it for a batch.
        let lookup = JustTCGBatchLookup.scryfallID("9b74f022-3e1d-481d-b822-cd86060a9901")
        XCTAssertEqual(lookup.wireKey, "scryfallId")

        // The marketplace id outranks it, so a card carrying both never sends
        // the one that cannot be resolved.
        XCTAssertEqual(
            JustTCGBatchLookup.best(from: [lookup, .tcgplayerID("696977")]),
            .tcgplayerID("696977")
        )
    }

    /// Scryfall publishes `tcgplayer_id` only for ordinary printings. Art cards
    /// and tokens — the entire fall-through population — come back null, so they
    /// have no keyed route and must resolve by search exactly once.
    func testArtCardsAndTokensCarryNoMarketplaceIdentifier() throws {
        let ordinary = """
        { "id": "x", "name": "Cloud, Midgar Mercenary", "set": "fin",
          "set_name": "Final Fantasy", "collector_number": "10", "lang": "en",
          "digital": false, "layout": "normal", "tcgplayer_id": 630870 }
        """
        let artCard = """
        { "id": "y", "name": "Forest // Forest", "set": "amsh",
          "set_name": "MSH Art Series", "collector_number": "17", "lang": "en",
          "digital": false, "layout": "art_series" }
        """

        let decoder = JSONDecoder()
        XCTAssertEqual(
            try decoder.decode(ScryfallCard.self, from: Data(ordinary.utf8)).tcgplayerID,
            630870
        )
        XCTAssertNil(
            try decoder.decode(ScryfallCard.self, from: Data(artCard.utf8)).tcgplayerID,
            "an art card has no marketplace id to batch by"
        )
    }

    // MARK: - Freshness

    func testMissingPriceIsAlwaysEligibleRegardlessOfProviderClock() {
        XCTAssertTrue(
            MarketFreshness.needsRefresh(
                amount: nil,
                checkedAt: .now,
                providerUpdatedAt: Date.distantPast
            )
        )
    }

    func testFreshPriceIsNotRefetched() {
        XCTAssertFalse(
            MarketFreshness.needsRefresh(
                amount: 1.23,
                checkedAt: Date.now.addingTimeInterval(-60 * 60),
                providerUpdatedAt: nil
            )
        )
    }

    /// Past six hours, the provider's own clock decides: if the game has not
    /// been repriced since the last check, another request buys the same number.
    func testStalePriceDefersToTheProviderClock() {
        let checkedAt = Date.now.addingTimeInterval(-7 * 60 * 60)

        XCTAssertFalse(
            MarketFreshness.needsRefresh(
                amount: 1.23,
                checkedAt: checkedAt,
                providerUpdatedAt: checkedAt.addingTimeInterval(-60)
            ),
            "provider has not repriced since the last check"
        )
        XCTAssertTrue(
            MarketFreshness.needsRefresh(
                amount: 1.23,
                checkedAt: checkedAt,
                providerUpdatedAt: checkedAt.addingTimeInterval(60)
            )
        )
    }

    // MARK: - Sync safety

    /// `updated_after` is only safe once a complete pass has succeeded. Before
    /// that, a variant absent from a delta is indistinguishable from one that
    /// was never fetched.
    func testDeltaSyncIsRefusedUntilAFullPassSucceeds() throws {
        let suite = "JustTCGContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = JustTCGSyncLedger(defaults: defaults)

        XCTAssertNil(ledger.deltaCutoff(game: .pokemon, apiVersion: "v1"))

        ledger.recordCompleteSync(game: .pokemon, apiVersion: "v1")
        XCTAssertNotNil(ledger.deltaCutoff(game: .pokemon, apiVersion: "v1"))
        // Versions are tracked separately: a v1 pass says nothing about v2.
        XCTAssertNil(ledger.deltaCutoff(game: .pokemon, apiVersion: "v2"))
        XCTAssertNil(ledger.deltaCutoff(game: .magic, apiVersion: "v1"))
    }

    // MARK: - Quota lanes

    /// Background work stops at 75 so the last 15 remain for whatever the user
    /// asks for directly.
    func testBackgroundStopsShortSoInteractiveWorkStillFits() throws {
        let suite = "JustTCGContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = JustTCGRequestLedger(defaults: defaults)
        for _ in 0..<JustTCGQuota.backgroundDailyCeiling {
            XCTAssertEqual(ledger.reserve(lane: .background), .allowed)
        }
        guard case .dailyReached = ledger.reserve(lane: .background) else {
            return XCTFail("background must stop at its ceiling")
        }
        // The reserve is still spendable by the user.
        XCTAssertEqual(ledger.reserve(lane: .interactive), .allowed)
    }

    func testMonthlyCeilingBlocksBothLanes() throws {
        let suite = "JustTCGContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(JustTCGQuota.monthlyHardLimit, forKey: "justTCGRequestsUsedThisMonth")
        // UTC, matching the ledger. Seeding with the local calendar makes the
        // ledger see a different month, roll over, and zero the counter — which
        // is the ledger behaving correctly and the test lying.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        defaults.set(
            calendar.dateInterval(of: .month, for: .now)?.start,
            forKey: "justTCGBudgetMonth"
        )
        let ledger = JustTCGRequestLedger(defaults: defaults)

        guard case .monthlyReached = ledger.reserve(lane: .interactive) else {
            return XCTFail("the monthly ceiling must stop even interactive work")
        }
    }

    /// Being told to wait is not a request the user got value from, so it must
    /// not consume an allowance.
    func testRateLimitBlocksWithoutSpendingAllowance() throws {
        let suite = "JustTCGContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = JustTCGRequestLedger(defaults: defaults)
        let retryAt = Date.now.addingTimeInterval(600)
        ledger.recordRateLimit(until: retryAt)

        XCTAssertEqual(ledger.reserve(lane: .interactive), .rateLimited(retryAt: retryAt))
        XCTAssertEqual(ledger.snapshot().usedToday, 0)
    }

    /// One allowance, not two.
    ///
    /// A refresh spends from both paths: batched pricing goes through the
    /// transport, identity resolution through `ProductFallbackBudget`. When
    /// those kept separate counters they each allowed 90 a day against a real
    /// limit of 100, and the overspend arrived as 429s rather than as an honest
    /// "budget reached".
    func testBothRefreshPathsSpendFromTheSameAllowance() async throws {
        let suite = "JustTCGContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let ledger = JustTCGRequestLedger(defaults: defaults)
        let identityBudget = ProductFallbackBudget(defaults: defaults)
        // Spend the whole day through the batched path.
        for _ in 0..<JustTCGQuota.dailyHardLimit {
            XCTAssertEqual(ledger.reserve(lane: .interactive), .allowed)
        }

        // The identity path must now find nothing left, not a fresh 90.
        let reservation = await identityBudget.reserveRequest()
        guard case .budgetReached = reservation else {
            return XCTFail("identity resolution must share the batched path's allowance")
        }
    }

    /// The app's counter starts at zero on a fresh install while the account may
    /// already have spent most of the day. The vendor reports the truth on every
    /// response, so the local number defers to it.
    func testLocalCountCorrectsItselfAgainstTheServer() throws {
        let suite = "JustTCGContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = JustTCGRequestLedger(defaults: defaults)
        XCTAssertEqual(ledger.snapshot().usedToday, 0, "a fresh install knows nothing")

        // Shaped exactly like the live `_metadata` block.
        ledger.syncFromServer(
            JustTCGQuotaMetadata(
                apiPlan: "Free Tier",
                apiDailyLimit: 100,
                apiDailyRequestsUsed: 70,
                apiDailyRequestsRemaining: 30,
                apiRequestLimit: 1_000,
                apiRequestsUsed: 70,
                apiRequestsRemaining: 930
            )
        )

        XCTAssertEqual(ledger.snapshot().usedToday, 70)
        XCTAssertEqual(ledger.snapshot().remainingToday, JustTCGQuota.dailyHardLimit - 70)
    }

    /// Never revise the count *down* to the server's: if the app believes it has
    /// spent more than the server has recorded yet, trusting the lower number
    /// would overshoot the real limit.
    func testServerSyncNeverLowersTheLocalCount() throws {
        let suite = "JustTCGContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = JustTCGRequestLedger(defaults: defaults)
        for _ in 0..<50 { _ = ledger.reserve(lane: .interactive) }

        ledger.syncFromServer(
            JustTCGQuotaMetadata(
                apiPlan: "Free Tier", apiDailyLimit: 100,
                apiDailyRequestsUsed: 10, apiDailyRequestsRemaining: 90,
                apiRequestLimit: 1_000, apiRequestsUsed: 10, apiRequestsRemaining: 990
            )
        )

        XCTAssertEqual(ledger.snapshot().usedToday, 50, "must not revise downward")
    }

    /// When the allowance is gone the user is told when it comes back, and that
    /// moment must be in the future rather than a stale timestamp.
    func testBudgetExhaustionReportsAFutureResetTime() throws {
        let suite = "JustTCGContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = JustTCGRequestLedger(defaults: defaults)
        for _ in 0..<JustTCGQuota.dailyHardLimit { _ = ledger.reserve(lane: .interactive) }

        guard case let .dailyReached(resetAt) = ledger.reserve(lane: .interactive) else {
            return XCTFail("expected the daily ceiling to stop this")
        }
        XCTAssertGreaterThan(resetAt, .now)
        XCTAssertLessThanOrEqual(resetAt.timeIntervalSinceNow, 24 * 60 * 60 + 1)
        XCTAssertEqual(ledger.snapshot().remainingToday, 0)
    }

    func testRetryAfterAcceptsSecondsAndHTTPDate() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertEqual(
            JustTCGTransport.retryDate(from: "120", now: now),
            now.addingTimeInterval(120)
        )
        XCTAssertNotNil(
            JustTCGTransport.retryDate(from: "Wed, 21 Oct 2015 07:28:00 GMT", now: now)
        )
        XCTAssertNil(JustTCGTransport.retryDate(from: nil, now: now))
    }

    // MARK: - Namespaced identity

    /// A slab never shares a row, a quantity or a price with the raw copy of the
    /// same printing.
    func testGradedAndSealedKeysCannotCollideWithRawKeys() {
        let raw = PriceRecord.key(game: .pokemon, printingID: "sv08.5-001", variantID: "holo")
        let graded = CollectedCard.gradedCollectionKey(
            game: .pokemon, underlyingPrintingID: "sv08.5-001", variantUUID: "g-1"
        )
        let sealed = CollectedCard.sealedCollectionKey(
            game: .pokemon, productUUID: "p-1", variantUUID: "v-1"
        )

        XCTAssertNotEqual(raw, graded)
        XCTAssertNotEqual(raw, sealed)
        XCTAssertTrue(graded.hasPrefix("graded:"))
        XCTAssertTrue(sealed.hasPrefix("sealed:"))
    }

    /// Two slabs with certificates are two objects even at the same grade.
    func testCertifiedSlabsDoNotMerge() {
        let first = CollectedCard.gradedCollectionKey(
            game: .pokemon, underlyingPrintingID: "p", variantUUID: "g",
            certificationNumber: "12345678"
        )
        let second = CollectedCard.gradedCollectionKey(
            game: .pokemon, underlyingPrintingID: "p", variantUUID: "g",
            certificationNumber: "87654321"
        )
        let uncertified = CollectedCard.gradedCollectionKey(
            game: .pokemon, underlyingPrintingID: "p", variantUUID: "g",
            certificationNumber: nil
        )

        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first, uncertified)
    }

    func testSealedProductsNeverCountTowardSetCompletion() {
        XCTAssertFalse(CollectionItemKind.sealedProduct.countsTowardSetCompletion)
        XCTAssertTrue(CollectionItemKind.rawCard.countsTowardSetCompletion)
        XCTAssertTrue(CollectionItemKind.gradedCard.countsTowardSetCompletion)
    }

    // MARK: - Identifier spellings

    /// The regression that made every fallback refresh re-pay for a search.
    ///
    /// `ProductVariant` is what the identity-resolution pass decodes, and it was
    /// asking for `variantId` — the request parameter's name, which the response
    /// does not use. It therefore never captured a variant handle, nothing was
    /// ever persisted as batchable, and the "search once, batch forever after"
    /// design never engaged.
    func testProductVariantReadsTheVariantHandleFromUUID() throws {
        let json = """
        { "uuid": "variant-uuid", "id": "variant-slug", "condition": "Near Mint",
          "printing": "Holofoil", "price": 12.5, "lastUpdated": 1700000000 }
        """
        let variant = try JSONDecoder().decode(ProductVariant.self, from: Data(json.utf8))

        XCTAssertEqual(variant.variantId, "variant-uuid", "the uuid is the handle batches send")
        XCTAssertEqual(variant.updatedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    /// The slug still identifies the variant when no uuid is published, which is
    /// better than storing nothing and searching again next time.
    func testProductVariantFallsBackToTheSlug() throws {
        let json = """
        { "id": "variant-slug", "condition": "Near Mint", "price": 1 }
        """
        let variant = try JSONDecoder().decode(ProductVariant.self, from: Data(json.utf8))

        XCTAssertEqual(variant.variantId, "variant-slug")
    }

    /// `cardId=<slug>` is verified against the live API to return the card, so
    /// the slug remains the handle. The uuid is decoded alongside it.
    func testProductCardHandlePrefersTheVerifiedSlug() throws {
        let json = """
        { "id": "card-slug", "uuid": "card-uuid", "name": "Trevenant",
          "set": "trick-or-trade-2023", "number": "017/196", "variants": [] }
        """
        let card = try JSONDecoder().decode(ProductCard.self, from: Data(json.utf8))

        XCTAssertEqual(card.vendorID, "card-slug")
        XCTAssertEqual(card.uuid, "card-uuid")
    }

    /// The card object mixes conventions — `set_name` is snake_case while the
    /// nested variant's `tcgplayerSkuId` is camelCase, both pinned from live
    /// responses. Nothing pins the marketplace ids, and a wrong guess is silent:
    /// sealed products simply show a placeholder instead of artwork.
    func testMarketplaceIdentifiersDecodeUnderEitherSpelling() throws {
        let camel = """
        { "data": [ { "id": "box", "uuid": "box-uuid", "tcgplayerId": "610553",
            "set_name": "Legendary Treasures", "variants": [] } ] }
        """
        let snake = """
        { "data": [ { "id": "box", "uuid": "box-uuid", "tcgplayer_id": 610553,
            "setName": "Legendary Treasures", "variants": [] } ] }
        """

        for payload in [camel, snake] {
            let card = try XCTUnwrap(
                JSONDecoder().decode(JustTCGBatchResponse.self, from: Data(payload.utf8)).data.first
            )
            XCTAssertEqual(card.tcgplayerId, "610553")
            XCTAssertEqual(card.setName, "Legendary Treasures")
        }
    }

    // MARK: - v2 graded beta

    /// Pinned from a live v2 response. v2 is a different schema from v1, not a
    /// newer version of it: the price moves into `markets`, and the grade label
    /// is `grade_label`. Decoding v2 with v1's field names left every graded
    /// variant with no price at all.
    func testV2GradedVariantPriceComesFromTheMarketsBlock() throws {
        let json = """
        { "id": "v2-variant", "type": "graded", "condition": null,
          "printing": "Holofoil", "language": "English",
          "grading": { "company": "PSA", "grade": 10, "grade_label": "GEM MT",
                       "qualifier": null, "canonical": "PSA 10" },
          "markets": [ { "region": "US", "currency": "USD", "price": 3999.99,
                         "updated_at": 1784585831 } ] }
        """
        let variant = try JSONDecoder().decode(JustTCGVariant.self, from: Data(json.utf8))

        XCTAssertNil(variant.price, "v2 publishes no flat price")
        XCTAssertEqual(variant.marketPriceUSD, 3999.99)
        XCTAssertEqual(variant.updatedAt, Date(timeIntervalSince1970: 1_784_585_831))
        XCTAssertEqual(variant.variantId, "v2-variant")
        XCTAssertEqual(variant.grading?.label, "GEM MT")
        XCTAssertEqual(variant.grading?.gradeText, "10")
    }

    /// v1's flat price keeps working; the two schemas share one type.
    func testV1FlatPriceStillReads() throws {
        let json = """
        { "uuid": "v1-variant", "condition": "Near Mint", "printing": "Holofoil",
          "price": 106.39, "lastUpdated": 1700000000 }
        """
        let variant = try JSONDecoder().decode(JustTCGVariant.self, from: Data(json.utf8))

        XCTAssertEqual(variant.marketPriceUSD, 106.39)
        XCTAssertEqual(variant.updatedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testForeignCurrencyIsNotExposedAsUSD() throws {
        let json = """
        { "uuid": "eur-variant", "price": 106.39, "currency": "EUR",
          "lastUpdated": 1700000000 }
        """
        let variant = try JSONDecoder().decode(JustTCGVariant.self, from: Data(json.utf8))

        XCTAssertEqual(variant.marketPrice?.currency, "EUR")
        XCTAssertNil(variant.marketPriceUSD)
        XCTAssertNil(variant.updatedAt)
    }

    func testMarketPriceChoosesTheExplicitUSDMarket() throws {
        let json = """
        { "uuid": "mixed-variant", "markets": [
          { "currency": "EUR", "price": 90.00, "updated_at": 1700000000 },
          { "currency": "USD", "price": 100.00, "updated_at": 1700000100 }
        ] }
        """
        let variant = try JSONDecoder().decode(JustTCGVariant.self, from: Data(json.utf8))

        XCTAssertEqual(variant.marketPriceUSD, 100.00)
        XCTAssertEqual(variant.updatedAt, Date(timeIntervalSince1970: 1_700_000_100))
    }

    /// v2 does not reject an identifier it does not recognise — it silently
    /// browses instead, returning arbitrary graded cards for the game. The app
    /// sends a catalog id, which v2 has never heard of, so the picker was
    /// offering slabs of unrelated cards.
    func testGradedIdentityRejectsACardTheBrowseHandedBack() throws {
        let json = """
        { "id": "other", "name": "Charizard Star (Delta Species)",
          "number": "100/101", "set_name": "EX Dragon Frontiers", "variants": [] }
        """
        let returned = try JSONDecoder().decode(JustTCGCard.self, from: Data(json.utf8))
        let asked = GradedCardIdentity(
            name: "Charizard", setName: "Base Set", collectorNumber: "4/102"
        )

        XCTAssertFalse(asked.matches(returned, game: .pokemon))
    }

    func testGradedIdentityAcceptsTheCardItAskedFor() throws {
        let json = """
        { "id": "right", "name": "Charizard", "number": "4/102",
          "set_name": "Base Set", "variants": [] }
        """
        let returned = try JSONDecoder().decode(JustTCGCard.self, from: Data(json.utf8))
        let asked = GradedCardIdentity(
            name: "Charizard", setName: "Base Set", collectorNumber: "004/102"
        )

        XCTAssertTrue(asked.matches(returned, game: .pokemon))
    }

    func testGradedIdentityUsesTheRequestedGameSetNormalization() throws {
        let json = """
        { "id": "right", "name": "The One Ring",
          "set_name": "The Lord of the Rings Commander", "variants": [] }
        """
        let returned = try JSONDecoder().decode(JustTCGCard.self, from: Data(json.utf8))
        let asked = GradedCardIdentity(
            name: "The One Ring", setName: "Commander: The Lord of the Rings", collectorNumber: ""
        )

        XCTAssertTrue(asked.matches(returned, game: .magic))
        XCTAssertFalse(asked.matches(returned, game: .pokemon))
    }

    /// One request must serve every owned grade of one card, or a shelf of PSA
    /// 8/9/10 copies costs three requests where it should cost one.
    func testEveryGradeOfOneCardSharesARequest() {
        let psa9 = GradedCardIdentity(
            name: "Charizard", setName: "Base Set", collectorNumber: "004/102"
        )
        let psa10 = GradedCardIdentity(
            name: "Charizard", setName: "Base Set", collectorNumber: "004/102"
        )
        let other = GradedCardIdentity(
            name: "Blastoise", setName: "Base Set", collectorNumber: "002/102"
        )

        XCTAssertEqual(psa9.groupingKey(game: .pokemon), psa10.groupingKey(game: .pokemon))
        XCTAssertNotEqual(psa9.groupingKey(game: .pokemon), other.groupingKey(game: .pokemon))
    }

    /// Pinned from the live v2 response for Base Set Charizard, which is the
    /// shape a graded refresh has to read: variant id under `id`, price nested
    /// in `markets`, grade under `grading.canonical`.
    func testGradedCardResponseYieldsPricedVariants() throws {
        let json = """
        { "data": [ { "id": "004d6ac4-92db-51b7-9cd6-8c2d46479bdc", "name": "Charizard",
            "number": "004/102", "set_name": "Base Set", "variants": [
              { "id": "b9174ffe-9b95-5aea-b916-2b3bcd6d5731", "type": "graded",
                "printing": "Holofoil",
                "grading": { "company": "PSA", "grade": 8, "canonical": "PSA 8" },
                "markets": [ { "region": "US", "currency": "USD", "price": 1479.99,
                               "updated_at": 1784585831 } ] } ] } ] }
        """
        let response = try JSONDecoder().decode(JustTCGBatchResponse.self, from: Data(json.utf8))
        let card = try XCTUnwrap(response.data.first)
        let variant = try XCTUnwrap(card.variants?.first)
        let asked = GradedCardIdentity(
            name: "Charizard", setName: "Base Set", collectorNumber: "4/102"
        )

        XCTAssertTrue(asked.matches(card, game: .pokemon))
        XCTAssertEqual(variant.variantId, "b9174ffe-9b95-5aea-b916-2b3bcd6d5731")
        XCTAssertEqual(variant.marketPriceUSD, 1479.99)
        XCTAssertEqual(variant.grading?.gradingCompany, .psa)
        XCTAssertEqual(variant.grading?.gradeText, "8")
    }

    // MARK: - Shared transport pacing

    /// A request that is abandoned while queued for the shared pacer must not
    /// consume quota. This exercises the transport boundary, rather than only
    /// the pacer's cancellation behavior, so a future reorder of `perform` is
    /// caught by the test.
    func testCancellationWhilePacingDoesNotReserveQuota() async throws {
        let suite = "JustTCGContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let ledger = JustTCGRequestLedger(defaults: defaults)
        let pacer = JustTCGPacer()
        try await pacer.wait(lane: .background, minimumInterval: 0)

        var configuration = JustTCGTransport.Configuration()
        configuration.baseURL = URL(string: "http://127.0.0.1:1")!
        configuration.minimumRequestInterval = 1
        let transport = JustTCGTransport(
            configuration: configuration,
            session: URLSession(configuration: .ephemeral),
            ledger: ledger,
            pacer: pacer,
            apiKeyOverride: "justtcg-test-key"
        )

        let request = Task {
            try await transport.get(
                "/test",
                lane: .background,
                as: EmptyJustTCGResponse.self
            )
        }
        try await Task.sleep(for: .milliseconds(20))
        request.cancel()

        do {
            _ = try await request.value
            XCTFail("a cancelled paced request must not succeed")
        } catch is CancellationError {
            // Expected: the request was cancelled while waiting for its slot.
        }

        let snapshot = await transport.snapshot()
        XCTAssertEqual(snapshot.usedToday, 0)
        XCTAssertEqual(snapshot.usedThisMonth, 0)
    }

    /// Interactive work is selected ahead of an already queued background
    /// waiter, so a long refresh cannot make a user-triggered lookup wait for
    /// the entire refresh queue.
    func testInteractivePacingPreemptsQueuedBackgroundWork() async throws {
        let pacer = JustTCGPacer()
        try await pacer.wait(lane: .background, minimumInterval: 0)

        let background = Task {
            try await pacer.wait(lane: .background, minimumInterval: 0.2)
            return Date.now
        }
        await Task.yield()
        try await Task.sleep(for: .milliseconds(20))

        let interactive = Task {
            try await pacer.wait(lane: .interactive, minimumInterval: 0.2)
            return Date.now
        }

        let interactiveGrantedAt = try await interactive.value
        let backgroundGrantedAt = try await background.value
        XCTAssertLessThan(
            interactiveGrantedAt,
            backgroundGrantedAt,
            "interactive work must not sit behind queued background work"
        )
    }

    /// Pacing must not change the transport's existing budget error mapping.
    func testBudgetReachedStillSurfacesAfterPacing() async throws {
        let suite = "JustTCGContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let ledger = JustTCGRequestLedger(defaults: defaults)
        for _ in 0..<JustTCGQuota.backgroundDailyCeiling {
            XCTAssertEqual(ledger.reserve(lane: .background), .allowed)
        }

        var configuration = JustTCGTransport.Configuration()
        configuration.baseURL = URL(string: "http://127.0.0.1:1")!
        configuration.minimumRequestInterval = 0
        let transport = JustTCGTransport(
            configuration: configuration,
            session: URLSession(configuration: .ephemeral),
            ledger: ledger,
            pacer: JustTCGPacer(),
            apiKeyOverride: "justtcg-test-key"
        )

        do {
            _ = try await transport.get(
                "/test",
                lane: .background,
                as: EmptyJustTCGResponse.self
            )
            XCTFail("an exhausted background budget must reject the request")
        } catch JustTCGTransport.TransportError.budgetReached {
            // Expected.
        }

        XCTAssertEqual(ledger.snapshot().usedToday, JustTCGQuota.backgroundDailyCeiling)
    }

    private struct EmptyJustTCGResponse: Decodable {}

    // MARK: - Delta safety

    /// Records every outbound request so a test can assert on `updated_after`.
    private final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var requestedURLs: [URL] = []
        nonisolated(unsafe) static var body = Data(#"{"data":[]}"#.utf8)
        private static let lock = NSLock()

        static func reset(body newBody: String = #"{"data":[]}"#) {
            lock.lock(); defer { lock.unlock() }
            requestedURLs = []
            body = Data(newBody.utf8)
        }

        static func recorded() -> [URL] {
            lock.lock(); defer { lock.unlock() }
            return requestedURLs
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            if let url = request.url {
                Self.lock.lock()
                Self.requestedURLs.append(url)
                Self.lock.unlock()
            }
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.invalid")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            Self.lock.lock()
            let payload = Self.body
            Self.lock.unlock()
            client?.urlProtocol(self, didLoad: payload)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    @MainActor
    private func makeCoordinator(
        defaults: UserDefaults
    ) -> (JustTCGRefreshCoordinator, JustTCGSyncLedger) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]

        var transportConfiguration = JustTCGTransport.Configuration()
        transportConfiguration.baseURL = URL(string: "https://justtcg.test")!
        transportConfiguration.minimumRequestInterval = 0

        let transport = JustTCGTransport(
            configuration: transportConfiguration,
            session: URLSession(configuration: configuration),
            ledger: JustTCGRequestLedger(defaults: defaults),
            pacer: JustTCGPacer(),
            apiKeyOverride: "justtcg-test-key"
        )
        let syncLedger = JustTCGSyncLedger(defaults: defaults)
        return (
            JustTCGRefreshCoordinator(
                client: JustTCGV1Client(transport: transport),
                syncLedger: syncLedger
            ),
            syncLedger
        )
    }

    private func target(
        key: String,
        variant: String,
        requiresFullResponse: Bool,
        itemKind: CollectionItemKind = .rawCard
    ) -> MarketPriceTarget {
        MarketPriceTarget(
            priceKey: key,
            game: .pokemon,
            printingID: "sv08.5-001",
            variantID: "normal",
            itemKind: itemKind,
            marketVariantID: variant,
            lookupCandidates: [],
            currentAmount: nil,
            lastCheckedAt: nil,
            requiresFullResponse: requiresFullResponse
        )
    }

    /// The delta clock is per game, but it is advanced by whatever narrow pass
    /// happened to succeed. A row that has never had a complete answer must
    /// therefore still be asked with a full request, or "absent" and "never
    /// fetched" become the same response — the exact ambiguity `updated_after`
    /// is documented as unsafe under.
    @MainActor
    func testChunkCarryingAnUnansweredRowAsksForAFullResponse() async throws {
        let suite = "JustTCGDelta.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingURLProtocol.reset()

        let (coordinator, syncLedger) = makeCoordinator(defaults: defaults)
        syncLedger.recordCompleteSync(game: .pokemon, apiVersion: JustTCGV1Client.apiVersion)
        XCTAssertNotNil(
            syncLedger.deltaCutoff(game: .pokemon, apiVersion: JustTCGV1Client.apiVersion),
            "precondition: the clock is set, so delta is available"
        )

        _ = await coordinator.refresh(
            [
                target(key: "priced", variant: "variant-priced", requiresFullResponse: false),
                target(key: "never-answered", variant: "variant-new", requiresFullResponse: true)
            ],
            game: .pokemon,
            useDelta: true,
            apply: { _, _, _ in true },
            checkpoint: { true }
        )

        let urls = RecordingURLProtocol.recorded()
        XCTAssertEqual(urls.count, 1, "both lookups fit one chunk")
        XCTAssertFalse(
            urls[0].query?.contains("updated_after") ?? false,
            "one row with nothing to compare against makes the whole chunk ask in full"
        )
    }

    /// The delta is still used where it is safe, so the gate above cannot be
    /// satisfied by simply never sending one.
    @MainActor
    func testChunkOfAlreadyAnsweredRowsStillUsesTheDelta() async throws {
        let suite = "JustTCGDelta.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingURLProtocol.reset()

        let (coordinator, syncLedger) = makeCoordinator(defaults: defaults)
        syncLedger.recordCompleteSync(game: .pokemon, apiVersion: JustTCGV1Client.apiVersion)

        _ = await coordinator.refresh(
            [target(key: "priced", variant: "variant-priced", requiresFullResponse: false)],
            game: .pokemon,
            useDelta: true,
            apply: { _, _, _ in true },
            checkpoint: { true }
        )

        let urls = RecordingURLProtocol.recorded()
        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(
            urls[0].query?.contains("updated_after") ?? false,
            "a row that already holds a value can be asked for changes only"
        )
    }

    /// A full response that carries no listing for the requested variant is a
    /// real answer and must be reported. Without it a sealed row waiting on
    /// artwork never learns the vendor has none, stays permanently stale, and
    /// spends one request on every refresh for the life of the collection.
    @MainActor
    func testFullResponseMissIsReportedSoArtworkCanBecomeTerminal() async throws {
        let suite = "JustTCGDelta.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingURLProtocol.reset()

        let (coordinator, _) = makeCoordinator(defaults: defaults)
        var missed: [MarketPriceTarget] = []

        _ = await coordinator.refresh(
            [
                target(
                    key: "sealed",
                    variant: "variant-sealed",
                    requiresFullResponse: true,
                    itemKind: .sealedProduct
                )
            ],
            game: .pokemon,
            useDelta: false,
            apply: { _, _, _ in true },
            unmatched: { missed.append(contentsOf: $0) },
            checkpoint: { true }
        )

        XCTAssertEqual(missed.map(\.priceKey), ["sealed"])
    }

    /// The mirror image: absence from a *delta* response means "unchanged", not
    /// "the vendor has nothing", and must never be reported as an answer.
    @MainActor
    func testDeltaResponseMissIsNotReported() async throws {
        let suite = "JustTCGDelta.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingURLProtocol.reset()

        let (coordinator, syncLedger) = makeCoordinator(defaults: defaults)
        syncLedger.recordCompleteSync(game: .pokemon, apiVersion: JustTCGV1Client.apiVersion)
        var missed: [MarketPriceTarget] = []

        _ = await coordinator.refresh(
            [
                target(
                    key: "sealed",
                    variant: "variant-sealed",
                    requiresFullResponse: false,
                    itemKind: .sealedProduct
                )
            ],
            game: .pokemon,
            useDelta: true,
            apply: { _, _, _ in true },
            unmatched: { missed.append(contentsOf: $0) },
            checkpoint: { true }
        )

        XCTAssertTrue(missed.isEmpty, "unchanged is not an answer about artwork")
    }

    @MainActor
    func testFailedCheckpointIsReportedAndDoesNotAdvanceDelta() async throws {
        let suite = "JustTCGDelta.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingURLProtocol.reset()

        let (coordinator, syncLedger) = makeCoordinator(defaults: defaults)
        let report = await coordinator.refresh(
            [target(key: "priced", variant: "variant-priced", requiresFullResponse: false)],
            game: .pokemon,
            apply: { _, _, _ in true },
            checkpoint: { false }
        )

        XCTAssertTrue(report.persistenceFailed)
        XCTAssertFalse(report.completedFully)
        XCTAssertNil(
            syncLedger.deltaCutoff(game: .pokemon, apiVersion: JustTCGV1Client.apiVersion),
            "a failed save must leave the delta checkpoint eligible for retry"
        )
    }
}
