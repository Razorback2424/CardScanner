import SwiftData
import XCTest
@testable import TradingCardScanner

@MainActor
final class QuoteCacheTests: XCTestCase {
    func testForeignRefreshCannotOverwriteLastGoodUSDReferenceQuote() async throws {
        let context = try makeContext()
        let scan = priceCheckScan()
        let cache = QuoteCache(context: context)
        let prior = quote(42, at: .now.addingTimeInterval(-60))
        let key = scan.card.providerID
        cache.store(prior, game: .pokemon, printingID: key, variantID: scan.resolved.variant?.id)
        let foreign = PriceLookup.price(NormalizedPrice(unitMarketPriceUSD: 999, currencyCode: "EUR", source: .cardmarket,
            sourceVariantID: "foreign", sourceUpdatedAt: nil, fetchedAt: .now))
        let coordinator = PriceCheckCoordinator(context: context, refreshProvider: StubPriceCheckProvider(outcome: .quote(foreign)))
        let result = coordinator.present(scan)
        let outcome = await coordinator.refresh(result)
        XCTAssertEqual(outcome, .failed(.providerUnavailable))
        XCTAssertEqual(cache.quote(game: .pokemon, printingID: key, variantID: scan.resolved.variant?.id)?.effectiveAmount, 42)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PriceRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PriceObservation>()).isEmpty)
    }

    func testNoProviderObservationDoesNotClaimAnAbsentMarketQuote() async throws {
        let context = try makeContext()
        let coordinator = PriceCheckCoordinator(context: context,
            refreshProvider: StubPriceCheckProvider(outcome: .quote(.unavailable(nil))))
        let result = coordinator.present(priceCheckScan())
        let outcome = await coordinator.refresh(result)
        XCTAssertEqual(outcome, .failed(.providerUnavailable))
        XCTAssertTrue(try context.fetch(FetchDescriptor<ReferenceQuote>()).isEmpty)
    }
    func testMissingPricingAdapterIsTerminalInLivePriceCheck() async throws {
        let context = try makeContext()
        let service = PriceQuoteService(registry: .standard,
                                       adapters: try GamePriceAdapterRegistry(adapters: []))
        let coordinator = PriceCheckCoordinator(context: context, quoteService: service)
        let result = coordinator.present(priceCheckScan())
        let outcome = await coordinator.refresh(result)
        XCTAssertEqual(outcome, .failed(.unsupportedGame))
        XCTAssertTrue(try context.fetch(FetchDescriptor<PriceRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProductIdentity>()).isEmpty)
    }

    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ReferenceQuote.self, PriceRecord.self, PriceObservation.self, PriceCheckDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container.mainContext
    }

    private func quote(_ amount: Double, at date: Date) -> PriceLookup {
        .price(
            NormalizedPrice(
                unitMarketPriceUSD: amount,
                currencyCode: "USD",
                source: .tcgplayer,
                sourceVariantID: "reverse-holofoil",
                sourceUpdatedAt: date,
                fetchedAt: date
            )
        )
    }

    func testQuoteCachingDoesNotCreateCollectionOrPortfolioEvidence() throws {
        let context = try makeContext()
        let cache = QuoteCache(context: context)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        cache.store(
            quote(48.12, at: now),
            game: .pokemon,
            printingID: "sv08.5-001",
            variantID: PhysicalVariant.reverse.id,
            at: now
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<ReferenceQuote>()).count, 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PriceRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PriceObservation>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PriceCheckDay>()).isEmpty)
    }

    func testMagicTreatmentQuoteDoesNotReuseGenericFoilQuote() throws {
        let context = try makeContext()
        let cache = QuoteCache(context: context)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        cache.store(
            quote(48.12, at: now),
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id,
            at: now
        )

        XCTAssertNotNil(
            cache.quote(
                game: .magic,
                printingID: "printing",
                variantID: PhysicalVariant.foil.id
            )
        )
        XCTAssertNil(
            cache.quote(
                game: .magic,
                printingID: "printing",
                variantID: PhysicalVariant.foil.id,
                treatmentIDs: ["surgefoil"]
            )
        )

        cache.store(
            quote(72.50, at: now),
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id,
            at: now,
            treatmentIDs: ["surgefoil"]
        )

        XCTAssertEqual(
            cache.quote(
                game: .magic,
                printingID: "printing",
                variantID: PhysicalVariant.foil.id,
                treatmentIDs: ["surgefoil"]
            )?.amount,
            72.50
        )
    }

    func testPreviouslyStoredMagicTreatmentQuoteRemainsLocalEvidence() throws {
        let context = try makeContext()
        let quote = QuoteCache(context: context).store(
            .price(
                NormalizedPrice(
                    unitMarketPriceUSD: 48.12,
                    currencyCode: "USD",
                    source: .scryfall,
                    sourceVariantID: "usd_foil",
                    sourceUpdatedAt: nil,
                    fetchedAt: .now
                )
            ),
            game: .magic,
            printingID: "printing",
            variantID: PhysicalVariant.foil.id,
            treatmentIDs: ["surgefoil"]
        )

        XCTAssertEqual(quote.amount, 48.12)
        XCTAssertEqual(quote.effectiveAmount, 48.12)
        XCTAssertEqual(quote.display.amount, 48.12)
    }

    func testFailedRefreshKeepsLastKnownQuoteAndItsFreshness() throws {
        let context = try makeContext()
        let cache = QuoteCache(context: context)
        let retrieved = Date(timeIntervalSince1970: 1_700_000_000)
        let failed = retrieved.addingTimeInterval(60)

        cache.store(
            quote(48.12, at: retrieved),
            game: .pokemon,
            printingID: "sv08.5-001",
            variantID: PhysicalVariant.reverse.id,
            at: retrieved
        )
        let record = cache.recordFailure(
            game: .pokemon,
            printingID: "sv08.5-001",
            variantID: PhysicalVariant.reverse.id,
            at: failed
        )

        XCTAssertEqual(record.display.amount, 48.12)
        XCTAssertEqual(record.display.sourceUpdatedAt, retrieved)
        XCTAssertEqual(record.display.fetchedAt, retrieved)
        XCTAssertTrue(record.display.refreshFailed)
    }

    func testOlderQuoteCannotReplaceNewerCachedPrice() throws {
        let cache = QuoteCache(context: try makeContext())
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = older.addingTimeInterval(60)
        cache.store(quote(20, at: newer), game: .pokemon, printingID: "card", variantID: nil, at: newer)

        let record = cache.store(quote(10, at: older), game: .pokemon, printingID: "card",
                                 variantID: nil, at: newer.addingTimeInterval(60))

        XCTAssertEqual(record.amount, 20)
        XCTAssertEqual(record.retrievedAt, newer)
    }

    func testPresentingCachedQuotePreservesLaterRefreshFailure() throws {
        let context = try makeContext()
        let cache = QuoteCache(context: context)
        let retrieved = Date(timeIntervalSince1970: 1_700_000_000)
        let failed = retrieved.addingTimeInterval(60)
        cache.store(quote(20, at: retrieved), game: .pokemon, printingID: "sv10-085", variantID: nil, at: retrieved)
        let record = cache.recordFailure(game: .pokemon, printingID: "sv10-085", variantID: nil, at: failed)

        _ = PriceCheckCoordinator(context: context).present(priceCheckScan())

        XCTAssertEqual(record.lastCheckedAt, failed)
        XCTAssertEqual(record.lastFailureAt, failed)
        XCTAssertEqual(record.amount, 20)

        let recovered = failed.addingTimeInterval(60)
        cache.store(quote(30, at: recovered), game: .pokemon, printingID: "sv10-085", variantID: nil, at: recovered)
        XCTAssertEqual(record.lastCheckedAt, recovered)
        XCTAssertNil(record.lastFailureAt)
        XCTAssertEqual(record.amount, 30)
    }

    func testOlderFailureCannotMarkNewerQuoteAsFailed() throws {
        let cache = QuoteCache(context: try makeContext())
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = older.addingTimeInterval(60)
        cache.store(quote(20, at: newer), game: .pokemon, printingID: "card", variantID: nil, at: newer)

        let record = cache.recordFailure(game: .pokemon, printingID: "card", variantID: nil, at: older)

        XCTAssertEqual(record.lastCheckedAt, newer)
        XCTAssertNil(record.lastFailureAt)
    }

    func testNegativeQuoteCannotReplaceLastKnownPrice() throws {
        let cache = QuoteCache(context: try makeContext())
        let retrieved = Date(timeIntervalSince1970: 1_700_000_000)
        let failed = retrieved.addingTimeInterval(60)
        cache.store(quote(20, at: retrieved), game: .pokemon, printingID: "card", variantID: nil, at: retrieved)

        let invalid = quote(-1, at: failed)
        let record = cache.store(invalid, game: .pokemon, printingID: "card", variantID: nil, at: failed)

        XCTAssertEqual(record.amount, 20)
        XCTAssertEqual(record.retrievedAt, retrieved)
        XCTAssertEqual(record.lastFailureAt, failed)
        XCTAssertFalse(PriceCheckCoordinator.isUsableUSD(invalid))
    }

    func testScanRequestKeepsItsCapturedPurpose() {
        let identifier = ScanIdentifier.magic(
            setCode: "MKM",
            collectorNumber: "1",
            language: "en",
            contentKind: .regular
        )
        let request = ScanRequest(
            subject: ScanSubject(identifier: identifier),
            purpose: .priceCheck,
            generation: 4
        )

        XCTAssertEqual(request.purpose, .priceCheck)
        XCTAssertEqual(request.generation, 4)
    }

    func testPriceCheckUsesCachedQuoteImmediatelyAndKeepsItWhenRefreshFails() async throws {
        let context = try makeContext()
        let scan = priceCheckScan()
        let cached = quote(12.34, at: Date(timeIntervalSince1970: 1_700_000_000))
        QuoteCache(context: context).store(
            cached,
            game: .pokemon,
            printingID: "sv10-085",
            variantID: nil
        )
        let provider = StubPriceCheckProvider(outcome: .failed(.providerUnavailable))
        let coordinator = PriceCheckCoordinator(context: context, refreshProvider: provider)

        let result = coordinator.present(scan)
        XCTAssertEqual(result.display.amount, 12.34)
        XCTAssertEqual(result.quoteState, .stale)
        XCTAssertTrue(result.shouldAutoRefresh)
        XCTAssertNotNil(QuoteCache(context: context).quote(
            game: .pokemon,
            printingID: "sv10-085",
            variantID: nil
        ))

        let outcome = await coordinator.refresh(result)
        XCTAssertEqual(outcome, .failed(.providerUnavailable))
        // The coordinator never replaces a cached quote on a failed refresh.
        XCTAssertEqual(result.display.amount, 12.34)
    }

    func testPriceCheckDoesNotRefetchAQuoteAlreadyReturnedByCardResolution() throws {
        let context = try makeContext()
        let card = TCGdexPricing(
            tcgplayer: TCGPlayerPricing(
                updated: nil,
                normal: TCGPlayerPricePoint(marketPrice: 3.21),
                holo: nil,
                holofoil: nil,
                reverse: nil,
                reverseHolofoil: nil
            ),
            cardmarket: nil
        )
        let result = PriceCheckCoordinator(context: context).present(
            priceCheckScan(variant: .normal, pricing: card)
        )

        XCTAssertEqual(result.display.amount, 3.21)
        XCTAssertEqual(result.quoteState, .current)
        XCTAssertFalse(result.shouldAutoRefresh)
    }

    func testRecentlyFetchedOldProviderPriceStillAutoRefreshes() throws {
        let context = try makeContext()
        let old = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-14T22:55:12Z"))
        let fetched = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-26T00:00:00Z"))
        let pricing = TCGdexPricing(tcgplayer: TCGPlayerPricing(
            updated: ISO8601DateFormatter().string(from: old), normal: nil,
            holo: nil, holofoil: TCGPlayerPricePoint(marketPrice: 4.43), reverse: nil, reverseHolofoil: nil
        ), cardmarket: nil)
        let result = PriceCheckCoordinator(context: context).present(
            priceCheckScan(variant: .holo, pricing: pricing, catalogRetrievedAt: fetched, cardNumber: "195")
        )
        XCTAssertEqual(result.card.providerID, "sv10-195")
        XCTAssertEqual(result.card.name, "Clamperl")
        XCTAssertEqual(result.resolved.variant, .holo)
        XCTAssertTrue(result.shouldAutoRefresh)
        XCTAssertEqual(result.display.sourceUpdatedAt, old)
        XCTAssertEqual(result.display.state(), .stale)
        XCTAssertEqual(result.quoteState, .stale)
    }

    func testSuccessfulUnchangedCheckKeepsSourceDateAndReportsNoNewerData() throws {
        let scan = priceCheckScan(variant: .holo, cardNumber: "195")
        let old = Date.now.addingTimeInterval(-12 * 24 * 60 * 60)
        let primary = quote(4.43, at: old)
        var result = PriceCheckResult(resolvedScan: scan, quote: primary, checkedAt: old, quoteState: .stale)
        let checked = Date.now
        result.completeRefresh(.price(NormalizedPrice(unitMarketPriceUSD: 4.43, currencyCode: "USD",
            source: .tcgplayer, sourceVariantID: "reverse-holofoil", sourceUpdatedAt: old, fetchedAt: checked)), at: checked)
        XCTAssertEqual(result.quoteState, .stale)
        XCTAssertEqual(result.refreshFeedback, .noNewerData)
        XCTAssertEqual(result.lastSuccessfulCheckAt, checked)
        XCTAssertEqual(result.display.sourceUpdatedAt, old)
        XCTAssertEqual(result.display.amount, 4.43)
        XCTAssertFalse(result.isRefreshing)
        let retryAt = checked.addingTimeInterval(60)
        result.completeRefresh(result.quote, issue: .rateLimited(retryAt: retryAt), at: checked)
        XCTAssertEqual(result.refreshFeedback, .noNewerData)
        XCTAssertEqual(result.quoteState, .lastKnown(.rateLimited(retryAt: retryAt)))
        XCTAssertEqual(result.lastSuccessfulCheckAt, checked)
    }

    func testFailedCheckPreservesSuccessfulCheckAndQuoteProvenance() throws {
        let old = Date.now.addingTimeInterval(-12 * 24 * 60 * 60)
        var result = PriceCheckResult(resolvedScan: priceCheckScan(), quote: quote(4.43, at: old), checkedAt: old)
        let previous = result.quote
        let attempted = Date.now
        result.recordFailedCheck(at: attempted)
        XCTAssertEqual(result.quote, previous)
        XCTAssertEqual(result.lastSuccessfulCheckAt, old)
        XCTAssertEqual(result.checkedAt, attempted)
        XCTAssertEqual(result.refreshFeedback, .failed)
        XCTAssertTrue(result.refreshFailed)
    }

    func testNewerExactQuoteCompletesAsFreshAndUpdated() throws {
        let old = Date.now.addingTimeInterval(-12 * 24 * 60 * 60)
        var result = PriceCheckResult(resolvedScan: priceCheckScan(), quote: quote(4.43, at: old), checkedAt: old)
        let fresh = quote(4.03, at: .now)
        result.completeRefresh(fresh)
        XCTAssertEqual(result.quote, fresh)
        XCTAssertEqual(result.quoteState, .current)
        XCTAssertEqual(result.refreshFeedback, .updated)
    }

    func testLiveStalePrimaryTriesFallbackOnceAndKeepsSpecificFailures() async throws {
        let context = try makeContext()
        let old = quote(4.43, at: .now.addingTimeInterval(-12 * 24 * 60 * 60))
        let scan = priceCheckScan(variant: .holo, cardNumber: "195")
        for issue in [PriceCheckRefreshIssue.fallbackDisabled, .fallbackUnconfigured,
                      .rateLimited(retryAt: .now.addingTimeInterval(60)),
                      .budgetLimited(resetAt: .now.addingTimeInterval(60)),
                      .providerUnavailable, .noExactPrice] {
            var calls = 0
            let provider = LivePriceCheckRefreshProvider(
                quoteService: PriceQuoteService(catalogRefreshOverride: { _, _, _ in old }),
                fallbackResolver: PriceFallbackQuoteResolver(context: context),
                fallbackOverride: { card, variant, printRun in
                    calls += 1
                    XCTAssertEqual(card.providerID, scan.card.providerID)
                    XCTAssertEqual(variant, .holo)
                    XCTAssertNil(printRun)
                    return .failed(issue)
                })
            let outcome = await provider.refresh(card: scan.card, variant: .holo, pokemonPrintRun: nil)
            XCTAssertEqual(outcome, .lastKnown(old, issue))
            XCTAssertEqual(calls, 1)
        }
    }

    func testLiveFallbackRequiresDemonstrablyNewerDataAndFreshPrimarySkipsFallback() async throws {
        let context = try makeContext()
        let scan = priceCheckScan(variant: .holo, cardNumber: "195")
        let oldDate = Date.now.addingTimeInterval(-12 * 24 * 60 * 60)
        let old = quote(4.43, at: oldDate)
        let fresh = quote(4.03, at: .now)
        let unknownAge = PriceLookup.price(NormalizedPrice(unitMarketPriceUSD: 99, currencyCode: "USD",
            source: .justTCG, sourceVariantID: "exact", sourceUpdatedAt: nil, fetchedAt: .now))
        for (primary, alternate, expected, expectedCalls) in [
            (old, fresh, fresh, 1), (old, quote(99, at: oldDate.addingTimeInterval(-60)), old, 1),
            (old, unknownAge, old, 1), (fresh, old, fresh, 0)
        ] {
            var calls = 0
            let provider = LivePriceCheckRefreshProvider(
                quoteService: PriceQuoteService(catalogRefreshOverride: { _, _, _ in primary }),
                fallbackResolver: PriceFallbackQuoteResolver(context: context),
                fallbackOverride: { _, _, _ in calls += 1; return .quote(alternate) })
            let outcome = await provider.refresh(card: scan.card, variant: .holo, pokemonPrintRun: nil)
            XCTAssertEqual(outcome, .quote(expected))
            XCTAssertEqual(calls, expectedCalls)
        }
    }

    func testStalePrimaryRespectsActualDisabledFallbackSetting() async throws {
        let previous = UserDefaults.standard.object(forKey: "usesPriceFallback")
        UserDefaults.standard.set(false, forKey: "usesPriceFallback")
        defer { UserDefaults.standard.set(previous, forKey: "usesPriceFallback") }
        let context = try makeContext()
        let old = quote(4.43, at: .now.addingTimeInterval(-12 * 24 * 60 * 60))
        let provider = LivePriceCheckRefreshProvider(
            quoteService: PriceQuoteService(catalogRefreshOverride: { _, _, _ in old }),
            fallbackResolver: PriceFallbackQuoteResolver(context: context))
        let scan = priceCheckScan(variant: .holo)
        let outcome = await provider.refresh(card: scan.card, variant: .holo, pokemonPrintRun: nil)
        XCTAssertEqual(outcome, .lastKnown(old, .fallbackDisabled))
    }

    func testNewDownloadOfOldProviderDataDoesNotReplaceNewerLocalQuote() throws {
        let context = try makeContext()
        let old = Date.now.addingTimeInterval(-12 * 24 * 60 * 60)
        let recent = Date.now.addingTimeInterval(-60)
        QuoteCache(context: context).store(quote(4.03, at: recent),
            game: .pokemon, printingID: "sv10-085", variantID: "normal")
        let pricing = TCGdexPricing(tcgplayer: TCGPlayerPricing(
            updated: ISO8601DateFormatter().string(from: old), normal: TCGPlayerPricePoint(marketPrice: 4.43),
            holo: nil, holofoil: nil, reverse: nil, reverseHolofoil: nil
        ), cardmarket: nil)
        let result = PriceCheckCoordinator(context: context).present(
            priceCheckScan(variant: .normal, pricing: pricing)
        )
        XCTAssertEqual(result.display.amount, 4.03)
        XCTAssertEqual(result.display.sourceUpdatedAt, recent)
        XCTAssertFalse(result.shouldAutoRefresh)
    }

    func testRefreshCannotRegressToOlderProviderData() async throws {
        let context = try makeContext()
        let recent = quote(4.03, at: .now.addingTimeInterval(-60))
        let old = quote(4.43, at: .now.addingTimeInterval(-12 * 24 * 60 * 60))
        QuoteCache(context: context).store(recent,
            game: .pokemon, printingID: "sv10-085", variantID: nil)
        let coordinator = PriceCheckCoordinator(context: context,
            refreshProvider: StubPriceCheckProvider(outcome: .quote(old)))
        let outcome = await coordinator.refresh(coordinator.present(priceCheckScan()))
        XCTAssertEqual(outcome, .quote(recent))
        XCTAssertEqual(QuoteCache(context: context).quote(
            game: .pokemon, printingID: "sv10-085", variantID: nil)?.effectiveAmount, 4.03)
    }

    func testRetainedQuoteSuccessfulCheckSurvivesFreshContextPresentation() async throws {
        try await assertRetainedQuoteCheckSurvivesPresentation(failureAfterSuccess: false)
    }

    func testRetainedQuoteSuccessAndLaterFailureSurviveFreshContextPresentation() async throws {
        try await assertRetainedQuoteCheckSurvivesPresentation(failureAfterSuccess: true)
    }

    private func assertRetainedQuoteCheckSurvivesPresentation(failureAfterSuccess: Bool) async throws {
        let context = try makeContext()
        let t1 = Date(timeIntervalSince1970: 1_793_001_600)
        let t2 = t1.addingTimeInterval(60)
        let t3 = t2.addingTimeInterval(60)
        let scan = priceCheckScan(variant: .holo, cardNumber: "195")
        let retained = PriceLookup.price(NormalizedPrice(unitMarketPriceUSD: 4.03, currencyCode: "USD",
            source: .tcgplayer, sourceVariantID: "holofoil", sourceUpdatedAt: t1, fetchedAt: t1))
        let olderResponse = PriceLookup.price(NormalizedPrice(unitMarketPriceUSD: 4.43, currencyCode: "USD",
            source: .tcgplayer, sourceVariantID: "holofoil", sourceUpdatedAt: t1.addingTimeInterval(-3600), fetchedAt: t2))
        let cache = QuoteCache(context: context)
        cache.store(retained, game: .pokemon, printingID: "sv10-195", variantID: "holo", at: t1)
        cache.store(quote(999, at: t1), game: .pokemon, printingID: "sv10-195", variantID: "reverse", at: t1)
        let coordinator = PriceCheckCoordinator(context: context,
            refreshProvider: StubPriceCheckProvider(outcome: .quote(olderResponse)), now: { t2 })
        var visible = coordinator.present(scan)
        XCTAssertFalse(visible.shouldAutoRefresh, "T1's exact quote is still fresh at T2")
        let outcome = await coordinator.refresh(visible)
        XCTAssertEqual(outcome, .quote(retained))
        visible.completeRefresh(retained, at: try XCTUnwrap(coordinator.lastSuccessfulCheckAt(for: visible)))
        XCTAssertEqual(visible.checkedAt, t2)
        XCTAssertEqual(visible.lastSuccessfulCheckAt, t2)
        if failureAfterSuccess {
            let failedCheck = PriceCheckCoordinator(context: context,
                refreshProvider: StubPriceCheckProvider(outcome: .failed(.providerUnavailable)), now: { t3 })
            let failure = await failedCheck.refresh(visible)
            XCTAssertEqual(failure, .failed(.providerUnavailable))
            visible.recordFailedCheck(at: try XCTUnwrap(failedCheck.recordRefreshFailure(for: visible)))
        }
        try context.save()

        let freshContext = ModelContext(try XCTUnwrap(container))
        let reopened = PriceCheckCoordinator(context: freshContext, now: { t3 }).present(scan)
        XCTAssertEqual(reopened.lastSuccessfulCheckAt, t2)
        XCTAssertFalse(reopened.checkTimeIsRetrievalEvidence)
        XCTAssertEqual(reopened.checkedAt, failureAfterSuccess ? t3 : t2)
        XCTAssertEqual(reopened.refreshFailed, failureAfterSuccess)
        XCTAssertEqual(reopened.refreshFeedback, failureAfterSuccess ? .failed : nil)
        XCTAssertEqual(reopened.quote, retained)
        XCTAssertEqual(reopened.display.sourceUpdatedAt, t1)
        XCTAssertEqual(reopened.display.fetchedAt, t1)
        XCTAssertEqual(reopened.display.state(now: t3), .current)
        XCTAssertFalse(reopened.shouldAutoRefresh)
        XCTAssertEqual(reopened.card.providerID, "sv10-195")
        XCTAssertEqual(reopened.resolved.variant, .holo)
        let stored = try XCTUnwrap(QuoteCache(context: freshContext).quote(
            game: .pokemon, printingID: "sv10-195", variantID: "holo"))
        XCTAssertEqual(stored.lastCheckedAt, failureAfterSuccess ? t3 : t2)
        XCTAssertEqual(stored.lastFailureAt, failureAfterSuccess ? t3 : nil)
        XCTAssertEqual(stored.lastSuccessfulCheckAt, t2)
        XCTAssertEqual(stored.retrievedAt, t1)
        XCTAssertEqual(stored.effectiveAmount, 4.03)
        XCTAssertEqual(QuoteCache(context: freshContext).quote(
            game: .pokemon, printingID: "sv10-195", variantID: "reverse")?.effectiveAmount, 999)
    }

    func testLegacyReferenceQuoteStoreMigratesWithUnknownSuccessTime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.store")
        let t1 = Date(timeIntervalSince1970: 1_793_001_600)
        let t3 = t1.addingTimeInterval(120)
        // Write the pre-follow-up schema, then reopen the same SQLite file with
        // the additive optional field. No CloudKit or collection schema changes.
        try autoreleasepool {
            let legacy = try ModelContainer(for: LegacyReferenceQuoteFixture.ReferenceQuote.self,
                PriceRecord.self, PriceObservation.self, PriceCheckDay.self,
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let row = LegacyReferenceQuoteFixture.ReferenceQuote()
            row.key = "pokemon:sv10-195:holo"
            row.game = "pokemon"
            row.printingID = "sv10-195"
            row.variantID = "holo"
            row.amount = 4.03
            row.sourceRaw = PriceSource.tcgplayer.rawValue
            row.sourceVariantID = "holofoil"
            row.sourceUpdatedAt = t1
            row.retrievedAt = t1
            row.lastCheckedAt = t3
            row.lastFailureAt = t3
            legacy.mainContext.insert(row)
            try legacy.mainContext.save()
        }
        let migrated = try ModelContainer(for: ReferenceQuote.self,
            PriceRecord.self, PriceObservation.self, PriceCheckDay.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let row = try XCTUnwrap(QuoteCache(context: migrated.mainContext).quote(
            game: .pokemon, printingID: "sv10-195", variantID: "holo"))
        XCTAssertNil(row.lastSuccessfulCheckAt, "Legacy attempt timestamps cannot establish success")
        let scan = priceCheckScan(variant: .holo, cardNumber: "195")
        let result = PriceCheckCoordinator(context: migrated.mainContext, now: { t3 }).present(scan)
        XCTAssertNil(result.lastSuccessfulCheckAt)
        XCTAssertTrue(result.checkTimeIsRetrievalEvidence)
        XCTAssertTrue(result.refreshFailed)
        XCTAssertEqual(result.refreshFeedback, .failed)
        XCTAssertEqual(result.checkedAt, t3)
        XCTAssertEqual(result.display.fetchedAt, t1)
        XCTAssertEqual(result.display.sourceUpdatedAt, t1)
        XCTAssertEqual(result.display.amount, 4.03)
        XCTAssertEqual(row.lastCheckedAt, t3)
        XCTAssertEqual(row.lastFailureAt, t3)
        var failedAgain = result
        failedAgain.recordFailedCheck(at: t3.addingTimeInterval(60))
        XCTAssertNil(failedAgain.lastSuccessfulCheckAt, "A failure cannot promote retrieval evidence into success")
    }

    func testPriceCheckPrefersNewerLocalEvidenceOverCachedCatalogPrice() throws {
        let context = try makeContext()
        let cachedCatalogDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerLocalDate = cachedCatalogDate.addingTimeInterval(60 * 60)
        let scan = priceCheckScan(
            pricing: TCGdexPricing(
                tcgplayer: TCGPlayerPricing(
                    updated: nil,
                    normal: TCGPlayerPricePoint(marketPrice: 10),
                    holo: nil,
                    holofoil: nil,
                    reverse: nil,
                    reverseHolofoil: nil
                ),
                cardmarket: nil
            ),
            catalogRetrievedAt: cachedCatalogDate
        )
        PriceStore(context: context).store(
            quote(20, at: newerLocalDate),
            game: .pokemon,
            printingID: "sv10-085",
            variantID: nil,
            at: newerLocalDate
        )

        let result = PriceCheckCoordinator(context: context).present(scan)

        XCTAssertEqual(result.display.amount, 20)
        XCTAssertEqual(result.display.fetchedAt, newerLocalDate)
        XCTAssertNotEqual(result.display.amount, 10)
    }

    func testPriceCheckStartsWithoutUnavailableStateWhenNoQuoteExists() throws {
        let context = try makeContext()
        let coordinator = PriceCheckCoordinator(
            context: context,
            refreshProvider: StubPriceCheckProvider(outcome: .failed(.noExactPrice))
        )

        let result = coordinator.present(priceCheckScan())
        XCTAssertNil(result.display.amount)
        XCTAssertEqual(result.quoteState, .checking)
        XCTAssertTrue(result.shouldAutoRefresh)
    }

    func testSlabPriceCheckStartsInCheckingStateUntilGradedLookupCompletes() throws {
        let context = try makeContext()
        let scan = priceCheckScan(
            slab: GradedSlabEvidence(
                company: .psa,
                grade: CardGrade(value: "10", label: "Gem Mint"),
                certificationNumber: "12345678",
                labelCardText: []
            )
        )

        let result = PriceCheckCoordinator(context: context).present(scan)

        XCTAssertEqual(result.quoteState, .checking)
        XCTAssertNil(result.display.amount)
        XCTAssertTrue(result.shouldAutoRefresh)
    }

    func testPriceCheckSuccessfulRefreshIsCachedAsReferenceEvidence() async throws {
        let context = try makeContext()
        let refreshedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let refreshed = quote(4.56, at: refreshedAt)
        let provider = StubPriceCheckProvider(outcome: .quote(refreshed))
        let coordinator = PriceCheckCoordinator(context: context, refreshProvider: provider)
        let result = coordinator.present(priceCheckScan())

        let outcome = await coordinator.refresh(result)
        XCTAssertEqual(outcome, .quote(refreshed))
        let cached = QuoteCache(context: context).quote(
            game: .pokemon,
            printingID: "sv10-085",
            variantID: nil
        )
        XCTAssertEqual(cached?.amount, 4.56)
        XCTAssertEqual(cached?.retrievedAt, refreshedAt)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PriceRecord>()).isEmpty)
    }

    func testGradedPriceCheckRefreshCachesTheVendorVariantKey() async throws {
        let context = try makeContext()
        let gradedVariant = GradedVariant(
            id: "graded-v2-10",
            cardID: "graded-card",
            company: .psa,
            grade: CardGrade(value: "10", label: "GEM MT"),
            marketPriceUSD: 125,
            updatedAt: nil
        )
        let coordinator = PriceCheckCoordinator(
            context: context,
            gradedResolver: StubGradedResolver(outcome: .bound(gradedVariant))
        )
        let result = coordinator.present(
            priceCheckScan(
                slab: GradedSlabEvidence(
                    company: .psa,
                    grade: CardGrade(value: "10", label: "Gem Mint"),
                    certificationNumber: "12345678",
                    labelCardText: []
                )
            )
        )

        XCTAssertTrue(result.shouldAutoRefresh)
        let refreshed = await coordinator.refresh(result)
        guard case let .quote(.price(quote)) = refreshed else {
            XCTFail("Expected a graded quote, got \(refreshed)")
            return
        }
        XCTAssertEqual(quote.unitMarketPriceUSD, 125)
        XCTAssertEqual(quote.sourceVariantID, gradedVariant.id)

        let cached = QuoteCache(context: context).quote(
            game: .pokemon,
            printingID: "justtcg:v2:\(gradedVariant.id)",
            variantID: nil
        )
        XCTAssertEqual(cached?.amount, 125)
    }

    func testGradedPriceCheckForwardsConfirmedFinishBeforeLabelOrMissingFinish() async throws {
        for labelFinish: PhysicalVariant? in [nil, .normal] {
            let recorder = GradedFinishRecorder()
            let coordinator = PriceCheckCoordinator(context: try makeContext(),
                gradedResolver: StubGradedResolver(outcome: .unavailable, finishRecorder: recorder))
            let result = coordinator.present(priceCheckScan(variant: .holo,
                slab: .init(company: .psa, grade: .init(value: "10"), certificationNumber: nil,
                    labelCardText: [], printedFinish: labelFinish)))
            _ = await coordinator.refresh(result)
            let snapshot = await recorder.snapshot()
            XCTAssertEqual(snapshot.finish, .holo)
            XCTAssertEqual(snapshot.calls, 1)
        }
    }

    func testReviewedYellowARejectsAnOldNormalReferenceWithoutDeletingTheCache() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "pokemon-yellow-a-product-proof", withExtension: "json",
            subdirectory: "TradingCards/SetPricingAudit"))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let entry = try XCTUnwrap((document["cases"] as? [[String: Any]])?.first)
        let source = try JSONDecoder().decode(TCGdexCard.self,
            from: JSONSerialization.data(withJSONObject: XCTUnwrap(entry["source"])))
        let context = try makeContext()
        let cache = QuoteCache(context: context)
        _ = cache.store(quote(999, at: .now), game: .pokemon, printingID: source.id, variantID: PhysicalVariant.normal.id)
        let template = priceCheckScan(variant: .normal)
        let scan = ResolvedScan(request: template.request, card: .pokemon(source, setCode: ""), resolved: template.resolved,
            pokemonPrintRun: nil, options: [.holo], catalogRetrievedAt: .now, gradedOutcome: nil)
        let provider = StubPriceCheckProvider(outcome: .quote(quote(123, at: .now)))
        let coordinator = PriceCheckCoordinator(context: context, refreshProvider: provider)
        let result = coordinator.present(scan)
        XCTAssertEqual(result.quoteState, .unsupportedFinish)
        XCTAssertFalse(result.hasUsableAmount)
        XCTAssertFalse(result.shouldAutoRefresh)
        let refresh = await coordinator.refresh(result)
        XCTAssertEqual(refresh, .failed(.unsupportedFinish))
        XCTAssertEqual(provider.calls, 0)
        XCTAssertEqual(cache.quote(game: .pokemon, printingID: source.id, variantID: PhysicalVariant.normal.id)?.amount, 999)
    }

    func testUnboundGradedRefreshStillStoresVendorVariantQuoteWhenRowIsMissing() throws {
        let context = try makeContext()
        let variant = GradedVariant(
            id: "graded-v2-10",
            cardID: "graded-card",
            company: .psa,
            grade: CardGrade(value: "10", label: "GEM MT"),
            marketPriceUSD: 125,
            updatedAt: nil
        )
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let receipt = GradedVariantBinding.storeUnboundVariantQuote(
            variant,
            game: .pokemon,
            variantID: nil,
            treatmentIDs: [],
            store: PriceStore(context: context),
            at: fetchedAt
        )

        XCTAssertTrue(receipt.wasAccepted)
        XCTAssertEqual(receipt.priceKey, PriceRecord.key(
            game: .pokemon,
            printingID: "justtcg:v2:graded-v2-10",
            variantID: nil,
            treatmentIDs: []
        ))
        let record = try XCTUnwrap(PriceStore(context: context).record(forKey: receipt.priceKey))
        XCTAssertEqual(record.effectiveUnitMarketPriceUSD, 125)
        XCTAssertEqual(record.marketVariantID, variant.id)
        XCTAssertEqual(record.itemKind, .gradedCard)
    }

    func testPriceCheckPassesTheResolvedVariantToItsRefreshProvider() async throws {
        let context = try makeContext()
        let provider = StubPriceCheckProvider(outcome: .failed(.noExactPrice))
        let coordinator = PriceCheckCoordinator(context: context, refreshProvider: provider)
        let result = coordinator.present(priceCheckScan(variant: .reverse))

        _ = await coordinator.refresh(result)

        XCTAssertEqual(provider.lastVariant, .reverse)
        XCTAssertEqual(provider.calls, 1)
    }

    func testPriceCheckPreservesMatcherAndFinishFailuresAsDistinctIssues() async throws {
        let context = try makeContext()
        let scan = priceCheckScan()

        let notMatchedCoordinator = PriceCheckCoordinator(
            context: context,
            refreshProvider: StubPriceCheckProvider(outcome: .failed(.notMatched))
        )
        let notMatched = await notMatchedCoordinator.refresh(notMatchedCoordinator.present(scan))
        XCTAssertEqual(notMatched, .failed(.notMatched))

        let unsupportedFinishCoordinator = PriceCheckCoordinator(
            context: context,
            refreshProvider: StubPriceCheckProvider(outcome: .failed(.unsupportedFinish))
        )
        let unsupportedFinish = await unsupportedFinishCoordinator.refresh(
            unsupportedFinishCoordinator.present(scan)
        )
        XCTAssertEqual(unsupportedFinish, .failed(.unsupportedFinish))
    }

    private func priceCheckScan(
        variant: PhysicalVariant? = nil,
        pricing: TCGdexPricing? = nil,
        catalogRetrievedAt: Date = .now,
        slab: GradedSlabEvidence? = nil,
        gradedOutcome: ScannedGradedOutcome? = nil,
        cardNumber: String = "085"
    ) -> ResolvedScan {
        let card = TCGdexCard(
            id: "sv10-\(cardNumber)",
            localId: cardNumber,
            name: cardNumber == "195" ? "Clamperl" : "Example Pokémon",
            image: nil,
            rarity: nil,
            set: TCGdexSetBrief(
                id: "sv10",
                name: "Destined Rivals",
                cardCount: TCGdexCardCount(total: 182, official: 182)
            ),
            variants: nil,
            pricing: pricing,
            variantsDetailed: nil
        )
        let identifier = ScanIdentifier.pokemon(
            setCode: "DRI",
            cardNumber: cardNumber,
            printedTotal: 182,
            setDefinition: PokemonSetDefinition(
                printedCode: "DRI",
                tcgdexSetID: "sv10",
                officialCount: 182,
                releaseIndex: 1
            )
        )
        return ResolvedScan(
            request: ScanRequest(
                subject: ScanSubject(identifier: identifier, slab: slab),
                purpose: .priceCheck,
                generation: 0
            ),
            card: .pokemon(card, setCode: "DRI"),
            resolved: ResolvedVariant(
                variant: variant,
                resolution: variant == nil ? .catalogSilent : .userConfirmed
            ),
            pokemonPrintRun: nil,
            options: variant.map { [$0] } ?? [],
            catalogRetrievedAt: catalogRetrievedAt,
            gradedOutcome: gradedOutcome
        )
    }
}

