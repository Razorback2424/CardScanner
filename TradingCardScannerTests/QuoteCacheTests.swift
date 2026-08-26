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
}
