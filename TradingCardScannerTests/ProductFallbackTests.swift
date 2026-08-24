import XCTest
import SwiftData
@testable import TradingCardScanner

/// The fallback stage: what gets sent to the vendor, which listing is read, and
/// what is remembered about the attempt.
@MainActor
final class ProductFallbackTests: XCTestCase {
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CollectedCard.self, PriceRecord.self, ProductIdentity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container.mainContext
    }

    private func usd(_ amount: Double) -> NormalizedPrice {
        NormalizedPrice(
            unitMarketPriceUSD: amount,
            currencyCode: "USD",
            source: .tcgplayer,
            sourceVariantID: "normal",
            sourceUpdatedAt: nil,
            fetchedAt: .now
        )
    }

    private func eur(_ amount: Double) -> NormalizedPrice {
        NormalizedPrice(
            unitMarketPriceUSD: amount,
            currencyCode: "EUR",
            source: .cardmarket,
            sourceVariantID: "cardmarket",
            sourceUpdatedAt: nil,
            fetchedAt: .now
        )
    }

    // MARK: - What falls through

    func testCatalogPriceInDollarsFinishesTheJob() {
        XCTAssertFalse(PriceRefreshController.needsFallback(.price(usd(3.75))))
    }

    func testUnpricedCardFallsThrough() {
        XCTAssertTrue(PriceRefreshController.needsFallback(.unavailable(.tcgplayer)))
        XCTAssertTrue(PriceRefreshController.needsFallback(.unavailable(nil)))
    }

    /// The Cardmarket reordering. A euro price is a price, but not one the
    /// collection can total, so the vendor is asked before it is settled for.
    /// If the vendor has nothing, the euro value stays — it is not cleared.
    func testEuroPriceStillFallsThroughSoTheVendorIsTriedFirst() {
        XCTAssertTrue(PriceRefreshController.needsFallback(.price(eur(0.53))))
    }

    func testEuroPriceBecomesUnfinishedOnlyWhenFallbackIsEnabled() {
        XCTAssertTrue(
            PriceRefreshController.hasFinishedPrice(
                amount: 0.53,
                currencyCode: "EUR",
                usesFallback: false
            )
        )
        XCTAssertFalse(
            PriceRefreshController.hasFinishedPrice(
                amount: 0.53,
                currencyCode: "EUR",
                usesFallback: true
            )
        )
        XCTAssertTrue(
            PriceRefreshController.hasFinishedPrice(
                amount: 0.53,
                currencyCode: "USD",
                usesFallback: true
            )
        )
    }

    func testRetryAfterParsesSecondsAndHTTPDate() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(
            ProductPriceService.retryDate(from: "120", now: now),
            now.addingTimeInterval(120)
        )
        XCTAssertNotNil(
            ProductPriceService.retryDate(
                from: "Wed, 21 Oct 2015 07:28:00 GMT",
                now: now
            )
        )
    }

    func testDailyBudgetStopsAtNinetyAndResetsTheNextUTCDay() async throws {
        let suite = "ProductFallbackTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let budget = ProductFallbackBudget(defaults: defaults)
        let now = Date.now

        await budget.beginRun()
        for _ in 0..<ProductFallbackBudget.dailyLimit {
            let reservation = await budget.reserveRequest(now: now)
            XCTAssertEqual(reservation, .allowed)
        }

        let exhausted = await budget.reserveRequest(now: now)
        guard case .budgetReached = exhausted else {
            return XCTFail("Expected the persisted daily limit to stop request 91")
        }

        let tomorrow = now.addingTimeInterval(25 * 60 * 60)
        let reset = await budget.reserveRequest(now: tomorrow)
        XCTAssertEqual(reset, .allowed)
    }

    func testRateLimitBlocksWithoutConsumingAnotherRequest() async throws {
        let suite = "ProductFallbackTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let budget = ProductFallbackBudget(defaults: defaults)
        let now = Date.now
        let retryAt = now.addingTimeInterval(600)

        await budget.beginRun()
        await budget.recordRateLimit(until: retryAt)
        let reservation = await budget.reserveRequest(now: now)
        XCTAssertEqual(reservation, .rateLimited(retryAt: retryAt))
        let snapshot = await budget.snapshot(now: now)
        XCTAssertEqual(snapshot.usedToday, 0)
    }

    // MARK: - Which listing is read

    private func variant(_ condition: String, _ printing: String, _ price: Double) -> ProductVariant {
        ProductVariant(
            condition: condition,
            printing: printing,
            price: price,
            currency: nil,
            variantId: nil,
            lastUpdated: nil
        )
    }

    /// Taken from a live response. Heavily Played is listed above Near Mint and
    /// priced higher, so position and magnitude are both useless as selectors.
    func testNearMintIsSelectedByNameNotByPosition() {
        let variants = [
            variant("Heavily Played", "Holofoil", 0.35),
            variant("Near Mint", "Holofoil", 0.16),
            variant("Lightly Played", "Holofoil", 0.12)
        ]

        let chosen = ProductFinish.nearMintVariant(in: variants, printing: "Holofoil")

        XCTAssertEqual(chosen?.price, 0.16)
        XCTAssertNotEqual(chosen?.price, variants[0].price, "must not take the first entry")
    }

    func testPrintingMustMatchTooNotJustCondition() {
        let variants = [
            variant("Near Mint", "Foil", 0.34),
            variant("Near Mint", "Normal", 0.20)
        ]

        XCTAssertEqual(ProductFinish.nearMintVariant(in: variants, printing: "Normal")?.price, 0.20)
        XCTAssertEqual(ProductFinish.nearMintVariant(in: variants, printing: "Foil")?.price, 0.34)
    }

    func testAFinishTheVendorDoesNotListYieldsNothing() {
        let variants = [variant("Near Mint", "Holofoil", 1.00)]

        XCTAssertNil(ProductFinish.nearMintVariant(in: variants, printing: "Reverse Holofoil"))
    }

    // MARK: - Finish mapping

    func testMappedFinishes() {
        XCTAssertEqual(ProductFinish.printing(for: .normal), "Normal")
        XCTAssertEqual(ProductFinish.printing(for: .holo), "Holofoil")
        XCTAssertEqual(ProductFinish.printing(for: .reverse), "Reverse Holofoil")
        XCTAssertEqual(ProductFinish.printing(for: .nonfoil), "Normal")
        XCTAssertEqual(ProductFinish.printing(for: .foil), "Foil")
    }

    /// The rule the catalog path already follows: a finish with no explicit
    /// mapping is not priced, rather than being given a nearby finish's number.
    /// The ball patterns are deliberately absent — they are already priced from
    /// the catalog, and guessing their vendor spelling would risk exactly the
    /// contamination this layer is meant to avoid.
    func testUnmappedFinishesAreNotPriced() {
        XCTAssertNil(ProductFinish.printing(for: .masterBall))
        XCTAssertNil(ProductFinish.printing(for: .pokeBall))
        XCTAssertNil(ProductFinish.printing(for: .duskBall))
        XCTAssertNil(ProductFinish.printing(for: .firstEdition))
        XCTAssertNil(ProductFinish.printing(for: nil))
    }

    // MARK: - What is remembered

    func testAMatchRemembersTheHandleSoTheSearchIsNotRepeated() throws {
        let store = ProductIdentityStore(context: try makeContext())
        store.record(
            .price(usd(1.23), vendorCardID: "vendor-1", vendorVariantID: "vendor-1_nm_normal"),
            forKey: "k"
        )

        XCTAssertEqual(store.cachedCardID(forKey: "k"), "vendor-1")
        XCTAssertFalse(store.needsResolution(forKey: "k"))
        // The variant handle is what batches are built from; without it every
        // refresh would repeat a search already paid for.
        XCTAssertEqual(
            store.identity(forKey: "k")?.vendorVariantID,
            "vendor-1_nm_normal"
        )
    }

    /// The product exists but is unlisted in this finish. That is a fact about
    /// the listing, not about whether the card was found, so the handle is kept.
    func testAnUnlistedFinishStillRemembersTheProduct() throws {
        let store = ProductIdentityStore(context: try makeContext())
        store.record(.noListingForVariant(vendorCardID: "vendor-2"), forKey: "k")

        XCTAssertEqual(store.cachedCardID(forKey: "k"), "vendor-2")
    }

    func testAMissIsRememberedSoTheSearchIsNotRepeated() throws {
        let store = ProductIdentityStore(context: try makeContext())
        store.record(.noProductMatch, forKey: "k")

        XCTAssertNil(store.cachedCardID(forKey: "k"))
        XCTAssertFalse(store.needsResolution(forKey: "k"), "a known miss must not be re-searched")
        XCTAssertNotNil(store.identity(forKey: "k")?.unmatchedAt)
    }

    /// A network error says nothing about whether the vendor carries the card.
    /// Recording it as a miss would suppress the retry that should happen next
    /// time — the same shape as the starvation bug, in a new place.
    func testAFailedRequestIsNotRememberedAsAMiss() throws {
        let store = ProductIdentityStore(context: try makeContext())
        store.record(.requestFailed, forKey: "k")

        XCTAssertNil(store.identity(forKey: "k"))
        XCTAssertTrue(store.needsResolution(forKey: "k"), "a failed request must be retried")
    }

    func testBudgetAndRateLimitAreNotRememberedAsCardFailures() throws {
        let store = ProductIdentityStore(context: try makeContext())
        store.record(.budgetReached(resetAt: .now), forKey: "budget")
        store.record(.rateLimited(retryAt: .now.addingTimeInterval(60)), forKey: "rate")

        XCTAssertNil(store.identity(forKey: "budget"))
        XCTAssertNil(store.identity(forKey: "rate"))
    }

    func testUnknownCardNeedsResolution() throws {
        let store = ProductIdentityStore(context: try makeContext())

        XCTAssertTrue(store.needsResolution(forKey: "never-seen"))
        XCTAssertNil(store.cachedCardID(forKey: "never-seen"))
    }
}