@MainActor
private final class StubPriceCheckProvider: PriceCheckRefreshProvider {
    let outcome: PriceCheckRefreshOutcome
    private(set) var calls = 0
    private(set) var lastVariant: PhysicalVariant?

    init(outcome: PriceCheckRefreshOutcome) {
        self.outcome = outcome
    }

    func refresh(
        card: IdentifiedCard,
        variant: PhysicalVariant?,
        pokemonPrintRun: PokemonPrintRun?
    ) async -> PriceCheckRefreshOutcome {
        calls += 1
        lastVariant = variant
        return outcome
    }
}

private struct StubGradedResolver: ScannedGradedResolving {
    let outcome: ScannedGradedOutcome
    var finishRecorder: GradedFinishRecorder? = nil

    func resolve(
        card: IdentifiedCard,
        slab: GradedSlabEvidence,
        pokemonPrintRun: PokemonPrintRun?
    ) async -> ScannedGradedOutcome {
        await finishRecorder?.record(slab.printedFinish)
        return outcome
    }
}

private actor GradedFinishRecorder {
    private var finish: PhysicalVariant?
    private var calls = 0
    func record(_ value: PhysicalVariant?) { finish = value; calls += 1 }
    func snapshot() -> (finish: PhysicalVariant?, calls: Int) { (finish, calls) }
}

/// The exact cache model before this follow-up, used only to verify the
/// automatic additive migration and unknown legacy success-time semantics.
private enum LegacyReferenceQuoteFixture {
    @Model final class ReferenceQuote {
        @Attribute var key: String = ""
        var game: String = ""
        var printingID: String = ""
        var variantID: String?
        var magicTreatmentIDsRaw: [String] = []
        var amount: Double?
        var currencyCode: String = "USD"
        var sourceRaw: String?
        var sourceVariantID: String?
        var sourceUpdatedAt: Date?
        var retrievedAt: Date?
        var lastCheckedAt: Date?
        var lastFailureAt: Date?
        var catalogPriceIdentity: String?
        var invalidatedAt: Date?
        init() {}
    }
}
