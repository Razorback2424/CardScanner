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
        XCTAssertEqual(result.quoteState, .current)
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
        gradedOutcome: ScannedGradedOutcome? = nil
    ) -> ResolvedScan {
        let card = TCGdexCard(
            id: "sv10-085",
            localId: "085",
            name: "Example Pokémon",
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
            cardNumber: "085",
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
