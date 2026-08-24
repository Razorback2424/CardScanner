import XCTest
@testable import TradingCardScanner

/// Slice 1: the wire contract, pinned against fixtures.
///
/// These exist because the expensive mistakes in this layer are silent ones — a
/// batch item with two identifiers, a response correlated by position, a delta
/// omission read as "no price". None of those throw; they just produce wrong
/// numbers in someone's collection.
final class JustTCGContractTests: XCTestCase {

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
        ledger.beginRun()

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
        ledger.beginRun()
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
        ledger.beginRun()

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
        ledger.beginRun()

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
        ledger.beginRun()
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
        ledger.beginRun()
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
}
