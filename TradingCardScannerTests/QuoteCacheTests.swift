import SwiftData
import XCTest
@testable import TradingCardScanner

@MainActor
final class QuoteCacheTests: XCTestCase {
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

    func testScanRequestKeepsItsCapturedPurpose() {
        let identifier = ScanIdentifier.magic(
            setCode: "MKM",
            collectorNumber: "1",
            language: "en",
            contentKind: .regular
        )
        let request = ScanRequest(identifier: identifier, purpose: .priceCheck, generation: 4)

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
        catalogRetrievedAt: Date = .now
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
            request: ScanRequest(identifier: identifier, purpose: .priceCheck, generation: 0),
            card: .pokemon(card, setCode: "DRI"),
            resolved: ResolvedVariant(
                variant: variant,
                resolution: variant == nil ? .catalogSilent : .userConfirmed
            ),
            pokemonPrintRun: nil,
            options: variant.map { [$0] } ?? [],
            catalogRetrievedAt: catalogRetrievedAt
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
