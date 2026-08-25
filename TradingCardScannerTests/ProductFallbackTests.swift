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

        let chosen = ProductFinish.nearMintVariant(in: variants, requirement: .printings(["Holofoil"]))

        XCTAssertEqual(chosen?.price, 0.16)
        XCTAssertNotEqual(chosen?.price, variants[0].price, "must not take the first entry")
    }

    func testPrintingMustMatchTooNotJustCondition() {
        let variants = [
            variant("Near Mint", "Foil", 0.34),
            variant("Near Mint", "Normal", 0.20)
        ]

        XCTAssertEqual(ProductFinish.nearMintVariant(in: variants, requirement: .printings(["Normal"]))?.price, 0.20)
        XCTAssertEqual(ProductFinish.nearMintVariant(in: variants, requirement: .printings(["Foil"]))?.price, 0.34)
    }

    func testAFinishTheVendorDoesNotListYieldsNothing() {
        let variants = [variant("Near Mint", "Holofoil", 1.00)]

        XCTAssertNil(ProductFinish.nearMintVariant(in: variants, requirement: .printings(["Reverse Holofoil"])))
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

    // MARK: - Unrecorded finishes

    /// A CSV import routinely carries no finish. Refusing those outright before
    /// any request left a large part of an imported collection permanently
    /// unpriceable — the fallback existed for exactly these rows and never ran
    /// for them.
    func testUnrecordedFinishIsPricedWhenTheCardLeavesNoDoubt() {
        let variants = [
            variant("Near Mint", "Normal", 4.25),
            variant("Lightly Played", "Normal", 2.10)
        ]

        XCTAssertEqual(
            ProductFinish.nearMintVariant(in: variants, requirement: .unknownFinish(.unspecified))?.price,
            4.25
        )
    }

    /// Two finishes means the finish genuinely matters. Picking between them is
    /// how a foil's price lands on a plain copy.
    func testUnrecordedFinishIsRefusedWhenSeveralFinishesExist() {
        let variants = [
            variant("Near Mint", "Normal", 0.20),
            variant("Near Mint", "Foil", 8.40)
        ]

        XCTAssertNil(ProductFinish.nearMintVariant(in: variants, requirement: .unknownFinish(.unspecified)))
    }

    /// An unmapped finish stays refused. This is the borrowing the whole layer
    /// exists to prevent, and "unknown" must not become a way around it.
    func testUnmappedFinishIsStillRefused() {
        XCTAssertNil(ProductFinish.requirement(for: .masterBall))
        XCTAssertEqual(ProductFinish.requirement(for: nil), .unknownFinish(.unspecified))
        XCTAssertEqual(ProductFinish.requirement(for: .holo), .printings(["Holofoil"]))
    }

    // MARK: - Vendor-native rows

    /// A sealed box has no TCGdex or Scryfall identity, so it must not be sent
    /// down the catalog pass: that spends a request to learn nothing and then
    /// stamps a price failure that reads as though something went wrong.
    func testSealedAndGradedRowsAreVendorNative() {
        func target(kind: CollectionItemKind, handle: String?) -> PriceTarget {
            PriceTarget(
                game: .pokemon, printingID: "p", catalogPrintingID: nil, setCode: "",
                variantID: nil, importedIdentity: nil, catalogMetadataCheckedAt: nil,
                lastFailureAt: nil, hasPrice: false, lastCheckedAt: nil,
                itemKind: kind, marketVariantID: handle
            )
        }

        XCTAssertTrue(target(kind: .sealedProduct, handle: "v-sealed").isVendorNative)
        XCTAssertTrue(target(kind: .sealedProduct, handle: nil).isVendorNative)
        // A slab has an underlying catalog identity, and an imported one still
        // needs the catalog pass to resolve it and fetch artwork. It reaches the
        // vendor as an ordinary fallback candidate instead.
        XCTAssertFalse(target(kind: .gradedCard, handle: "v-graded").isVendorNative)
        // Likewise a raw card that already has a handle: skipping the catalog
        // would forfeit a free price it may publish later.
        XCTAssertFalse(target(kind: .rawCard, handle: "v-resolved").isVendorNative)
        XCTAssertFalse(target(kind: .rawCard, handle: nil).isVendorNative)
    }

    // MARK: - WotC editions

    /// Pinned from live responses. `jungle-pokemon` publishes exactly
    /// `1st Edition Holofoil` and `Unlimited Holofoil` on the same card, and
    /// `base-set-shadowless-pokemon` adds the bare `1st Edition` / `Unlimited`
    /// spellings for cards with no foil treatment.
    func testWotCEditionPrintingSpellings() {
        XCTAssertEqual(
            ProductEdition.firstEdition.printings(finish: "Holofoil"),
            ["1st Edition Holofoil"]
        )
        XCTAssertEqual(
            ProductEdition.firstEdition.printings(finish: "Normal"),
            ["1st Edition Normal", "1st Edition"]
        )
        XCTAssertEqual(
            ProductEdition.shadowlessUnlimited.printings(finish: "Holofoil"),
            ["Unlimited Holofoil"]
        )
        // Base Set prints a plain `Holofoil` for its shadowed Unlimited run
        // while Jungle qualifies the same run as `Unlimited Holofoil`. Both
        // spellings are accepted; only one exists per set.
        XCTAssertEqual(
            ProductEdition.unlimited.printings(finish: "Holofoil"),
            ["Holofoil", "Unlimited Holofoil"]
        )
        XCTAssertEqual(ProductEdition.unspecified.printings(finish: "Holofoil"), ["Holofoil"])
    }

    /// The one distinction that must never be crossed: an Unlimited row may
    /// never read a 1st Edition listing, whatever else it accepts.
    func testUnlimitedNeverAdmitsAFirstEditionListing() {
        XCTAssertFalse(ProductEdition.unlimited.admits(printing: "1st Edition Holofoil"))
        XCTAssertTrue(ProductEdition.unlimited.admits(printing: "Unlimited Holofoil"))
        XCTAssertTrue(ProductEdition.unlimited.admits(printing: "Holofoil"))

        XCTAssertTrue(ProductEdition.firstEdition.admits(printing: "1st Edition Holofoil"))
        XCTAssertFalse(ProductEdition.firstEdition.admits(printing: "Unlimited Holofoil"))

        XCTAssertTrue(ProductEdition.shadowlessUnlimited.admits(printing: "Unlimited Holofoil"))
        XCTAssertFalse(ProductEdition.shadowlessUnlimited.admits(printing: "Holofoil"))
    }

    /// Base Set is the only WotC set the vendor splits by *set* rather than by
    /// printing: 1st Edition and Shadowless both live in `Base Set (Shadowless)`
    /// while plain `Base Set` is the shadowed Unlimited run.
    func testBaseSetEditionsSelectTheShadowlessSet() {
        let slugs = ["base-set-pokemon", "base-set-shadowless-pokemon", "jungle-pokemon"]

        XCTAssertEqual(
            ProductEdition.firstEdition.setSlug(plain: "base-set-pokemon", knownSlugs: slugs),
            "base-set-shadowless-pokemon"
        )
        XCTAssertEqual(
            ProductEdition.shadowlessUnlimited.setSlug(plain: "base-set-pokemon", knownSlugs: slugs),
            "base-set-shadowless-pokemon"
        )
        XCTAssertEqual(
            ProductEdition.unlimited.setSlug(plain: "base-set-pokemon", knownSlugs: slugs),
            "base-set-pokemon"
        )
        // Jungle keeps both runs in one set.
        XCTAssertEqual(
            ProductEdition.firstEdition.setSlug(plain: "jungle-pokemon", knownSlugs: slugs),
            "jungle-pokemon"
        )
        // Shadowless exists nowhere else, so there is no set to ask about and
        // no ordinary-run price to fall onto.
        XCTAssertNil(
            ProductEdition.shadowlessUnlimited.setSlug(plain: "jungle-pokemon", knownSlugs: slugs)
        )
    }

    /// Skyridge publishes only `Holofoil`, `Reverse Holofoil` and `Normal` —
    /// no edition qualifier at all. A 1st Edition e-card row therefore finds no
    /// matching printing and stays unpriced, rather than taking the number that
    /// covers both runs and losing the premium.
    func testECardSetsHaveNoEditionSpecificListing() {
        let skyridge = [
            variant("Near Mint", "Holofoil", 42.00),
            variant("Near Mint", "Reverse Holofoil", 65.00)
        ]

        XCTAssertNil(
            ProductFinish.nearMintVariant(
                in: skyridge,
                requirement: .printings(ProductEdition.firstEdition.printings(finish: "Holofoil"))
            )
        )
        XCTAssertEqual(
            ProductFinish.nearMintVariant(
                in: skyridge,
                requirement: .printings(ProductEdition.unlimited.printings(finish: "Holofoil"))
            )?.price,
            42.00
        )
    }

    /// A split set prices both runs off one card, and each must read its own.
    func testSplitSetReadsTheMatchingEdition() {
        let jungle = [
            variant("Near Mint", "1st Edition Holofoil", 480.00),
            variant("Near Mint", "Unlimited Holofoil", 96.00)
        ]

        func price(_ run: PokemonPrintRun) -> Double? {
            ProductFinish.nearMintVariant(
                in: jungle,
                requirement: .printings(ProductEdition.from(run).printings(finish: "Holofoil"))
            )?.price
        }

        XCTAssertEqual(price(.firstEdition), 480.00)
        XCTAssertEqual(price(.unlimited), 96.00)
    }

    /// The free plan rejects any `limit` above 20 outright, failing the whole
    /// request rather than returning a short page.
    func testListPageSizeStaysWithinThePlanLimit() {
        XCTAssertLessThanOrEqual(JustTCGQuota.maximumPageSize, 20)
    }

    // MARK: - Japanese printings

    /// Japanese printings carry a ` - Japanese` suffix. Without it the app asked
    /// for `Holofoil` where the vendor publishes `Holofoil - Japanese`, so every
    /// Japanese card in a collection came back unpriced — not an edge case, the
    /// whole Japanese catalogue.
    func testJapanesePrintingsCarryTheLocaleSuffix() {
        XCTAssertEqual(
            ProductEdition.unspecified.printings(finish: "Holofoil", isJapanese: true),
            ["Holofoil - Japanese"]
        )
        XCTAssertEqual(
            ProductEdition.unspecified.printings(finish: "Normal", isJapanese: true),
            ["Normal - Japanese"]
        )
        XCTAssertEqual(
            ProductEdition.unspecified.printings(finish: "Holofoil"),
            ["Holofoil"],
            "English is untouched"
        )
    }

    /// The vendor separates early Japanese prints by set — "Expansion Pack (No
    /// Rarity)" beside "Expansion Pack" — and publishes no edition-qualified
    /// Japanese printing. A Japanese 1st Edition row therefore finds nothing,
    /// which is the honest answer: the ordinary Japanese price is not it.
    func testJapaneseHasNoEditionQualifiedListing() {
        let japanese = [
            variant("Near Mint", "Holofoil - Japanese", 800.00),
            variant("Lightly Played", "Holofoil - Japanese", 448.98)
        ]

        XCTAssertEqual(
            ProductFinish.nearMintVariant(
                in: japanese,
                requirement: .printings(
                    ProductEdition.unspecified.printings(finish: "Holofoil", isJapanese: true)
                )
            )?.price,
            800.00
        )
        XCTAssertNil(
            ProductFinish.nearMintVariant(
                in: japanese,
                requirement: .printings(
                    ProductEdition.firstEdition.printings(finish: "Holofoil", isJapanese: true)
                )
            ),
            "no 1st Edition Japanese listing exists to read"
        )
    }

    /// Artwork rides along with the price, but a row can need one without the
    /// other. A sealed product priced yesterday is not stale, so it never
    /// entered a refresh, so the backfill never saw it — and the placeholder box
    /// stayed no matter how many times the user pulled to refresh.
    func testMissingArtworkIsItsOwnReasonToRefresh() {
        func target(hasPrice: Bool, needsArtwork: Bool) -> PriceTarget {
            PriceTarget(
                game: .pokemon, printingID: "p", catalogPrintingID: nil, setCode: "",
                variantID: nil, importedIdentity: nil, catalogMetadataCheckedAt: nil,
                lastFailureAt: nil, hasPrice: hasPrice, lastCheckedAt: .now,
                itemKind: .sealedProduct, marketVariantID: "v", needsArtwork: needsArtwork
            )
        }

        XCTAssertEqual(
            PriceRefreshController.staleTargets(from: [target(hasPrice: true, needsArtwork: true)]).count,
            1,
            "a freshly priced row with no picture still has something to fetch"
        )
        XCTAssertTrue(
            PriceRefreshController.staleTargets(
                from: [target(hasPrice: true, needsArtwork: false)]
            ).isEmpty,
            "a row with both is left alone"
        )
    }

    func testSealedArtworkBackfillDoesNotRequireGeneralPriceFallback() {
        let sealedArtwork = PriceTarget(
            game: .pokemon, printingID: "p", catalogPrintingID: nil, setCode: "",
            variantID: nil, importedIdentity: nil, catalogMetadataCheckedAt: nil,
            lastFailureAt: nil, hasPrice: true, lastCheckedAt: .now,
            itemKind: .sealedProduct, marketVariantID: "v", needsArtwork: true
        )
        let ordinaryPrice = PriceTarget(
            game: .pokemon, printingID: "c", catalogPrintingID: "c", setCode: "SET",
            variantID: "normal", importedIdentity: nil, catalogMetadataCheckedAt: nil,
            lastFailureAt: nil, hasPrice: false, lastCheckedAt: nil,
            itemKind: .rawCard, marketVariantID: nil, needsArtwork: false
        )

        XCTAssertTrue(
            PriceRefreshController.permitsVendorWork(
                for: sealedArtwork,
                usesFallback: false
            )
        )
        XCTAssertFalse(
            PriceRefreshController.permitsVendorWork(
                for: ordinaryPrice,
                usesFallback: false
            )
        )
        XCTAssertTrue(
            PriceRefreshController.permitsVendorWork(
                for: ordinaryPrice,
                usesFallback: true
            )
        )
    }
}
