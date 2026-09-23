import Foundation
import CryptoKit
import CoreImage
import ImageIO
import XCTest
import SwiftData
import UIKit
import UniformTypeIdentifiers
@testable import TradingCardScanner

private func centeringDiagnosticDirectory(_ name: String) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    let root = environment["CENTERING_DIAGNOSTIC_OUTPUT_ROOT"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    } ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("TradingCardScannerCenteringDiagnostics", isDirectory: true)
    let directory = root.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@MainActor
final class OpusImplementationPlanTests: XCTestCase {
    func testRM001GradedCSVWithoutCatalogProviderIDCanRenderVariantOptions() throws {
        let gradedKey = CollectedCard.scannedGradedCollectionKey(
            game: .pokemon,
            underlyingPrintingID: ProductionRowFixtures.pokemonPrintingID,
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            certificationNumber: "RM001-GRADED"
        )
        let csv = """
        game,provider_id,card_name,set_name,set_code,card_number,quantity,item_kind,grading_company,grade,grade_label,certification_number
        pokemon,\(gradedKey),Eevee,Prismatic Evolutions,PRE,074,1,gradedCard,psa,10,Gem Mint,RM001-GRADED
        """
        let plan = try CollectionCSV.parse(Data(csv.utf8))
        let container = try ProductionRowFixtures.makeContainer()
        _ = try CollectionCSV.apply(plan, to: container.mainContext)
        let row = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).first
        )

        // RM-001: this supported legacy import shape must reach the detail
        // helper without trapping even though it has no catalog identity.
        let options = CollectionCardDetailView.gradedVariantOptions(for: row)
        XCTAssertTrue(options.isEmpty)
    }

    func testRM001SealedCSVWithoutMarketplaceOrCatalogIDCanRenderVariantOptions() throws {
        let csv = """
        game,provider_id,card_name,set_name,set_code,card_number,quantity,item_kind
        pokemon,sealed:pokemon:legacy-box,Legacy Booster Box,Prismatic Evolutions,,,2,sealedProduct
        """
        let plan = try CollectionCSV.parse(Data(csv.utf8))
        let container = try ProductionRowFixtures.makeContainer()
        _ = try CollectionCSV.apply(plan, to: container.mainContext)
        let row = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).first
        )

        // RM-001: the analogous unresolved sealed row must also return safely.
        let options = CollectionCardDetailView.gradedVariantOptions(for: row)
        XCTAssertTrue(options.isEmpty)
    }

    func testREQ002ProductionRowsRoundTripCollectionKeysAndQuantities() throws {
        let sourceContainer = try ProductionRowFixtures.makeContainer()
        let sourceContext = sourceContainer.mainContext
        let store = CollectionStore(context: sourceContext)
        let rawCard = try ProductionRowFixtures.pokemonCard()

        _ = try store.add(
            rawCard,
            resolved: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
            quantity: 2
        )
        _ = try ProductionRowFixtures.gradedRow(in: sourceContext)
        _ = try ProductionRowFixtures.scannedGradedRow(in: sourceContext)
        _ = try ProductionRowFixtures.sealedRow(in: sourceContext)

        let sourceRows = try sourceContext.fetch(FetchDescriptor<CollectedCard>())
        let expected = Dictionary(
            uniqueKeysWithValues: sourceRows.map { ($0.collectionKey, $0.quantity) }
        )
        let exported = CollectionCSV.export(sourceRows)
        let plan = try CollectionCSV.parse(Data(exported.text.utf8))

        let destinationContainer = try ProductionRowFixtures.makeContainer()
        let result = try CollectionCSV.apply(plan, to: destinationContainer.mainContext)
        let importedRows = try destinationContainer.mainContext.fetch(
            FetchDescriptor<CollectedCard>()
        )

        XCTAssertEqual(result.failedRows, [])
        XCTAssertEqual(importedRows.count, expected.count)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: importedRows.map { ($0.collectionKey, $0.quantity) }),
            expected
        )
    }

    func testREQ002OlderCSVWithoutCollectionKeyPreservesAlreadyNamespacedKeys() throws {
        let gradedKey = CollectedCard.scannedGradedCollectionKey(
            game: .pokemon,
            underlyingPrintingID: ProductionRowFixtures.pokemonPrintingID,
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            certificationNumber: "CERT-OLD"
        )
        let sealedKey = "sealed:pokemon:legacy-box"
        let csv = """
        game,provider_id,card_name,set_name,set_code,card_number,quantity,item_kind,grading_company,grade,grade_label,certification_number
        pokemon,\(gradedKey),Eevee,Prismatic Evolutions,PRE,074,1,gradedCard,psa,10,Gem Mint,CERT-OLD
        pokemon,\(sealedKey),Booster Box,Prismatic Evolutions,,,2,sealedProduct,,,,
        """

        let plan = try CollectionCSV.parse(Data(csv.utf8))

        XCTAssertEqual(
            Set(plan.entries.map(\.collectionKey)),
            Set([gradedKey, sealedKey])
        )
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: plan.entries.map { ($0.collectionKey, $0.quantity) }),
            [gradedKey: 1, sealedKey: 2]
        )
    }

    func testREQ002SealedProductionRoundTripRetainsPreImplementationKey() throws {
        let sourceContainer = try ProductionRowFixtures.makeContainer()
        let sourceContext = sourceContainer.mainContext
        let product = SealedProductSummary(
            id: "preimplementation-product",
            name: "Pre-implementation Booster Box",
            setName: "Prismatic Evolutions",
            variantID: "preimplementation-variant",
            marketPriceUSD: nil,
            updatedAt: nil,
            imageURL: nil
        )
        let sourceMutation = try CollectionStore(context: sourceContext).addSealed(
            product,
            game: .pokemon
        )
        let originalKey = sourceMutation.collectionKey
        let sourceRow = try XCTUnwrap(
            try sourceContext.fetch(FetchDescriptor<CollectedCard>()).first
        )

        let plan = try CollectionCSV.parse(
            Data(CollectionCSV.export([sourceRow]).text.utf8)
        )
        let destinationContainer = try ProductionRowFixtures.makeContainer()
        _ = try CollectionCSV.apply(plan, to: destinationContainer.mainContext)
        let importedRow = try XCTUnwrap(
            try destinationContainer.mainContext.fetch(FetchDescriptor<CollectedCard>()).first
        )

        XCTAssertEqual(originalKey, "sealed:pokemon:preimplementation-product:preimplementation-variant")
        XCTAssertEqual(importedRow.collectionKey, originalKey)
    }

    func testRM002PreviousBuildCSVWithCatalogProviderIDPreservesScannedGradedKey() throws {
        let sourceContainer = try ProductionRowFixtures.makeContainer()
        let sourceRow = try ProductionRowFixtures.scannedGradedRow(
            in: sourceContainer.mainContext,
            certificationNumber: "RM002-CERT"
        )
        let originalKey = sourceRow.collectionKey
        let exportedLines = CollectionCSV.export([sourceRow]).text
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
        var headers = exportedLines[0].split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        var values = exportedLines[1].split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        let collectionKeyIndex = try XCTUnwrap(headers.firstIndex(of: "collection_key"))
        headers.remove(at: collectionKeyIndex)
        values.remove(at: collectionKeyIndex)
        let previousBuildCSV = "\(headers.joined(separator: ","))\n\(values.joined(separator: ","))\n"

        let plan = try CollectionCSV.parse(Data(previousBuildCSV.utf8))
        let destinationContainer = try ProductionRowFixtures.makeContainer()
        _ = try CollectionCSV.apply(plan, to: destinationContainer.mainContext)
        let importedRows = try destinationContainer.mainContext.fetch(
            FetchDescriptor<CollectedCard>()
        )

        // RM-002: the immediately preceding export format carried
        // catalog_provider_id but not collection_key; provider identity was
        // already the canonical scanned-slab key in that format.
        XCTAssertEqual(importedRows.count, 1)
        XCTAssertEqual(importedRows.first?.collectionKey, originalKey)
    }

    func testREQ003GradedVariantOptionsUseUnderlyingPrintingSetID() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let card = try ProductionRowFixtures.pokemonCard()
        let mutation = try CollectionStore(context: container.mainContext).addScannedGraded(
            underlying: card,
            company: .psa,
            grade: CardGrade(value: "9", label: "Mint"),
            certificationNumber: "REQ003-CERT",
            resolved: ResolvedVariant(variant: .reverse, resolution: .userConfirmed)
        )
        let row = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).first {
                $0.collectionKey == mutation.collectionKey
            }
        )

        let evidence = CollectionCardDetailView.gradedVariantEvidence(for: row)
        let options = CollectionCardDetailView.gradedVariantOptions(for: row)

        XCTAssertEqual(evidence.setID, "sv08.5")
        XCTAssertFalse(evidence.setID.contains("graded"))
        XCTAssertTrue(options.contains(.pokeBall))
        XCTAssertTrue(options.contains(.masterBall))
    }

    func testREQ003GradedVariantOptionsIncludeVerifiedStampedRelease() throws {
        let container = try ProductionRowFixtures.makeContainer()
        let card = try XCTUnwrap(
            try JSONDecoder().decode(
                TCGdexCard.self,
                from: Data(
                    """
                    {"id":"swsh6-57","localId":"57","name":"Pikachu","image":"https://assets.example/swsh6/57","set":{"id":"swsh6","name":"Evolving Skies","cardCount":{"total":203,"official":203}},"pricing":{"tcgplayer":{"normal":{"marketPrice":1.0}}}}
                    """.utf8
                )
            )
        )
        let mutation = try CollectionStore(context: container.mainContext).addScannedGraded(
            underlying: .pokemon(card, setCode: "EVS"),
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            certificationNumber: "REQ003-STAMP",
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed)
        )
        let row = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<CollectedCard>()).first {
                $0.collectionKey == mutation.collectionKey
            }
        )

        XCTAssertTrue(
            CollectionCardDetailView.gradedVariantOptions(for: row).contains {
                $0.id == PokemonStampedReleaseCatalog.entries(providerID: "swsh6-57").first?.variant.id
            }
        )
    }

    func testREQ005NonUSDTransitionDepricesCurrentAndReplaySymmetrically() throws {
        let container = try ModelContainer(
            for: CollectedCard.self,
            PriceRecord.self,
            ProductIdentity.self,
            CollectionActivity.self,
            InventoryEvent.self,
            PriceObservation.self,
            PriceCheckDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let card = try ProductionRowFixtures.pokemonCard()
        let timeZone = TimeZone(identifier: "UTC")!
        let acquisitionAt = Date(timeIntervalSince1970: 1_800_000_000)
        let mutation = try CollectionStore(context: context).add(
            card,
            resolved: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
            quantity: 2
        )
        let row = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CollectedCard>()).first {
                $0.collectionKey == mutation.collectionKey
            }
        )
        row.dateAdded = acquisitionAt
        let inventoryEvents = try context.fetch(FetchDescriptor<InventoryEvent>())
        for event in inventoryEvents where event.collectionKey == mutation.collectionKey {
            event.occurredAt = acquisitionAt
            event.recordedAt = acquisitionAt
        }
        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        for activity in activities where activity.collectionKey == mutation.collectionKey {
            activity.occurredAt = acquisitionAt
        }
        try context.save()

        // The owned quantity must exist before the transition so the replay can
        // attribute the full de-pricing to the two copies rather than treating
        // the first quote as a price for a not-yet-owned position.
        let firstPriceAt = acquisitionAt.addingTimeInterval(3_600)
        let secondPriceAt = firstPriceAt.addingTimeInterval(60)
        let priceStore = PriceStore(context: context)

        XCTAssertTrue(
            priceStore.store(
                .price(
                    NormalizedPrice(
                        unitMarketPriceUSD: 10,
                        currencyCode: "USD",
                        source: .justTCG,
                        sourceVariantID: "usd-reverse",
                        sourceUpdatedAt: firstPriceAt,
                        fetchedAt: firstPriceAt
                    )
                ),
                game: row.cardGame,
                printingID: row.priceStorageID,
                variantID: row.variantID,
                at: firstPriceAt
            )
        )
        try context.save()

        XCTAssertTrue(
            priceStore.store(
                .price(
                    NormalizedPrice(
                        unitMarketPriceUSD: 12,
                        currencyCode: "EUR",
                        source: .cardmarket,
                        sourceVariantID: "eur-reverse",
                        sourceUpdatedAt: secondPriceAt,
                        fetchedAt: secondPriceAt
                    )
                ),
                game: row.cardGame,
                printingID: row.priceStorageID,
                variantID: row.variantID,
                at: secondPriceAt
            )
        )
        try context.save()

        XCTAssertNil(
            InventoryLedger(context: context)
                .valuation(forPriceKey: row.priceKey)
                .unitPrice,
            "the current valuation must de-price the newer non-USD evidence"
        )

        let through = secondPriceAt.addingTimeInterval(1)
        let computation = PortfolioReplaySnapshotBuilder.compute(
            context: context,
            epoch: PortfolioCalendar.day(containing: acquisitionAt, in: timeZone),
            through: through,
            timeZone: timeZone
        )
        let attribution = try XCTUnwrap(computation.replay.live?.attribution)

        XCTAssertEqual(attribution.currentValue, .zero)
        XCTAssertEqual(attribution.closeValue, .zero)
        XCTAssertEqual(attribution.market, .zero)
        XCTAssertEqual(attribution.pricingAdjustment, -Money(rounding: 20)!)
        XCTAssertEqual(attribution.unexplained, .zero)
        XCTAssertEqual(computation.valuation.value, .zero)
        XCTAssertEqual(computation.valuation.unpricedCount, 0)
        XCTAssertEqual(computation.valuation.otherCurrencyCount, 2)
        XCTAssertNil(
            PortfolioEngine.unattributedValueChangeDefect(
                attribution: attribution,
                periodStart: PortfolioCalendar.day(containing: acquisitionAt, in: timeZone),
                periodEnd: through
            )
        )
    }

    func testRM006NonUSDTransitionAcrossDayBoundaryKeepsCurrentAndReplayAligned() throws {
        let container = try ModelContainer(
            for: CollectedCard.self,
            PriceRecord.self,
            ProductIdentity.self,
            CollectionActivity.self,
            InventoryEvent.self,
            PriceObservation.self,
            PriceCheckDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let timeZone = TimeZone(identifier: "UTC")!
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        let dayN = PortfolioCalendar.day(containing: anchor, in: timeZone)
        let nextDay = PortfolioCalendar.boundary(afterDay: dayN, in: timeZone)
        let acquisitionAt = dayN.addingTimeInterval(3_600)
        let firstPriceAt = dayN.addingTimeInterval(7_200)
        let secondPriceAt = nextDay.addingTimeInterval(3_600)
        let through = secondPriceAt.addingTimeInterval(1)
        let card = try ProductionRowFixtures.pokemonCard()
        let mutation = try CollectionStore(context: context).add(
            card,
            resolved: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
            quantity: 2
        )
        let row = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CollectedCard>()).first {
                $0.collectionKey == mutation.collectionKey
            }
        )
        row.dateAdded = acquisitionAt
        let inventoryEvents = try context.fetch(FetchDescriptor<InventoryEvent>())
        for event in inventoryEvents where event.collectionKey == mutation.collectionKey {
            event.occurredAt = acquisitionAt
            event.recordedAt = acquisitionAt
        }
        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        for activity in activities where activity.collectionKey == mutation.collectionKey {
            activity.occurredAt = acquisitionAt
        }
        try context.save()

        let priceStore = PriceStore(context: context)
        XCTAssertTrue(
            priceStore.store(
                .price(
                    NormalizedPrice(
                        unitMarketPriceUSD: 10,
                        currencyCode: "USD",
                        source: .justTCG,
                        sourceVariantID: "usd-boundary",
                        sourceUpdatedAt: firstPriceAt,
                        fetchedAt: firstPriceAt
                    )
                ),
                game: row.cardGame,
                printingID: row.priceStorageID,
                variantID: row.variantID,
                at: firstPriceAt
            )
        )
        try context.save()

        XCTAssertTrue(
            priceStore.store(
                .price(
                    NormalizedPrice(
                        unitMarketPriceUSD: 12,
                        currencyCode: "EUR",
                        source: .cardmarket,
                        sourceVariantID: "eur-boundary",
                        sourceUpdatedAt: secondPriceAt,
                        fetchedAt: secondPriceAt
                    )
                ),
                game: row.cardGame,
                printingID: row.priceStorageID,
                variantID: row.variantID,
                at: secondPriceAt
            )
        )
        try context.save()

        let current = InventoryLedger(context: context).valuation(forPriceKey: row.priceKey)
        XCTAssertNil(current.unitPrice)
        XCTAssertEqual(
            try XCTUnwrap(
                try context.fetch(FetchDescriptor<PriceObservation>()).last
            ).kind,
            .sourceTransition
        )

        let computation = PortfolioReplaySnapshotBuilder.compute(
            context: context,
            epoch: dayN,
            through: through,
            timeZone: timeZone
        )
        let live = try XCTUnwrap(computation.replay.live)
        let closedDay = try XCTUnwrap(computation.replay.days.first)

        XCTAssertEqual(closedDay.displayDay, dayN)
        XCTAssertEqual(closedDay.closeValue, Money(rounding: 20)!)
        XCTAssertEqual(live.day, nextDay)
        XCTAssertEqual(live.attribution.currentValue, .zero)
        XCTAssertEqual(live.attribution.currentValue, computation.valuation.value)
        XCTAssertEqual(live.attribution.pricingAdjustment, -Money(rounding: 20)!)
        XCTAssertEqual(live.attribution.market, .zero)
        XCTAssertEqual(live.attribution.unexplained, .zero)
        XCTAssertEqual(computation.valuation.otherCurrencyCount, 2)
        XCTAssertEqual(computation.valuation.unpricedCount, 0)
    }

    func testREQ006NonUSDLocalPriceRecordIsCheckingButStillVisible() throws {
        let container = try ModelContainer(
            for: ReferenceQuote.self,
            PriceRecord.self,
            PriceObservation.self,
            PriceCheckDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let scan = try priceCheckScanForREQ006()
        let retrievedAt = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertTrue(
            PriceStore(context: context).store(
                .price(
                    NormalizedPrice(
                        unitMarketPriceUSD: 12,
                        currencyCode: "EUR",
                        source: .cardmarket,
                        sourceVariantID: "cardmarket-reverse",
                        sourceUpdatedAt: retrievedAt,
                        fetchedAt: retrievedAt
                    )
                ),
                game: .pokemon,
                printingID: "req006-printing",
                variantID: PhysicalVariant.reverse.id,
                at: retrievedAt
            )
        )
        try context.save()

        let result = PriceCheckCoordinator(context: context).present(scan)

        XCTAssertEqual(result.quoteState, .checking)
        XCTAssertEqual(result.display.amount, 12)
        XCTAssertEqual(result.display.currencyCode, "EUR")
        XCTAssertTrue(result.shouldAutoRefresh)
    }

    func testREQ006NonUSDReferenceQuoteIsCheckingButStillVisible() throws {
        let container = try ModelContainer(
            for: ReferenceQuote.self,
            PriceRecord.self,
            PriceObservation.self,
            PriceCheckDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let scan = try priceCheckScanForREQ006()
        let retrievedAt = Date(timeIntervalSince1970: 1_800_000_000)

        _ = QuoteCache(context: context).store(
            .price(
                NormalizedPrice(
                    unitMarketPriceUSD: 12,
                    currencyCode: "EUR",
                    source: .cardmarket,
                    sourceVariantID: "cardmarket-reverse",
                    sourceUpdatedAt: retrievedAt,
                    fetchedAt: retrievedAt
                )
            ),
            game: .pokemon,
            printingID: "req006-printing",
            variantID: PhysicalVariant.reverse.id,
        )

        let result = PriceCheckCoordinator(context: context).present(scan)

        XCTAssertEqual(result.quoteState, .checking)
        XCTAssertEqual(result.display.amount, 12)
        XCTAssertEqual(result.display.currencyCode, "EUR")
        XCTAssertTrue(result.shouldAutoRefresh)
    }

    func testREQ006USDLocalEvidenceRemainsCurrent() throws {
        let container = try ModelContainer(
            for: ReferenceQuote.self,
            PriceRecord.self,
            PriceObservation.self,
            PriceCheckDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let scan = try priceCheckScanForREQ006()
        let retrievedAt = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertTrue(
            PriceStore(context: context).store(
                .price(
                    NormalizedPrice(
                        unitMarketPriceUSD: 12,
                        currencyCode: "USD",
                        source: .tcgplayer,
                        sourceVariantID: "normal",
                        sourceUpdatedAt: retrievedAt,
                        fetchedAt: retrievedAt
                    )
                ),
                game: .pokemon,
                printingID: "req006-printing",
                variantID: PhysicalVariant.reverse.id,
                at: retrievedAt
            )
        )
        try context.save()

        let result = PriceCheckCoordinator(context: context).present(scan)

        XCTAssertEqual(result.quoteState, .current)
        XCTAssertEqual(result.display.amount, 12)
        XCTAssertEqual(result.display.currencyCode, "USD")
    }

    func testREQ009AvailableHistoryAnchorIsDisclosed() {
        let timeZone = TimeZone(identifier: "UTC")!
        let calendar = PortfolioCalendar.calendar(in: timeZone)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let requestedStart = PortfolioHistoryRange.oneWeek.requestedStart(
            now: now,
            calendar: calendar,
            earliest: nil
        )
        let oldDate = calendar.date(byAdding: .day, value: -14, to: requestedStart)!
        let result = PortfolioHistoryEngine.calculate(
            input: PortfolioHistoryInput(
                closes: [portfolioClose(for: oldDate, value: 42)],
                summary: PortfolioSummary(),
                epoch: nil,
                timeZoneIdentifier: timeZone.identifier,
                now: now
            ),
            range: .oneWeek
        )

        XCTAssertNotNil(result.trackingBeganDate)
        XCTAssertLessThan(result.points[0].displayDay, requestedStart)
        let disclosure = PortfolioHistoryDisplay.availableHistoryDisclosure(for: result)
        XCTAssertNotNil(disclosure)
        XCTAssertNotEqual(disclosure, "History is being recorded.")
    }

    func testREQ010LateInventoryTruthRevisionIsClassified() throws {
        let container = try ModelContainer(
            for: PortfolioDailyClose.self, InventoryEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let zone = TimeZone(identifier: "UTC")!
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try XCTUnwrap(
            PortfolioEngine.publish(
                [portfolioReplayDay(for: day, value: 1)],
                timeZone: zone,
                context: context
            )
        )
        let lateEvent = InventoryEvent(
            operationID: UUID(),
            leg: nil,
            kind: .acquire,
            source: .scan,
            collectionKey: "late-inventory",
            priceStorageKey: "pokemon:late-inventory:-",
            deltaQuantity: 1,
            occurredAt: day.addingTimeInterval(3_600),
            recordedAt: try XCTUnwrap(first.publishedAt).addingTimeInterval(1),
            valuation: .unpriced
        )
        context.insert(lateEvent)
        try context.save()

        let revised = try XCTUnwrap(
            PortfolioEngine.publish(
                [portfolioReplayDay(for: day, value: 2)],
                timeZone: zone,
                context: context
            )
        )

        XCTAssertEqual(revised.revision, 2)
        XCTAssertEqual(revised.revisionReason, .lateInventoryTruth)
    }

    func testREQ010OrdinaryRevisionRemainsRecomputed() throws {
        let container = try ModelContainer(
            for: PortfolioDailyClose.self, InventoryEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let zone = TimeZone(identifier: "UTC")!
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try XCTUnwrap(
            PortfolioEngine.publish(
                [portfolioReplayDay(for: day, value: 1)],
                timeZone: zone,
                context: context
            )
        )
        let afterCutoff = InventoryEvent(
            operationID: UUID(),
            leg: nil,
            kind: .acquire,
            source: .scan,
            collectionKey: "ordinary-recompute",
            priceStorageKey: "pokemon:ordinary-recompute:-",
            deltaQuantity: 1,
            occurredAt: PortfolioCalendar.boundary(afterDay: day, in: zone)
                .addingTimeInterval(3_600),
            recordedAt: try XCTUnwrap(first.publishedAt).addingTimeInterval(1),
            valuation: .unpriced
        )
        context.insert(afterCutoff)
        try context.save()

        let revised = try XCTUnwrap(
            PortfolioEngine.publish(
                [portfolioReplayDay(for: day, value: 2)],
                timeZone: zone,
                context: context
            )
        )

        XCTAssertEqual(revised.revision, 2)
        XCTAssertEqual(revised.revisionReason, .recomputed)
    }

    func testREQ010EventAtNextDayBoundaryBelongsToFollowingDay() throws {
        let container = try ModelContainer(
            for: PortfolioDailyClose.self, InventoryEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let zone = TimeZone(identifier: "UTC")!
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try XCTUnwrap(
            PortfolioEngine.publish(
                [portfolioReplayDay(for: day, value: 1)],
                timeZone: zone,
                context: context
            )
        )
        let nextDayBoundary = PortfolioCalendar.boundary(afterDay: day, in: zone)
        context.insert(
            InventoryEvent(
                operationID: UUID(),
                leg: nil,
                kind: .acquire,
                source: .scan,
                collectionKey: "next-day-boundary-event",
                priceStorageKey: "pokemon:next-day-boundary-event:-",
                deltaQuantity: 1,
                occurredAt: nextDayBoundary,
                recordedAt: try XCTUnwrap(first.publishedAt).addingTimeInterval(1),
                valuation: .unpriced
            )
        )
        try context.save()

        let revised = try XCTUnwrap(
            PortfolioEngine.publish(
                [portfolioReplayDay(for: day, value: 2)],
                timeZone: zone,
                context: context
            )
        )

        // Portfolio days are half-open: [day start, next day start). An event
        // exactly at the cutoff belongs to the following accounting day and
        // must not explain a revision of this one.
        XCTAssertEqual(revised.revisionReason, .recomputed)
        XCTAssertNotEqual(revised.revisionReason, .lateInventoryTruth)
    }


    func testRM004PriceOnlyRevisionIgnoresUnrelatedLateEventFromBeforeThatDay() throws {
        let container = try ModelContainer(
            for: PortfolioDailyClose.self, InventoryEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let zone = TimeZone(identifier: "UTC")!
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try XCTUnwrap(
            PortfolioEngine.publish(
                [portfolioReplayDay(for: day, value: 1)],
                timeZone: zone,
                context: context
            )
        )
        context.insert(
            InventoryEvent(
                operationID: UUID(),
                leg: nil,
                kind: .acquire,
                source: .scan,
                collectionKey: "unrelated-earlier-event",
                priceStorageKey: "pokemon:unrelated-earlier-event:-",
                deltaQuantity: 1,
                occurredAt: PortfolioCalendar.day(containing: day, in: zone)
                    .addingTimeInterval(-3_600),
                recordedAt: try XCTUnwrap(first.publishedAt).addingTimeInterval(1),
                valuation: .unpriced
            )
        )
        try context.save()

        let revised = try XCTUnwrap(
            PortfolioEngine.publish(
                [portfolioReplayDay(for: day, value: 2)],
                timeZone: zone,
                context: context
            )
        )

        // RM-004: a price-only close revision must not blame an unrelated
        // late event that predates the day being republished.
        XCTAssertEqual(revised.revisionReason, .recomputed)
        XCTAssertNotEqual(revised.revisionReason, .lateInventoryTruth)
    }

    func testREQ010LegacyCloseWithoutPublicationInstantDoesNotGuessLateTruth() throws {
        let container = try ModelContainer(
            for: PortfolioDailyClose.self, InventoryEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let zone = TimeZone(identifier: "UTC")!
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try XCTUnwrap(
            PortfolioEngine.publish(
                [portfolioReplayDay(for: day, value: 1)],
                timeZone: zone,
                context: context
            )
        )
        // This is the state a pre-publication-schema row has after a
        // lightweight migration: no publication instant is available, so the
        // publisher must not infer one from the accounting day or computedAt.
        first.publishedAt = nil
        first.computedAt = day.addingTimeInterval(100)
        context.insert(
            InventoryEvent(
                operationID: UUID(),
                leg: nil,
                kind: .acquire,
                source: .scan,
                collectionKey: "legacy-publication",
                priceStorageKey: "pokemon:legacy-publication:-",
                deltaQuantity: 1,
                occurredAt: day.addingTimeInterval(3_600),
                recordedAt: day.addingTimeInterval(200),
                valuation: .unpriced
            )
        )
        try context.save()

        let revised = try XCTUnwrap(
            PortfolioEngine.publish(
                [portfolioReplayDay(for: day, value: 2)],
                timeZone: zone,
                context: context
            )
        )

        XCTAssertEqual(revised.revision, 2)
        XCTAssertEqual(revised.revisionReason, .recomputed)
    }

    func testREQ010PublicationTimestampPersistsAcrossContainerReopen() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpusREQ010Persistent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("Portfolio.store")
        let schema = Schema([PortfolioDailyClose.self, InventoryEvent.self])
        let configuration = ModelConfiguration(
            "REQ010Persistent",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )

        let publication = try XCTUnwrap(
            { () throws -> Date? in
                let container = try ModelContainer(for: schema, configurations: configuration)
                let close = try XCTUnwrap(
                    PortfolioEngine.publish(
                        [portfolioReplayDay(for: Date(timeIntervalSince1970: 1_800_000_000), value: 1)],
                        timeZone: TimeZone(identifier: "UTC")!,
                        context: container.mainContext
                    )
                )
                try container.mainContext.save()
                return close.publishedAt
            }()
        )

        let reopened = try ModelContainer(for: schema, configurations: configuration)
        let loaded = try XCTUnwrap(
            try reopened.mainContext.fetch(FetchDescriptor<PortfolioDailyClose>()).first
        )
        XCTAssertEqual(loaded.publishedAt, publication)
    }

    func testREQ011NullPriceBatchReportsMetadataWithoutPricedCount() async throws {
        let container = try ProductionRowFixtures.makeContainer()
        let context = container.mainContext
        let product = SealedProductSummary(
            id: "req011-product",
            name: "REQ-011 Booster Box",
            setName: "REQ-011 Set",
            variantID: "req011-variant",
            marketPriceUSD: nil,
            updatedAt: nil,
            imageURL: nil
        )
        let mutation = try CollectionStore(context: context).addSealed(product, game: .pokemon)
        let row = try XCTUnwrap(CollectionStore(context: context).card(forKey: mutation.collectionKey))
        let suite = "OpusREQ011-null-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = JustTCGV1Client(transport: makeREQ011Transport(defaults: defaults))
        let coordinator = JustTCGRefreshCoordinator(
            client: client,
            syncLedger: JustTCGSyncLedger(defaults: defaults)
        )
        OpusJustTCGURLProtocol.reset(body: Self.nullPriceBatchJSON)
        let owner = marketOwner(for: row)
        let report = await coordinator.refresh(
            [owner],
            game: .pokemon,
            lane: .background,
            applyDetailed: { card, variant, owners in
                PriceRefreshController.applyVendorBatchHitResult(
                    card: card,
                    variant: variant,
                    owners: owners,
                    store: PriceStore(context: context),
                    identities: ProductIdentityStore(context: context),
                    artworkRowsByPriceKey: [row.priceKey: [row]],
                    identityRowsByPriceKey: [row.priceKey: [row]],
                    fetchedAt: Date(timeIntervalSince1970: 1_000)
                )
            },
            checkpoint: { true }
        )
        try context.save()

        var priced = 0
        var changedPrices = false
        PriceRefreshController.accumulateMarketRefreshReport(
            report,
            priced: &priced,
            changedPrices: &changedPrices
        )

        XCTAssertEqual(report.metadataUpdated, 1)
        XCTAssertEqual(report.pricesWritten, 0)
        XCTAssertEqual(priced, 0)
        XCTAssertFalse(changedPrices)
        XCTAssertEqual(row.tcgplayerProductID, "98580")
        XCTAssertNil(PriceStore(context: context).record(forKey: row.priceKey))
    }

    func testREQ011NonNullPriceBatchReportsPricedCountAndChange() async throws {
        let container = try ProductionRowFixtures.makeContainer()
        let context = container.mainContext
        let product = SealedProductSummary(
            id: "req011-priced-product",
            name: "REQ-011 Priced Box",
            setName: "REQ-011 Set",
            variantID: "req011-priced-variant",
            marketPriceUSD: nil,
            updatedAt: nil,
            imageURL: nil
        )
        let mutation = try CollectionStore(context: context).addSealed(product, game: .pokemon)
        let row = try XCTUnwrap(CollectionStore(context: context).card(forKey: mutation.collectionKey))
        let suite = "OpusREQ011-priced-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = JustTCGV1Client(transport: makeREQ011Transport(defaults: defaults))
        let coordinator = JustTCGRefreshCoordinator(
            client: client,
            syncLedger: JustTCGSyncLedger(defaults: defaults)
        )
        OpusJustTCGURLProtocol.reset(body: Self.pricedBatchJSON)
        let owner = marketOwner(for: row)
        let report = await coordinator.refresh(
            [owner],
            game: .pokemon,
            lane: .background,
            applyDetailed: { card, variant, owners in
                PriceRefreshController.applyVendorBatchHitResult(
                    card: card,
                    variant: variant,
                    owners: owners,
                    store: PriceStore(context: context),
                    identities: ProductIdentityStore(context: context),
                    artworkRowsByPriceKey: [row.priceKey: [row]],
                    identityRowsByPriceKey: [row.priceKey: [row]],
                    fetchedAt: Date(timeIntervalSince1970: 1_000)
                )
            },
            checkpoint: { true }
        )
        try context.save()

        var priced = 0
        var changedPrices = false
        PriceRefreshController.accumulateMarketRefreshReport(
            report,
            priced: &priced,
            changedPrices: &changedPrices
        )

        XCTAssertEqual(report.metadataUpdated, 1)
        XCTAssertEqual(report.pricesWritten, 1)
        XCTAssertEqual(priced, 1)
        XCTAssertTrue(changedPrices)
        XCTAssertEqual(PriceStore(context: context).record(forKey: row.priceKey)?.unitMarketPriceUSD, 25)
    }

    func testREQ012OrdinaryFailureClearsInvalidQuoteDiagnosisWithoutChangingAmount() throws {
        let container = try ModelContainer(
            for: CollectedCard.self, PriceRecord.self, PriceObservation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let card = try ProductionRowFixtures.pokemonCard()
        let row = CollectedCard(
            collectionKey: card.providerID,
            game: card.game,
            providerID: card.providerID,
            name: card.name,
            setName: card.setName,
            setCode: card.setCode,
            cardNumber: card.cardNumber,
            rarity: card.rarity,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .reverse,
            variantResolution: .userConfirmed
        )
        context.insert(row)
        let store = PriceStore(context: context)
        let checkedAt = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(store.store(
            .price(NormalizedPrice(
                unitMarketPriceUSD: 17,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "valid",
                sourceUpdatedAt: checkedAt,
                fetchedAt: checkedAt
            )),
            game: .pokemon,
            printingID: row.priceStorageID,
            variantID: row.variantID,
            at: checkedAt
        ))
        XCTAssertFalse(store.store(
            .price(NormalizedPrice(
                unitMarketPriceUSD: .nan,
                currencyCode: "USD",
                source: .justTCG,
                sourceVariantID: "invalid",
                sourceUpdatedAt: checkedAt.addingTimeInterval(1),
                fetchedAt: checkedAt.addingTimeInterval(1)
            )),
            game: .pokemon,
            printingID: row.priceStorageID,
            variantID: row.variantID,
            at: checkedAt.addingTimeInterval(1)
        ))
        let record = try XCTUnwrap(store.record(forKey: row.priceKey))
        let amount = record.unitMarketPriceUSD
        XCTAssertEqual(
            record.lastFailureReasonRaw,
            PricingDiagnosticReason.invalidProviderQuote.rawValue
        )

        XCTAssertTrue(store.recordFailure(
            game: .pokemon,
            printingID: row.priceStorageID,
            variantID: row.variantID,
            at: checkedAt.addingTimeInterval(2)
        ))

        XCTAssertNotEqual(
            PricingDiagnostics.unpricedReason(for: row, record: record),
            .invalidProviderQuote
        )
        XCTAssertEqual(record.unitMarketPriceUSD, amount)
    }

    func testREQ013ImportedSealedRowConvergesWithBrowseAdd() async throws {
        let container = try ModelContainer(
            for: CollectedCard.self, PriceRecord.self, ProductIdentity.self,
            CollectionActivity.self, InventoryEvent.self, PriceObservation.self,
            PriceCheckDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let csv = """
        game,provider_id,card_name,set_name,set_code,card_number,quantity,item_kind,grading_company,grade,grade_label,certification_number
        pokemon,csv:REQ-013 Set|REQ-013 Booster Box,REQ-013 Booster Box,REQ-013 Set,,,2,sealedProduct,,,,
        """
        let plan = try CollectionCSV.parse(Data(csv.utf8))
        _ = try CollectionCSV.apply(plan, to: context)
        let imported = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CollectedCard>()).first
        )
        XCTAssertNil(imported.justTCGCardID)
        XCTAssertNil(imported.justTCGVariantID)
        let importedPriceKey = imported.priceKey
        let importedPriceDate = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(
            PriceStore(context: context).store(
                .price(
                    NormalizedPrice(
                        unitMarketPriceUSD: 18,
                        currencyCode: "USD",
                        source: .importedCSV,
                        sourceVariantID: "req013-imported",
                        sourceUpdatedAt: importedPriceDate,
                        fetchedAt: importedPriceDate
                    )
                ),
                game: imported.cardGame,
                printingID: imported.priceStorageID,
                variantID: imported.variantID,
                at: importedPriceDate
            )
        )
        try context.save()

        let suite = "OpusREQ013-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            PriceVendorCredentials.remove()
        }
        try PriceVendorCredentials.store("opus-req-013-key")
        OpusJustTCGURLProtocol.reset(routes: [
            "sets": """
            {"data":[{"id":"req013-set","name":"REQ-013 Set","sealed_count":1}]}
            """,
            "sealed": """
            {"data":[{"id":"req013-booster-box-slug","uuid":"req013-product","name":"REQ-013 Booster Box","set":"req013-set","set_name":"REQ-013 Set","variants":[{"uuid":"req013-variant","condition":"Sealed","price":null}]}],"meta":{"total":1,"limit":100,"offset":0,"hasMore":false}}
            """
        ])
        let normalizer = CollectionCatalogNormalizer(
            tcgdex: EmptyTCGdexSource(),
            justTCG: JustTCGV1Client(transport: makeREQ013Transport(defaults: defaults))
        )
        await normalizer.normalizeImportedCards(in: context)

        let product = SealedProductSummary(
            id: "req013-product",
            name: "REQ-013 Booster Box",
            setName: "REQ-013 Set",
            variantID: "req013-variant",
            marketPriceUSD: nil,
            updatedAt: nil,
            imageURL: nil
        )
        _ = try CollectionStore(context: context).addSealed(product, game: .pokemon)
        let rows = try context.fetch(FetchDescriptor<CollectedCard>())
        let productRows = rows.filter {
            $0.justTCGCardID == product.id && $0.justTCGVariantID == product.variantID
        }
        let row = try XCTUnwrap(productRows.first)
        XCTAssertEqual(productRows.count, 1)
        XCTAssertEqual(row.quantity, 3)
        XCTAssertEqual(CatalogOwnershipIndex(rows: rows.map(CatalogOwnershipCardSnapshot.init))
            .sealedQuantity(productID: product.id, variantID: product.variantID), 3)
        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
            .filter { $0.collectionKey == row.collectionKey }
        XCTAssertEqual(activities.reduce(0) { $0 + $1.deltaQuantity }, 3)
        let priceRecords = try context.fetch(FetchDescriptor<PriceRecord>())
        XCTAssertEqual(priceRecords.filter { $0.key == row.priceKey }.count, 1)
        if importedPriceKey != row.priceKey {
            XCTAssertFalse(priceRecords.contains { $0.key == importedPriceKey })
        }
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<PriceObservation>())
                .allSatisfy { $0.instrumentKey == row.priceKey }
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<PriceCheckDay>())
                .allSatisfy { $0.instrumentKey == row.priceKey }
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<InventoryEvent>())
                .allSatisfy { $0.priceStorageKey == row.priceKey }
        )
    }

    func testREQ014BackfillRunsForASecondStoreDespiteSharedDefaultsAndIsIdempotent() throws {
        let suite = "OpusREQ014-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let firstContainer = try backfillTestContainer()
        let firstContext = firstContainer.mainContext
        let firstCard = backfillTestCard(key: "req014-first", quantity: 2)
        firstContext.insert(firstCard)
        try firstContext.save()
        try CollectionStore(context: firstContext)
            .backfillExistingCollectionIfNeeded(defaults: defaults)
        XCTAssertEqual(try firstContext.fetch(FetchDescriptor<CollectionActivity>()).count, 1)

        let secondContainer = try backfillTestContainer()
        let secondContext = secondContainer.mainContext
        let secondCard = backfillTestCard(key: "req014-second", quantity: 3)
        secondContext.insert(secondCard)
        try secondContext.save()
        let store = CollectionStore(context: secondContext)
        try store.backfillExistingCollectionIfNeeded(defaults: defaults)
        let firstRun = try secondContext.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertEqual(firstRun.count, 1)
        XCTAssertEqual(firstRun.first?.kind, .added)
        XCTAssertEqual(firstRun.first?.deltaQuantity, secondCard.quantity)

        try store.backfillExistingCollectionIfNeeded(defaults: defaults)
        XCTAssertEqual(
            try secondContext.fetch(FetchDescriptor<CollectionActivity>()).count,
            firstRun.count
        )

        let anchor = try XCTUnwrap(secondCard.activityBackfillAnchor)
        let deletedAnchorID = anchor.id
        secondContext.delete(anchor)
        try secondContext.save()
        XCTAssertNil(secondCard.activityBackfillAnchor)
        try store.backfillExistingCollectionIfNeeded(defaults: defaults)
        XCTAssertEqual(
            try secondContext.fetch(FetchDescriptor<CollectionActivity>()).count,
            firstRun.count
        )
        let repairedAnchor = try XCTUnwrap(secondCard.activityBackfillAnchor)
        XCTAssertNotEqual(repairedAnchor.id, deletedAnchorID)
        XCTAssertTrue(
            try secondContext.fetch(FetchDescriptor<CollectionActivity>())
                .contains { $0.id == repairedAnchor.id }
        )
    }

    func testREQ014BackfillWatermarkSurvivesPersistentContainerReopen() throws {
        let suite = "OpusREQ014Persistent-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpusREQ014Persistent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("Collection.store")

        let firstContainer = try backfillPersistentContainer(at: url)
        let firstContext = firstContainer.mainContext
        let firstCard = backfillTestCard(key: "req014-persistent", quantity: 4)
        firstContext.insert(firstCard)
        try firstContext.save()
        try CollectionStore(context: firstContext)
            .backfillExistingCollectionIfNeeded(defaults: defaults)
        let firstKey = CollectionStore.existingCollectionBackfillVersionKey(
            for: firstContainer
        )
        XCTAssertEqual(
            try firstContext.fetch(FetchDescriptor<CollectionActivity>()).count,
            1
        )
        XCTAssertEqual(firstCard.activityBackfillVersion, 1)
        XCTAssertNotNil(firstCard.activityBackfillAnchor)

        let secondContainer = try backfillPersistentContainer(at: url)
        let secondContext = secondContainer.mainContext
        let secondKey = CollectionStore.existingCollectionBackfillVersionKey(
            for: secondContainer
        )
        XCTAssertEqual(secondKey, firstKey)
        let persistedCard = try XCTUnwrap(
            try secondContext.fetch(FetchDescriptor<CollectedCard>()).first
        )
        XCTAssertEqual(persistedCard.activityBackfillVersion, 1)
        XCTAssertNotNil(persistedCard.activityBackfillAnchor)
        let before = try secondContext.fetch(FetchDescriptor<CollectionActivity>()).count
        try CollectionStore(context: secondContext)
            .backfillExistingCollectionIfNeeded(defaults: defaults)
        XCTAssertEqual(
            try secondContext.fetch(FetchDescriptor<CollectionActivity>()).count,
            before
        )
    }

    func testREQ015FutureCacheEnvelopeIsReturnedButNotFresh() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpusREQ015-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let set = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "req015"),
            name: "REQ-015 Set",
            code: "REQ15",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 1,
            releaseDate: nil,
            sortRank: 0
        )
        let url = root.appendingPathComponent("Sets-pokemon.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(
            TestCacheEnvelope(storedAt: Date.now.addingTimeInterval(3_600), value: [set])
        ).write(to: url)

        let loaded = await CatalogCacheStore(root: root).sets(for: .pokemon)
        XCTAssertNotNil(loaded?.value)
        XCTAssertFalse(loaded?.isFresh ?? true)
    }

    func testREQ015RecentCacheEnvelopeRemainsFresh() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpusREQ015-recent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let set = CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: "req015-recent"),
            name: "REQ-015 Recent Set",
            code: "REQ15R",
            logoURL: nil,
            symbolURL: nil,
            cardCount: 1,
            releaseDate: nil,
            sortRank: 0
        )
        let url = root.appendingPathComponent("Sets-pokemon.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(
            TestCacheEnvelope(storedAt: Date.now.addingTimeInterval(-60), value: [set])
        ).write(to: url)

        let loaded = await CatalogCacheStore(root: root).sets(for: .pokemon)
        XCTAssertTrue(loaded?.isFresh ?? false)
    }

    private func priceCheckScanForREQ006() throws -> ResolvedScan {
        let card = TCGdexCard(
            id: "req006-printing",
            localId: "074",
            name: "REQ-006 Example",
            image: nil,
            rarity: nil,
            set: TCGdexSetBrief(
                id: "req006-set",
                name: "REQ-006 Set",
                cardCount: TCGdexCardCount(total: 180, official: 180)
            ),
            variants: nil,
            pricing: nil,
            variantsDetailed: nil
        )
        let identifier = ScanIdentifier.pokemon(
            setCode: "REQ6",
            cardNumber: "074",
            printedTotal: 180,
            setDefinition: PokemonSetDefinition(
                printedCode: "REQ6",
                tcgdexSetID: "req006-set",
                officialCount: 180,
                releaseIndex: 0
            )
        )
        return ResolvedScan(
            request: ScanRequest(
                subject: ScanSubject(identifier: identifier),
                purpose: .priceCheck,
                generation: 0
            ),
            card: .pokemon(card, setCode: "REQ6"),
            resolved: ResolvedVariant(
                variant: .reverse,
                resolution: .userConfirmed
            ),
            pokemonPrintRun: nil,
            options: [.reverse],
            catalogRetrievedAt: Date(timeIntervalSince1970: 1_700_000_000),
            gradedOutcome: nil
        )
    }

#if DEBUG
    func testREQ008EveryRecognitionDiscontinuityClearsSlabState() {
        let evidence = GradedSlabEvidence(
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            certificationNumber: "REQ008-CERT",
            labelCardText: ["CHARIZARD"]
        )
        let raw = ScanSubject(identifier: .pokemon(
            setCode: "OBF",
            cardNumber: "223",
            printedTotal: SetCodeMap.definitions["OBF"]!.officialCount,
            setDefinition: SetCodeMap.definitions["OBF"]!
        ))

        let endSessionScanner = CardScanner()
        XCTAssertNil(endSessionScanner.receiveSlabLabelEvidenceForTesting(
            evidence,
            footerHasText: true,
            at: 0
        ))
        XCTAssertEqual(endSessionScanner.receiveSlabLabelEvidenceForTesting(
            evidence,
            footerHasText: true,
            at: 1.5
        ), evidence)
        endSessionScanner.endSession()
        endSessionScanner.drainVisionQueueForTesting()
        endSessionScanner.receiveFooterOutcomeForTesting(.identified(raw), at: 2)
        endSessionScanner.receiveFooterOutcomeForTesting(.identified(raw), at: 2.25)
        XCTAssertEqual(endSessionScanner.latchedSubjectForTesting, raw)
        XCTAssertNil(endSessionScanner.latchedSubjectForTesting?.slab)

        let stopScanner = CardScanner()
        XCTAssertNil(stopScanner.receiveSlabLabelEvidenceForTesting(
            evidence,
            footerHasText: true,
            at: 0
        ))
        XCTAssertEqual(stopScanner.receiveSlabLabelEvidenceForTesting(
            evidence,
            footerHasText: true,
            at: 1.5
        ), evidence)
        stopScanner.stop()
        stopScanner.drainVisionQueueForTesting()
        stopScanner.receiveFooterOutcomeForTesting(.identified(raw), at: 2)
        stopScanner.receiveFooterOutcomeForTesting(.identified(raw), at: 2.25)
        XCTAssertEqual(stopScanner.latchedSubjectForTesting, raw)
        XCTAssertNil(stopScanner.latchedSubjectForTesting?.slab)

        let invalidationScanner = CardScanner()
        XCTAssertNil(invalidationScanner.receiveSlabLabelEvidenceForTesting(
            evidence,
            footerHasText: true,
            at: 0
        ))
        XCTAssertEqual(invalidationScanner.receiveSlabLabelEvidenceForTesting(
            evidence,
            footerHasText: true,
            at: 1.5
        ), evidence)
        invalidationScanner.invalidateSpatialContinuity()
        invalidationScanner.drainVisionQueueForTesting()
        invalidationScanner.receiveFooterOutcomeForTesting(.identified(raw), at: 2)
        invalidationScanner.receiveFooterOutcomeForTesting(.identified(raw), at: 2.25)
        XCTAssertEqual(invalidationScanner.latchedSubjectForTesting, raw)
        XCTAssertNil(invalidationScanner.latchedSubjectForTesting?.slab)
    }

    func testREQ007BrokenContinuityCannotBindLabelToDifferentFooter() {
        let scanner = CardScanner()
        let evidence = GradedSlabEvidence(
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            certificationNumber: "REQ007-CERT",
            labelCardText: ["CHARIZARD"]
        )
        let different = ScanSubject(identifier: .pokemon(
            setCode: "OBF",
            cardNumber: "224",
            printedTotal: SetCodeMap.definitions["OBF"]!.officialCount,
            setDefinition: SetCodeMap.definitions["OBF"]!
        ))
        XCTAssertNil(scanner.receiveSlabLabelEvidenceForTesting(
            evidence,
            footerHasText: true,
            at: 0
        ))
        XCTAssertEqual(scanner.receiveSlabLabelEvidenceForTesting(
            evidence,
            footerHasText: true,
            at: 1.5
        ), evidence)

        scanner.invalidateSpatialContinuity()
        scanner.drainVisionQueueForTesting()
        var emitted: ScanSubject?
        let confirmed = expectation(description: "different footer is emitted without stale slab")
        scanner.onConfirmedSubjectCandidate = { _, _, subject, _ in
            emitted = subject
            confirmed.fulfill()
        }
        scanner.receiveFooterOutcomeForTesting(.identified(different), at: 2)
        scanner.receiveFooterOutcomeForTesting(.identified(different), at: 2.25)
        wait(for: [confirmed], timeout: 1)

        XCTAssertEqual(emitted?.identifier, different.identifier)
        XCTAssertNil(emitted?.slab)
    }

    func testREQ007ContinuousLabelFirstBootstrapBindsOriginalSlab() {
        let scanner = CardScanner()
        let evidence = GradedSlabEvidence(
            company: .bgs,
            grade: CardGrade(value: "9.5", label: "Gem Mint"),
            certificationNumber: "REQ007-POSITIVE",
            labelCardText: ["PIKACHU"]
        )
        let identifier = ScanIdentifier.pokemon(
            setCode: "OBF",
            cardNumber: "223",
            printedTotal: SetCodeMap.definitions["OBF"]!.officialCount,
            setDefinition: SetCodeMap.definitions["OBF"]!
        )
        XCTAssertNil(scanner.receiveSlabLabelEvidenceForTesting(
            evidence,
            footerHasText: true,
            at: 0
        ))
        XCTAssertEqual(scanner.receiveSlabLabelEvidenceForTesting(
            evidence,
            footerHasText: true,
            at: 1.5
        ), evidence)

        var emitted: ScanSubject?
        let confirmed = expectation(description: "same footer binds the original slab")
        scanner.onConfirmedSubjectCandidate = { _, _, subject, _ in
            emitted = subject
            confirmed.fulfill()
        }
        let subject = ScanSubject(identifier: identifier)
        scanner.receiveFooterOutcomeForTesting(.identified(subject), at: 2)
        scanner.receiveFooterOutcomeForTesting(.identified(subject), at: 2.25)
        wait(for: [confirmed], timeout: 1)

        XCTAssertEqual(emitted?.identifier, identifier)
        XCTAssertEqual(emitted?.slab, evidence)
    }

    func testRM003FrameLevelTrackerLossPreservesBoundSlabEvidence() {
        let scanner = CardScanner()
        let evidence = GradedSlabEvidence(
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            certificationNumber: "RM003-PRESERVE",
            labelCardText: ["CHARIZARD"]
        )
        let identifier = ScanIdentifier.pokemon(
            setCode: "OBF",
            cardNumber: "223",
            printedTotal: SetCodeMap.definitions["OBF"]!.officialCount,
            setDefinition: SetCodeMap.definitions["OBF"]!
        )

        XCTAssertNil(scanner.receiveSlabLabelEvidenceForTesting(
            evidence,
            footerHasText: true,
            at: 0
        ))
        XCTAssertEqual(scanner.receiveSlabLabelEvidenceForTesting(
            evidence,
            footerHasText: true,
            at: 1.5
        ), evidence)
        scanner.receiveSlabFooterPresenceForTesting(
            identifier: identifier,
            hasText: true,
            at: 2
        )

        // RM-003: this is the shared production transition for a frame with
        // no tracker observation or sub-threshold tracker confidence.
        scanner.receiveTrackerContinuityLossForTesting()
        let subject = ScanSubject(identifier: identifier)
        scanner.receiveFooterOutcomeForTesting(.identified(subject), at: 2.25)
        scanner.receiveFooterOutcomeForTesting(.identified(subject), at: 2.5)

        XCTAssertEqual(scanner.latchedSubjectForTesting?.identifier, identifier)
        XCTAssertEqual(scanner.latchedSubjectForTesting?.slab, evidence)
    }

    func testRM003FrameLevelTrackerLossRejectsDifferentFooterIdentity() {
        let scanner = CardScanner()
        let evidence = GradedSlabEvidence(
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            certificationNumber: "RM003-REJECT",
            labelCardText: ["CHARIZARD"]
        )
        let original = ScanIdentifier.pokemon(
            setCode: "OBF",
            cardNumber: "223",
            printedTotal: SetCodeMap.definitions["OBF"]!.officialCount,
            setDefinition: SetCodeMap.definitions["OBF"]!
        )
        let different = ScanIdentifier.pokemon(
            setCode: "OBF",
            cardNumber: "224",
            printedTotal: SetCodeMap.definitions["OBF"]!.officialCount,
            setDefinition: SetCodeMap.definitions["OBF"]!
        )

        XCTAssertNil(scanner.receiveSlabLabelEvidenceForTesting(
            evidence,
            footerHasText: true,
            at: 0
        ))
        XCTAssertEqual(scanner.receiveSlabLabelEvidenceForTesting(
            evidence,
            footerHasText: true,
            at: 1.5
        ), evidence)
        scanner.receiveSlabFooterPresenceForTesting(
            identifier: original,
            hasText: true,
            at: 2
        )
        scanner.receiveTrackerContinuityLossForTesting()

        var emitted: ScanSubject?
        let confirmed = expectation(description: "different footer is emitted without stale slab")
        scanner.onConfirmedSubjectCandidate = { _, _, subject, _ in
            emitted = subject
            confirmed.fulfill()
        }
        let subject = ScanSubject(identifier: different)
        scanner.receiveFooterOutcomeForTesting(.identified(subject), at: 2.25)
        scanner.receiveFooterOutcomeForTesting(.identified(subject), at: 2.5)
        wait(for: [confirmed], timeout: 1)

        XCTAssertEqual(emitted?.identifier, different)
        XCTAssertNil(emitted?.slab)
    }

    func testRM008FrameLevelTrackerLossPreservesLateSlabBinding() {
        let scanner = CardScanner()
        let evidence = GradedSlabEvidence(
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            certificationNumber: "RM008-LATE-BIND",
            labelCardText: ["CHARIZARD"]
        )
        let identifier = ScanIdentifier.pokemon(
            setCode: "OBF",
            cardNumber: "223",
            printedTotal: SetCodeMap.definitions["OBF"]!.officialCount,
            setDefinition: SetCodeMap.definitions["OBF"]!
        )

        XCTAssertNil(scanner.receiveSlabLabelEvidenceForTesting(
            evidence,
            footerHasText: true,
            at: 0
        ))
        XCTAssertEqual(scanner.receiveSlabLabelEvidenceForTesting(
            evidence,
            footerHasText: true,
            at: 1.5
        ), evidence)

        // No footer presence confirmation occurred before tracker continuity
        // was lost. The label-first slab has already earned two matching label
        // passes, so ordinary frame-level tracker noise must not discard it
        // before the temporarily unreadable footer can bind.
        scanner.receiveTrackerContinuityLossForTesting()

        var emitted: ScanSubject?
        let confirmed = expectation(description: "late footer is emitted with preserved slab evidence")
        scanner.onConfirmedSubjectCandidate = { _, _, subject, _ in
            emitted = subject
            confirmed.fulfill()
        }
        let subject = ScanSubject(identifier: identifier)
        scanner.receiveFooterOutcomeForTesting(.identified(subject), at: 2)
        scanner.receiveFooterOutcomeForTesting(.identified(subject), at: 2.25)
        wait(for: [confirmed], timeout: 1)

        XCTAssertEqual(emitted?.identifier, identifier)
        XCTAssertEqual(emitted?.slab, evidence)
        XCTAssertEqual(scanner.latchedSubjectForTesting?.slab, evidence)
    }

#endif

    private func portfolioClose(for date: Date, value: Int) -> PortfolioPublishedClose {
        PortfolioPublishedClose(
            date: date,
            revision: 1,
            timeZoneIdentifier: "UTC",
            closeValue: money(value),
            market: .zero,
            flow: .zero,
            corrections: .zero,
            pricingAdjustment: .zero,
            carriedForwardValue: .zero,
            coverage: .complete,
            refreshedInstrumentCount: 0,
            carriedForwardInstrumentCount: 0,
            pricedPositionCount: 0,
            excludedCount: 0,
            revisionReason: nil
        )
    }

    private func portfolioReplayDay(for date: Date, value: Int) -> PortfolioReplayDay {
        let zone = TimeZone(identifier: "UTC")!
        return PortfolioReplayDay(
            displayDay: date,
            boundary: PortfolioCalendar.boundary(afterDay: date, in: zone),
            closeValue: money(value),
            market: .zero,
            added: .zero,
            removed: .zero,
            corrections: .zero,
            newlyAddedValue: .zero,
            pricingAdjustment: .zero,
            performanceFactor: nil,
            pricedPositionCount: 0,
            excludedQuantity: 0,
            coverage: PortfolioCoverage(state: .complete),
            carriedForwardValue: .zero,
            contributions: [:],
            movementDetails: [:],
            hasEligibleMarketMovement: false
        )
    }

    private func money(_ dollars: Int) -> Money {
        Money(rounding: Double(dollars))!
    }

    private func backfillTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: CollectedCard.self, CollectionActivity.self, InventoryEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func backfillPersistentContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema([
            CollectedCard.self,
            CollectionActivity.self,
            InventoryEvent.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                "REQ014Persistent",
                schema: schema,
                url: url,
                cloudKitDatabase: .none
            )
        )
    }

    private func backfillTestCard(key: String, quantity: Int) -> CollectedCard {
        CollectedCard(
            collectionKey: key,
            game: .pokemon,
            providerID: key,
            name: "REQ-014 Card",
            setName: "REQ-014 Set",
            setCode: "REQ14",
            cardNumber: "001",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .normal,
            variantResolution: .imported,
            quantity: quantity
        )
    }

    private func makeREQ011Transport(defaults: UserDefaults) -> JustTCGTransport {
        var configuration = JustTCGTransport.Configuration()
        configuration.baseURL = URL(string: "https://opus-req011.test")!
        configuration.minimumRequestInterval = 0
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [OpusJustTCGURLProtocol.self]
        return JustTCGTransport(
            configuration: configuration,
            session: URLSession(configuration: sessionConfiguration),
            ledger: JustTCGRequestLedger(defaults: defaults),
            pacer: JustTCGPacer(),
            apiKeyOverride: "opus-req011-key"
        )
    }

    private func makeREQ013Transport(defaults: UserDefaults) -> JustTCGTransport {
        var configuration = JustTCGTransport.Configuration()
        configuration.baseURL = URL(string: "https://opus-req013.test")!
        configuration.minimumRequestInterval = 0
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [OpusJustTCGURLProtocol.self]
        return JustTCGTransport(
            configuration: configuration,
            session: URLSession(configuration: sessionConfiguration),
            ledger: JustTCGRequestLedger(defaults: defaults),
            pacer: JustTCGPacer(),
            apiKeyOverride: "opus-req013-key"
        )
    }

    private func marketOwner(for row: CollectedCard) -> MarketPriceTarget {
        MarketPriceTarget(
            priceKey: row.priceKey,
            game: row.cardGame,
            printingID: row.priceStorageID,
            variantID: row.variantID,
            itemKind: .sealedProduct,
            marketVariantID: row.justTCGVariantID,
            lookupCandidates: [],
            currentAmount: nil,
            lastCheckedAt: nil
        )
    }

    private static let nullPriceBatchJSON = """
    {"data":[{"id":"req011-box","uuid":"req011-product","tcgplayerId":"98580","variants":[{"uuid":"req011-variant","condition":"Sealed","price":null}]}]}
    """

    private static let pricedBatchJSON = """
    {"data":[{"id":"req011-priced-box","uuid":"req011-priced-product","tcgplayerId":"98581","variants":[{"uuid":"req011-priced-variant","condition":"Sealed","price":25}]}]}
    """
}

final class CardCenteringGroundTruthTests: XCTestCase {
    private let fixtureNames = [
        "IMG_0347", "IMG_0348", "IMG_0349", "IMG_0350", "IMG_0351",
        "IMG_0352", "IMG_0780", "IMG_0781", "IMG_0782", "IMG_0783"
    ]

    private var repositoryURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func requireVerifiedGroundTruth(
        _ record: GroundTruthRecord,
        _ name: String
    ) throws {
        guard record.provenance.method != "provisional_five_pixel_grid_estimate" else {
            throw XCTSkip(
                "\(name) ground truth is provisional; re-annotation is required before accuracy claims."
            )
        }
    }

    func testRealFixturesAndGroundTruthAreReachableFromTheTestBundle() throws {
        let bundle = Bundle(for: CardCenteringGroundTruthTests.self)

        for name in fixtureNames {
            let imageURL = try XCTUnwrap(
                bundle.url(forResource: name, withExtension: "HEIC", subdirectory: "TradingCards/HEIC"),
                "missing HEIC fixture \(name)"
            )
            XCTAssertGreaterThan(try Data(contentsOf: imageURL).count, 0)

            let groundTruthURL = try XCTUnwrap(
                bundle.url(forResource: "\(name).gt", withExtension: "json", subdirectory: "TradingCards/GroundTruth"),
                "missing ground truth \(name)"
            )
            XCTAssertGreaterThan(try Data(contentsOf: groundTruthURL).count, 0)
        }
    }

    func testGroundTruthRecordsConformToSchemaAndGeometryContract() throws {
        let bundle = Bundle(for: CardCenteringGroundTruthTests.self)

        for name in fixtureNames {
            let url = try XCTUnwrap(
                bundle.url(
                    forResource: "\(name).gt",
                    withExtension: "json",
                    subdirectory: "TradingCards/GroundTruth"
                )
            )
            let record = try JSONDecoder().decode(
                GroundTruthRecord.self,
                from: Data(contentsOf: url)
            )

            XCTAssertEqual(record.schema, 1, name)
            XCTAssertEqual(record.fixture, "\(name).HEIC", name)
            XCTAssertEqual(record.sourcePixelSize, GroundTruthSize(width: 4032, height: 3024), name)
            XCTAssertEqual(record.orientedPixelSize, GroundTruthSize(width: 3024, height: 4032), name)
            XCTAssertEqual(record.exifOrientation, 6, name)
            XCTAssertEqual(record.cardOuterQuad.count, 4, name)
            XCTAssertTrue(record.cardOuterQuad.allSatisfy { $0.count == 2 && $0.allSatisfy { $0.isFinite } }, name)
            XCTAssertEqual(record.edgeBands.count, 4, name)
            XCTAssertTrue(record.edgeBands.allSatisfy { $0.value > 0 }, name)
            XCTAssertTrue(Set(record.ambiguousEdges).isSubset(of: ["left", "top", "right", "bottom"]), name)
            let cardHeight = try XCTUnwrap(CardCenteringQuad(record.cardOuterQuad)).rectifiedHeight
            let agreementTolerance = min(
                max(cardHeight * 0.0025, record.edgeBands.values.min() ?? 0),
                cardHeight * 0.01
            )
            if let agreementPx = record.provenance.agreementPx {
                XCTAssertLessThanOrEqual(agreementPx, agreementTolerance, name)
            } else {
                XCTAssertEqual(record.provenance.method, "provisional_five_pixel_grid_estimate", name)
                XCTAssertEqual(record.provenance.annotators, ["unverified"], name)
            }
            let expectedAmbiguousEdges = Set(record.edgeBands.compactMap { edge, band in
                band > cardHeight * 0.01 ? edge : nil
            })
            XCTAssertEqual(Set(record.ambiguousEdges), expectedAmbiguousEdges, name)

            let outer = try XCTUnwrap(CardCenteringQuad(record.cardOuterQuad))
            XCTAssertEqual(outer.rectifiedAspectRatio, 2.5 / 3.5, accuracy: 0.02, name)
            XCTAssertTrue(record.expected.skewDegrees.isFinite, name)

            if let innerValues = record.innerQuad {
                let inner = try XCTUnwrap(CardCenteringQuad(innerValues))
                XCTAssertNotEqual(record.innerReference, .none, name)
                let distances = outer.borderDistances(to: inner)
                let lr = 100 * distances.left / max(distances.left + distances.right, .ulpOfOne)
                let tb = 100 * distances.top / max(distances.top + distances.bottom, .ulpOfOne)
                XCTAssertEqual(lr, try XCTUnwrap(record.expected.lrRatio), accuracy: 0.25, name)
                XCTAssertEqual(tb, try XCTUnwrap(record.expected.tbRatio), accuracy: 0.25, name)
            } else {
                XCTAssertEqual(record.innerReference, .none, name)
                XCTAssertNil(record.expected.lrRatio, name)
                XCTAssertNil(record.expected.tbRatio, name)
            }
        }
    }

    func testGroundTruthHasVerifiedDualPassSubpixelProvenance() throws {
        let bundle = Bundle(for: CardCenteringGroundTruthTests.self)
        var allCoordinates: [Double] = []

        for name in fixtureNames {
            let url = try XCTUnwrap(
                bundle.url(
                    forResource: "\(name).gt",
                    withExtension: "json",
                    subdirectory: "TradingCards/GroundTruth"
                )
            )
            let record = try JSONDecoder().decode(
                GroundTruthRecord.self,
                from: Data(contentsOf: url)
            )

            XCTAssertFalse(record.provenance.method.hasPrefix("provisional_"), name)
            XCTAssertEqual(
                record.provenance.method,
                "analyzer_free_dual_profile_fit_with_visual_adjudication",
                name
            )
            XCTAssertEqual(
                record.provenance.annotators,
                ["generic_profile_pass_A", "generic_profile_pass_B"],
                name
            )
            XCTAssertNotNil(record.provenance.agreementPx, name)
            XCTAssertGreaterThanOrEqual(record.provenance.agreementPx ?? -.infinity, 0, name)
            XCTAssertTrue(
                record.provenance.notes.localizedCaseInsensitiveContains("analyzer-free") &&
                    record.provenance.notes.localizedCaseInsensitiveContains("physical silhouette"),
                name
            )
            allCoordinates.append(contentsOf: record.cardOuterQuad.flatMap { $0 })
            allCoordinates.append(contentsOf: record.innerQuad?.flatMap { $0 } ?? [])
            allCoordinates.append(contentsOf: record.encasementOuterQuad?.flatMap { $0 } ?? [])
        }

        XCTAssertTrue(
            allCoordinates.contains { abs($0 - $0.rounded()) > 0.0001 },
            "verified ground truth must retain subpixel coordinates"
        )
    }

    func testGroundTruthReviewSheetsArePresentAndStayBelowArtifactLimit() throws {
        let directory = repositoryURL.appendingPathComponent("review/centering-evidence/ground-truth")
        for name in fixtureNames {
            let url = directory.appendingPathComponent("\(name)_gt.png")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), name)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            XCTAssertLessThan(size, 1_500_000, name)
        }
    }

    func testBaselineChecksumManifestCoversTheImmutableBaseline() throws {
        let directory = repositoryURL.appendingPathComponent("review/centering-evidence/baseline-2026-09-11")
        let manifestURL = directory.appendingPathComponent("SHA256SUMS")
        let lines = try String(contentsOf: manifestURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
        XCTAssertFalse(lines.isEmpty)
        var manifestPaths: [String] = []

        for line in lines {
            let parts = String(line).components(separatedBy: "  ")
            guard parts.count == 2 else {
                XCTFail("malformed checksum line: \(line)")
                continue
            }
            let expected = parts[0]
            let relativePath = parts[1]
            manifestPaths.append(relativePath)
            let fileURL = directory.appendingPathComponent(relativePath)
            let data = try Data(contentsOf: fileURL)
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(actual, expected, relativePath)
        }

        let expectedPaths = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .filter { $0 != "SHA256SUMS" }
            .sorted()
        XCTAssertEqual(manifestPaths.sorted(), expectedPaths)
    }

    func testEvidenceTableReferencesEveryFixtureAndRetainedEvidenceDirectories() throws {
        let tableURL = repositoryURL.appendingPathComponent("review/centering-evidence/evidence-table.md")
        let table = try String(contentsOf: tableURL, encoding: .utf8)

        for name in fixtureNames {
            XCTAssertTrue(table.contains("`\(name)`"), name)
            XCTAssertTrue(table.contains("GroundTruth/\(name).gt.json"), name)
            XCTAssertTrue(table.contains("ground-truth/\(name)_gt.png"), name)
        }

        XCTAssertTrue(table.contains("baseline-2026-09-11/baseline.json"))
        XCTAssertTrue(table.contains("after/README.md"))
        XCTAssertTrue(table.contains("DEVICE-PENDING-5"))
    }

    func testCameraOpticsConfigurationRequestsDistortionCorrectionWhenSupported() {
        XCTAssertTrue(
            CenteringCameraOpticsConfiguration(
                lens: .macro,
                geometricDistortionCorrectionSupported: true
            ).requestsGeometricDistortionCorrection
        )
        XCTAssertFalse(
            CenteringCameraOpticsConfiguration(
                lens: .wide,
                geometricDistortionCorrectionSupported: false
            ).requestsGeometricDistortionCorrection
        )
    }

    func testAnalyzerKeepsDevelopmentCandidatesPendingForManualConfirmation() throws {
        let holdouts = ["IMG_0349", "IMG_0782", "IMG_0783", "IMG_0351"]
        let bundle = Bundle(for: CardCenteringGroundTruthTests.self)

        for name in holdouts {
            let imageURL = try XCTUnwrap(
                bundle.url(forResource: name, withExtension: "HEIC", subdirectory: "TradingCards/HEIC")
            )
            let recordURL = try XCTUnwrap(
                bundle.url(forResource: "\(name).gt", withExtension: "json", subdirectory: "TradingCards/GroundTruth")
            )
            let record = try JSONDecoder().decode(
                GroundTruthRecord.self,
                from: Data(contentsOf: recordURL)
            )
            try requireVerifiedGroundTruth(record, name)
            let analysis = try CardCenteringAnalyzer.analyze(Data(contentsOf: imageURL))
            let measurement = analysis.measurement

            if record.innerQuad == nil {
                XCTAssertTrue(measurement.isDeclined, name)
                XCTAssertNil(measurement.geometryInnerQuad, name)
                continue
            }

            XCTAssertTrue(measurement.isDeclined, name)
            XCTAssertTrue(measurement.requiresManualInnerConfirmation, name)
            XCTAssertTrue(measurement.requiresManualOuterConfirmation, name)
            XCTAssertTrue(measurement.requiresManualFrameConfirmation, name)
            XCTAssertEqual(measurement.leftRightCentering, "—", name)
            XCTAssertEqual(measurement.topBottomCentering, "—", name)
            let mapping = try XCTUnwrap(analysis.coordinateMapping, name)
            let outer = mapping.nativeQuad(fromWorking: measurement.geometryOuterQuad)
            XCTAssertNotNil(measurement.geometryInnerQuad, name)
            XCTAssertEqual(outer.rectifiedAspectRatio, 2.5 / 3.5, accuracy: 0.02, name)
        }
    }

    func testFrontArtWindowIsNotReplacedByTheFullCardPrintedBorder() throws {
        let name = "IMG_0780"
        let bundle = Bundle(for: CardCenteringGroundTruthTests.self)
        let imageURL = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "HEIC", subdirectory: "TradingCards/HEIC")
        )
        let recordURL = try XCTUnwrap(
            bundle.url(forResource: "\(name).gt", withExtension: "json", subdirectory: "TradingCards/GroundTruth")
        )
        let record = try JSONDecoder().decode(
            GroundTruthRecord.self,
            from: Data(contentsOf: recordURL)
        )
        try requireVerifiedGroundTruth(record, name)
        let analysis = try CardCenteringAnalyzer.analyze(Data(contentsOf: imageURL))
        let mapping = try XCTUnwrap(analysis.coordinateMapping)
        let inner = try XCTUnwrap(analysis.measurement.geometryInnerQuad)
        let nativeInner = mapping.nativeQuad(fromWorking: inner)
        XCTAssertEqual(analysis.measurement.innerReference, .artWindow)
        XCTAssertTrue(analysis.measurement.requiresManualInnerConfirmation)
        XCTAssertEqual(analysis.measurement.leftRightCentering, "—")
        XCTAssertEqual(analysis.measurement.topBottomCentering, "—")
        XCTAssertNotNil(nativeInner)
    }

    func testPortraitFrontArtWindowUsesTheGradeableInnerReference() throws {
        let name = "IMG_0348"
        let bundle = Bundle(for: CardCenteringGroundTruthTests.self)
        let imageURL = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "HEIC", subdirectory: "TradingCards/HEIC")
        )
        let recordURL = try XCTUnwrap(
            bundle.url(forResource: "\(name).gt", withExtension: "json", subdirectory: "TradingCards/GroundTruth")
        )
        let record = try JSONDecoder().decode(
            GroundTruthRecord.self,
            from: Data(contentsOf: recordURL)
        )
        try requireVerifiedGroundTruth(record, name)
        let analysis = try CardCenteringAnalyzer.analyze(Data(contentsOf: imageURL))
        let mapping = try XCTUnwrap(analysis.coordinateMapping)
        let inner = try XCTUnwrap(analysis.measurement.geometryInnerQuad)
        let innerNative = mapping.nativeQuad(fromWorking: inner)
        XCTAssertEqual(analysis.measurement.innerReference, .artWindow)
        XCTAssertTrue(analysis.measurement.requiresManualInnerConfirmation)
        XCTAssertEqual(analysis.measurement.leftRightCentering, "—")
        XCTAssertEqual(analysis.measurement.topBottomCentering, "—")
        XCTAssertNotNil(innerNative)
    }

    func testMaskFailureDeclinesWithoutAnInnerReference() throws {
        let name = "IMG_0782"
        let bundle = Bundle(for: CardCenteringGroundTruthTests.self)
        let imageURL = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "HEIC", subdirectory: "TradingCards/HEIC")
        )
        let analysis = try CardCenteringAnalyzer.analyze(Data(contentsOf: imageURL))

        XCTAssertTrue(analysis.measurement.isDeclined)
        XCTAssertNil(analysis.measurement.geometryInnerQuad)
        XCTAssertEqual(analysis.measurement.innerReference, .none)
    }

    func testL1PublicPipelineReportsEveryFixtureAndNeverConfidentlyWrong() throws {
        let bundle = Bundle(for: CardCenteringGroundTruthTests.self)
        var pendingInnerCount = 0

        for name in fixtureNames {
            let imageURL = try XCTUnwrap(
                bundle.url(forResource: name, withExtension: "HEIC", subdirectory: "TradingCards/HEIC")
            )
            let recordURL = try XCTUnwrap(
                bundle.url(forResource: "\(name).gt", withExtension: "json", subdirectory: "TradingCards/GroundTruth")
            )
            let record = try JSONDecoder().decode(
                GroundTruthRecord.self,
                from: Data(contentsOf: recordURL)
            )
            try requireVerifiedGroundTruth(record, name)
            let analysis = try CardCenteringAnalyzer.analyze(Data(contentsOf: imageURL))
            let measurement = analysis.measurement
            let mapping = try XCTUnwrap(analysis.coordinateMapping, name)
            XCTAssertEqual(mapping.orientedSourceSize, CardCenteringSize(width: 3024, height: 4032), name)

            if record.innerQuad == nil {
                XCTAssertTrue(measurement.isDeclined, name)
                XCTAssertNil(measurement.geometryInnerQuad, name)
                continue
            }
            XCTAssertTrue(measurement.isDeclined, name)
            XCTAssertNotNil(measurement.declineReason, name)
            XCTAssertEqual(measurement.leftRightCentering, "—", name)
            XCTAssertEqual(measurement.topBottomCentering, "—", name)
            if measurement.requiresManualInnerConfirmation {
                pendingInnerCount += 1
                XCTAssertNotNil(measurement.geometryInnerQuad, name)
            }
        }

        XCTAssertEqual(
            pendingInnerCount,
            9,
            "every gradeable development candidate must be held for explicit inner confirmation"
        )
    }

}

final class CardCenteringInvariantTests: XCTestCase {
    private let holdout = "IMG_0783"
    private let fixtureNames = [
        "IMG_0347", "IMG_0348", "IMG_0349", "IMG_0350", "IMG_0351",
        "IMG_0352", "IMG_0780", "IMG_0781", "IMG_0782", "IMG_0783"
    ]

    private func fixtureData(_ name: String) throws -> Data {
        let bundle = Bundle(for: CardCenteringGroundTruthTests.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "HEIC", subdirectory: "TradingCards/HEIC")
        )
        return try Data(contentsOf: url)
    }

    private func fixtureRecord(_ name: String) throws -> GroundTruthRecord {
        let bundle = Bundle(for: CardCenteringGroundTruthTests.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "\(name).gt", withExtension: "json", subdirectory: "TradingCards/GroundTruth")
        )
        return try JSONDecoder().decode(GroundTruthRecord.self, from: Data(contentsOf: url))
    }

    private func normalisedImage(_ data: Data) throws -> UIImage {
        let source = try XCTUnwrap(UIImage(data: data))
        let scale = min(1, 1_200 / max(source.size.width, source.size.height))
        let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func renderedVariant(
        _ data: Data,
        rotationDegrees: CGFloat = 0,
        mirrorX: Bool = false,
        scale: CGFloat = 1
    ) throws -> Data {
        let image = try normalisedImage(data)
        let sourceSize = image.size
        let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let radians = rotationDegrees * .pi / 180
        let cosine = abs(cos(radians))
        let sine = abs(sin(radians))
        let rotatedSize = CGSize(
            width: cosine * drawSize.width + sine * drawSize.height,
            height: sine * drawSize.width + cosine * drawSize.height
        )
        let margin = max(24, max(rotatedSize.width, rotatedSize.height) * 0.12)
        let canvasSize = CGSize(
            width: ceil(rotatedSize.width + margin * 2),
            height: ceil(rotatedSize.height + margin * 2)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: canvasSize, format: format).image { context in
            UIColor(white: 0.76, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))
            let cg = context.cgContext
            cg.translateBy(x: canvasSize.width / 2, y: canvasSize.height / 2)
            cg.rotate(by: radians)
            cg.scaleBy(x: mirrorX ? -1 : 1, y: 1)
            image.draw(in: CGRect(
                x: -drawSize.width / 2,
                y: -drawSize.height / 2,
                width: drawSize.width,
                height: drawSize.height
            ))
        }
        return try XCTUnwrap(rendered.pngData())
    }

    private enum EXIFVariantError: Error {
        case unsupportedOrientation
        case encodeFailed
        case renderFailed
        case selfCheckFailed(Int)
    }

    private func renderedBitmapBytes(
        _ image: UIImage,
        width: Int,
        height: Int
    ) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return try pixels.withUnsafeMutableBytes { rawBuffer in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw EXIFVariantError.renderFailed
            }

            context.setFillColor(UIColor.black.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIGraphicsPushContext(context)
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            UIGraphicsPopContext()

            return Array(rawBuffer.bindMemory(to: UInt8.self))
        }
    }

    private func maxChannelDelta(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        guard lhs.count == rhs.count else { return Int.max }
        return zip(lhs, rhs).reduce(0) { result, pair in
            max(result, abs(Int(pair.0) - Int(pair.1)))
        }
    }

    private func reencodedVariant(
        _ data: Data,
        exifOrientation: Int
    ) throws -> Data {
        let canonical = try normalisedImage(data)
        let rawOrientation: Int
        switch exifOrientation {
        case 1: rawOrientation = 1
        case 3: rawOrientation = 3
        case 6: rawOrientation = 8
        case 8: rawOrientation = 6
        default: throw EXIFVariantError.unsupportedOrientation
        }
        let canonicalCGImage = try XCTUnwrap(canonical.cgImage)
        let rawCGImage: CGImage
        if exifOrientation == 1 {
            // Preserve the canonical bitmap byte-for-byte for the identity
            // encoding. A Core Image round trip can change color-space and
            // bitmap-provider details enough to move this detector even when
            // a rendered-pixel self-check still looks identical.
            rawCGImage = canonicalCGImage
        } else {
            // Build the inverse EXIF transform with an exact-axis UIKit
            // render. This avoids a Core Image color-space conversion while
            // keeping the raw pixels in the dimensions expected by ImageIO.
            let sourceSize = canonical.size
            let rawSize = rawOrientation == 6 || rawOrientation == 8
                ? CGSize(width: sourceSize.height, height: sourceSize.width)
                : sourceSize
            let radians: CGFloat
            switch rawOrientation {
            case 3: radians = .pi
            case 6: radians = .pi / 2
            case 8: radians = -.pi / 2
            default: radians = 0
            }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let rawImage = UIGraphicsImageRenderer(size: rawSize, format: format).image { context in
                context.cgContext.interpolationQuality = .none
                context.cgContext.translateBy(x: rawSize.width / 2, y: rawSize.height / 2)
                context.cgContext.rotate(by: radians)
                canonical.draw(in: CGRect(
                    x: -sourceSize.width / 2,
                    y: -sourceSize.height / 2,
                    width: sourceSize.width,
                    height: sourceSize.height
                ))
            }
            rawCGImage = try XCTUnwrap(rawImage.cgImage)
        }
        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                output,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        let properties: [CFString: Any] = [kCGImagePropertyOrientation: exifOrientation]
        CGImageDestinationAddImage(destination, rawCGImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw EXIFVariantError.encodeFailed
        }

        let encoded = output as Data
        let decoded = try XCTUnwrap(UIImage(data: encoded))
        let width = try XCTUnwrap(canonical.cgImage).width
        let height = try XCTUnwrap(canonical.cgImage).height
        let expected = try renderedBitmapBytes(canonical, width: width, height: height)
        let actual = try renderedBitmapBytes(decoded, width: width, height: height)
        let maximumDelta = maxChannelDelta(expected, actual)
        guard maximumDelta <= 2 else {
            XCTFail(
                "EXIF \(exifOrientation) self-check failed: maximum displayed channel delta (\(maximumDelta)) > 2"
            )
            throw EXIFVariantError.selfCheckFailed(maximumDelta)
        }
        return encoded
    }

    private func benignCropVariant(_ data: Data, record: GroundTruthRecord) throws -> Data {
        let image = try normalisedImage(data)
        let xScale = image.size.width / 3_024
        let yScale = image.size.height / 4_032
        let points = record.cardOuterQuad.map {
            CGPoint(x: $0[0] * xScale, y: $0[1] * yScale)
        }
        let bounds = points.reduce(into: CGRect.null) { result, point in
            result = result.union(CGRect(origin: point, size: .zero))
        }
        let marginX = bounds.width * 0.08
        let marginY = bounds.height * 0.08
        let padding = max(24, max(marginX, marginY) + 8)
        let canvasSize = CGSize(
            width: image.size.width + padding * 2,
            height: image.size.height + padding * 2
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let canvas = UIGraphicsImageRenderer(size: canvasSize, format: format).image { context in
            UIColor(white: 0.76, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))
            image.draw(in: CGRect(
                x: padding,
                y: padding,
                width: image.size.width,
                height: image.size.height
            ))
        }
        let crop = CGRect(
            x: padding + bounds.minX - marginX,
            y: padding + bounds.minY - marginY,
            width: bounds.width + marginX * 2,
            height: bounds.height + marginY * 2
        ).integral
        let cropped = try XCTUnwrap(canvas.cgImage).cropping(to: crop)
        return try XCTUnwrap(UIImage(cgImage: try XCTUnwrap(cropped)).pngData())
    }

    private func ratios(_ measurement: CardCenteringMeasurement) throws -> (lr: Double, tb: Double) {
        guard !measurement.isDeclined else {
            throw XCTSkip("measurement declined: \(measurement.declineReason ?? "unknown")")
        }
        let lr = try XCTUnwrap(Double(measurement.leftRightCentering.components(separatedBy: " / ").first ?? ""))
        let tb = try XCTUnwrap(Double(measurement.topBottomCentering.components(separatedBy: " / ").first ?? ""))
        return (lr, tb)
    }

    private func confidentRatios(_ data: Data) throws -> (lr: Double, tb: Double) {
        var measurement = try CardCenteringAnalyzer.analyze(data).measurement
        if measurement.requiresManualFrameConfirmation {
            measurement.setManualOuterEdge(\.left, to: measurement.outer.left)
            measurement.setManualInnerEdge(\.left, to: measurement.inner.left)
            measurement.refreshWarnings()
        }
        return try ratios(measurement)
    }

    private func ratioError(_ lhs: (lr: Double, tb: Double), _ rhs: (lr: Double, tb: Double)) -> Double {
        max(abs(lhs.lr - rhs.lr), abs(lhs.tb - rhs.tb))
    }

    func testINV1RepeatedProductionAnalysisIsByteStable() throws {
        let bundle = Bundle(for: CardCenteringGroundTruthTests.self)
        let imageURL = try XCTUnwrap(
            bundle.url(forResource: holdout, withExtension: "HEIC", subdirectory: "TradingCards/HEIC")
        )
        let data = try Data(contentsOf: imageURL)
        let first = try CardCenteringAnalyzer.analyze(data).measurement

        for _ in 0..<4 {
            XCTAssertEqual(
                try CardCenteringAnalyzer.analyze(data).measurement,
                first,
                "repeated production analyses must return identical geometry and confidence"
            )
        }
    }

    func testREQ018DeclinedMeasurementDoesNotExposeARatio() {
        let outer = CardCenteringQuad(
            topLeft: CardCenteringPoint(x: 0, y: 0),
            topRight: CardCenteringPoint(x: 500, y: 0),
            bottomRight: CardCenteringPoint(x: 500, y: 500),
            bottomLeft: CardCenteringPoint(x: 0, y: 500)
        )
        var measurement = CardCenteringMeasurement(
            imageWidth: 500,
            imageHeight: 500,
            outerQuad: outer,
            innerQuad: nil,
            warnings: [],
            innerReference: .none
        )
        measurement.refreshWarnings()

        XCTAssertTrue(measurement.isDeclined)
        XCTAssertEqual(measurement.leftRightCentering, "—")
        XCTAssertEqual(measurement.topBottomCentering, "—")
        XCTAssertNil(measurement.geometryInnerQuad)
        XCTAssertNotNil(measurement.declineReason)
    }

    @MainActor
    func testREQ045AutomaticInnerCandidateRequiresConfirmationBeforeRatio() throws {
        var measurement = try CardCenteringAnalyzer.analyze(
            try fixtureData("IMG_0348")
        ).measurement

        XCTAssertTrue(measurement.requiresManualInnerConfirmation)
        XCTAssertTrue(measurement.requiresManualOuterConfirmation)
        XCTAssertTrue(measurement.requiresManualFrameConfirmation)
        XCTAssertTrue(measurement.isDeclined)
        XCTAssertNotNil(measurement.geometryInnerQuad)
        XCTAssertEqual(measurement.leftRightCentering, "—")
        XCTAssertEqual(measurement.topBottomCentering, "—")

        measurement.setManualOuterEdge(\.left, to: measurement.outer.left + 1)
        measurement.setManualInnerEdge(\.left, to: measurement.inner.left + 1)

        XCTAssertTrue(measurement.requiresManualFrameConfirmation)
        XCTAssertTrue(measurement.isDeclined)
        XCTAssertEqual(measurement.leftRightCentering, "—")
        XCTAssertEqual(measurement.topBottomCentering, "—")

        measurement.refreshWarnings()

        XCTAssertFalse(measurement.requiresManualInnerConfirmation)
        XCTAssertFalse(measurement.requiresManualOuterConfirmation)
        XCTAssertFalse(measurement.requiresManualFrameConfirmation)
        XCTAssertFalse(measurement.isDeclined)
        XCTAssertNotEqual(measurement.leftRightCentering, "—")
        XCTAssertNotEqual(measurement.topBottomCentering, "—")
    }

    func testREQ041AnalysisDiagnosticReportsNamedStageTimings() throws {
        var captured: CardCenteringAnalysisDiagnostic?
        CardCenteringAnalyzer.analysisDiagnosticSink = { captured = $0 }
        defer { CardCenteringAnalyzer.analysisDiagnosticSink = nil }

        _ = try CardCenteringAnalyzer.analyze(try fixtureData(holdout))

        let diagnostic = try XCTUnwrap(captured)
        let encoded = try JSONEncoder().encode(diagnostic)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let timings = try XCTUnwrap(
            object["stageTimings"] as? [String: Any],
            "REQ-041 must expose stage timings through the DEBUG diagnostic"
        )
        let requiredStages = [
            "decodeOrientationDownscale",
            "colorPreparation",
            "visionRequests",
            "scalarFields",
            "outerCandidateRefinement",
            "innerCandidateGeneration",
            "jointSelection",
            "rectification",
            "resultConstruction"
        ]
        for stage in requiredStages {
            XCTAssertNotNil(timings[stage], "missing REQ-041 stage timing: \(stage)")
        }
    }

    func testREQ049AnalysisDiagnosticReportsPositionalConsistency() throws {
        var captured: CardCenteringAnalysisDiagnostic?
        CardCenteringAnalyzer.analysisDiagnosticSink = { captured = $0 }
        defer { CardCenteringAnalyzer.analysisDiagnosticSink = nil }

        _ = try CardCenteringAnalyzer.analyze(try fixtureData(holdout))

        let diagnostic = try XCTUnwrap(captured)
        let positional = try XCTUnwrap(
            diagnostic.positionalConsistency,
            "REQ-049 must report positional ratio evidence when an inner reference exists"
        )
        XCTAssertGreaterThanOrEqual(positional.samples.count, 5)
        XCTAssertTrue(positional.leftRight.firstSpread.isFinite)
        XCTAssertTrue(positional.topBottom.firstSpread.isFinite)

        let encoded = try JSONEncoder().encode(diagnostic)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNotNil(
            object["positionalConsistency"],
            "REQ-049 evidence must survive diagnostic serialization"
        )
    }

#if DEBUG
    func testREQ050NumericalSensitivityParametersAreInjectedWithoutChangingDefaults() throws {
        let defaults = CardCenteringAnalyzer.NumericalParameters.productionDefaults
        let perturbed = defaults.replacing(
            scalarSmoothingRadius: 1,
            scalarPeakThresholdFraction: 0.08,
            profileRadiusNormalized: 0.001,
            profileThresholdFloor: 2.0
        )

        XCTAssertTrue(defaults.isValid)
        XCTAssertTrue(perturbed.isValid)
        XCTAssertNotEqual(defaults, perturbed)
        XCTAssertEqual(
            CardCenteringAnalyzer.NumericalParameters.productionDefaults,
            defaults,
            "sensitivity injection must not mutate the production defaults"
        )

        let invalid = defaults.replacing(profileRadiusNormalized: 0)
        XCTAssertFalse(invalid.isValid)
        XCTAssertThrowsError(
            try CardCenteringAnalyzer.analyzeForSensitivity(Data(), parameters: invalid),
            "invalid sensitivity parameters must be rejected before analysis"
        )
    }
#endif

#if DEBUG
    func testREQ042CandidateLedgerRetainsAllEdgeFamiliesBeforeSelection() throws {
        var captured: CardCenteringCandidateLedgerDiagnostic?
        CardCenteringAnalyzer.candidateLedgerDiagnosticSink = { captured = $0 }
        defer { CardCenteringAnalyzer.candidateLedgerDiagnosticSink = nil }

        _ = try CardCenteringAnalyzer.analyze(try fixtureData(holdout))

        let ledger = try XCTUnwrap(
            captured,
            "REQ-042 must expose a candidate ledger for the analyzer pass"
        )
        let expectedSides = Set(["left", "top", "right", "bottom"])
        for family in ["outer", "inner"] {
            let candidates = ledger.candidates.filter { $0.family == family }
            XCTAssertEqual(
                Set(candidates.map(\.side)),
                expectedSides,
                "REQ-042 must retain (family) candidates for every edge"
            )
        }
        XCTAssertFalse(ledger.candidates.isEmpty)
        for candidate in ledger.candidates {
            XCTAssertFalse(candidate.workingGeometry.isEmpty)
            XCTAssertEqual(candidate.workingGeometry.count, candidate.nativeGeometry.count)
            XCTAssertEqual(candidate.workingGeometry.count, candidate.normalizedGeometry.count)
            XCTAssertTrue(candidate.support.isFinite && candidate.support >= 0)
            XCTAssertTrue(candidate.transitionStrength.isFinite && candidate.transitionStrength >= 0)
            XCTAssertFalse(candidate.proposedSemanticRole.isEmpty)
        }
    }

    func testREQ042CandidateRecallDiagnosticCoversAllFixtures() throws {
        let output = try centeringDiagnosticDirectory("REQ-042")

        func lineDistance(
            _ point: CardCenteringPoint,
            from start: CardCenteringPoint,
            to end: CardCenteringPoint
        ) -> Double {
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = max(hypot(dx, dy), .ulpOfOne)
            return abs(dx * (point.y - start.y) - dy * (point.x - start.x)) / length
        }

        func candidateError(
            _ candidate: CardCenteringCandidateDiagnostic,
            expected: CardCenteringQuad,
            side: String
        ) -> Double? {
            guard let groundTruthSide = GroundTruthSide(rawValue: side),
                  !candidate.nativeGeometry.isEmpty else {
                return nil
            }
            let endpoints = edgeEndpoints(expected, side: groundTruthSide)
            let distances = candidate.nativeGeometry.map {
                lineDistance($0, from: endpoints.0, to: endpoints.1)
            }
            return distances.max()
        }

        func bestRecall(
            family: String,
            side: String,
            candidates: [CardCenteringCandidateDiagnostic],
            expected: CardCenteringQuad?,
            tolerance: Double?
        ) -> REQ042CandidateRecallRecord {
            let matching = candidates.filter { $0.family == family && $0.side == side }
            let measured = matching.compactMap { candidate -> (Double, CardCenteringCandidateDiagnostic)? in
                guard let expected, let error = candidateError(candidate, expected: expected, side: side) else {
                    return nil
                }
                return (error, candidate)
            }.sorted { $0.0 < $1.0 }
            let best = measured.first
            let withinTolerance = best.flatMap { pair in
                tolerance.map { pair.0 <= $0 }
            }
            return REQ042CandidateRecallRecord(
                family: family,
                side: side,
                candidateCount: matching.count,
                bestErrorPx: best?.0,
                bestSource: best?.1.source,
                bestSemanticRole: best?.1.proposedSemanticRole,
                tolerancePx: tolerance,
                anyWithinTolerance: withinTolerance
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var records: [REQ042FixtureDiagnosticRecord] = []

        var capturedAnalysis: CardCenteringAnalysisDiagnostic?
        var capturedLedger: CardCenteringCandidateLedgerDiagnostic?
        CardCenteringAnalyzer.analysisDiagnosticSink = { capturedAnalysis = $0 }
        CardCenteringAnalyzer.candidateLedgerDiagnosticSink = { capturedLedger = $0 }
        defer {
            CardCenteringAnalyzer.analysisDiagnosticSink = nil
            CardCenteringAnalyzer.candidateLedgerDiagnosticSink = nil
        }

        for fixture in fixtureNames {
            capturedAnalysis = nil
            capturedLedger = nil
            let data = try fixtureData(fixture)
            let result = try CardCenteringAnalyzer.analyze(data)
            let analysis = try XCTUnwrap(
                capturedAnalysis,
                "REQ-042 must capture branch metadata for \(fixture)"
            )
            let ledger = try XCTUnwrap(
                capturedLedger,
                "REQ-042 must capture candidate telemetry for \(fixture)"
            )
            XCTAssertGreaterThan(ledger.workingWidth, 0, fixture)
            XCTAssertGreaterThan(ledger.workingHeight, 0, fixture)
            XCTAssertFalse(ledger.candidates.isEmpty, fixture)

            let groundTruth = try fixtureRecord(fixture)
            let expectedOuter = try XCTUnwrap(CardCenteringQuad(groundTruth.cardOuterQuad), fixture)
            let expectedInner = groundTruth.innerQuad.flatMap(CardCenteringQuad.init)
            let cardHeight = expectedOuter.rectifiedHeight
            let outerTolerance = Dictionary(uniqueKeysWithValues: GroundTruthSide.allCases.map { side in
                (side.rawValue, groundTruthEdgeTolerance(groundTruth, side: side, cardHeight: cardHeight))
            })
            let innerTolerance = expectedInner.map { inner in
                Dictionary(uniqueKeysWithValues: GroundTruthSide.allCases.map { side in
                    (side.rawValue, cardHeight * 0.0035)
                })
            }
            let recall = GroundTruthSide.allCases.flatMap { side in
                [
                    bestRecall(
                        family: "outer",
                        side: side.rawValue,
                        candidates: ledger.candidates,
                        expected: expectedOuter,
                        tolerance: outerTolerance[side.rawValue]
                    ),
                    bestRecall(
                        family: "inner",
                        side: side.rawValue,
                        candidates: ledger.candidates,
                        expected: expectedInner,
                        tolerance: innerTolerance?[side.rawValue]
                    )
                ]
            }
            let record = REQ042FixtureDiagnosticRecord(
                fixture: fixture,
                groundTruthInnerReference: groundTruth.innerReference.rawValue,
                confidenceState: result.measurement.confidence.state.rawValue,
                selectedInnerSource: analysis.innerSource.rawValue,
                selectedOuterSource: analysis.selectedOuterSource,
                analysis: analysis,
                ledger: ledger,
                recall: recall
            )
            records.append(record)
            print(
                "REQ-042 fixture=\(fixture) state=\(record.confidenceState) "
                    + "innerSource=\(record.selectedInnerSource) "
                    + "candidates=\(ledger.candidates.count)"
            )
        }

        XCTAssertEqual(records.count, fixtureNames.count)
        try encoder.encode(records).write(
            to: output.appendingPathComponent("candidate-ledger.json"),
            options: .atomic
        )

        var markdown = [
            "# REQ-042 candidate recall diagnostic",
            "",
            "Signed DEBUG analyses on the original HEIC fixtures using the iOS 26.5 iPhone 17 Pro simulator.",
            "The ledger is observational. `bestErrorPx` is the maximum perpendicular distance of the candidate line's reported points from the corresponding GT edge; it is not a production selection score.",
            "",
            "| Fixture | GT inner | State | Inner source | Family | Side | Candidates | Best error px | Tolerance px | Best source | Best role | Within GT tolerance |",
            "|---|---|---|---|---|---|---:|---:|---:|---|---|---|"
        ]
        for record in records {
            for item in record.recall {
                let bestError = item.bestErrorPx.map { String(format: "%.2f", $0) } ?? "—"
                let tolerance = item.tolerancePx.map { String(format: "%.2f", $0) } ?? "—"
                let within = item.anyWithinTolerance.map { $0 ? "true" : "false" } ?? "—"
                markdown.append(
                    "| \(record.fixture) | \(record.groundTruthInnerReference) | \(record.confidenceState) | \(record.selectedInnerSource) | \(item.family) | \(item.side) | \(item.candidateCount) | \(bestError) | \(tolerance) | \(item.bestSource ?? "—") | \(item.bestSemanticRole ?? "—") | \(within) |"
                )
            }
        }
        try Data((markdown.joined(separator: "\n") + "\n").utf8).write(
            to: output.appendingPathComponent("candidate-ledger.md"),
            options: .atomic
        )
    }

    func testREQ043RegisteredBackIdentityGateReportsFrontNegativeClass() throws {
        let output = try centeringDiagnosticDirectory("REQ-043")
        let fronts = ["IMG_0348", "IMG_0349", "IMG_0351", "IMG_0780", "IMG_0782"]
        var captured: CardCenteringBackIdentityDiagnostic?
        CardCenteringAnalyzer.registeredBackIdentityDiagnosticSink = { captured = $0 }
        defer { CardCenteringAnalyzer.registeredBackIdentityDiagnosticSink = nil }

        var records: [REQ043BackIdentityRecord] = []
        for fixture in fronts {
            captured = nil
            _ = try CardCenteringAnalyzer.analyze(try fixtureData(fixture))
            let diagnostic = try XCTUnwrap(
                captured,
                "REQ-043 must emit identity-gate evidence for \(fixture)"
            )
            XCTAssertFalse(
                diagnostic.fullAcceptanceGatePassed,
                "front \(fixture) must not pass the registered-back identity gate"
            )
            records.append(REQ043BackIdentityRecord(fixture: fixture, diagnostic: diagnostic))
            print(
                "REQ-043 fixture=\(fixture) winner=\(diagnostic.winner) "
                    + String(format: "pokemon=%.4f magic=%.4f margin=%.4f", diagnostic.pokemonScore, diagnostic.magicScore, diagnostic.identityMargin)
                    + " fullGate=\(diagnostic.fullAcceptanceGatePassed)"
            )
        }

        XCTAssertEqual(records.count, fronts.count)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(
            to: output.appendingPathComponent("front-negative-class.json"),
            options: .atomic
        )

        var markdown = [
            "# REQ-043 registered-back identity negative class",
            "",
            "DEBUG-only identity scores for the five development front fixtures. The identity gate remains unchanged; this is distribution evidence, not a threshold fit.",
            "",
            "| Fixture | Winner | Pokémon score | Magic score | Margin | Score gate | Margin gate | Secondary gate | Full gate |",
            "|---|---|---:|---:|---:|---|---|---|---|"
        ]
        for record in records {
            let diagnostic = record.diagnostic
            markdown.append(
                String(
                    format: "| %@ | %@ | %.4f | %.4f | %.4f | %@ | %@ | %@ | %@ |",
                    record.fixture,
                    diagnostic.winner,
                    diagnostic.pokemonScore,
                    diagnostic.magicScore,
                    diagnostic.identityMargin,
                    diagnostic.scoreGatePassed ? "true" : "false",
                    diagnostic.marginGatePassed ? "true" : "false",
                    diagnostic.secondaryGatePassed ? "true" : "false",
                    diagnostic.fullAcceptanceGatePassed ? "true" : "false"
                )
            )
        }
        try Data((markdown.joined(separator: "\n") + "\n").utf8).write(
            to: output.appendingPathComponent("front-negative-class.md"),
            options: .atomic
        )
    }

    func testREQ043ReferenceTypeIsChosenSemanticallyAcrossDevelopmentCorpus() throws {
        for fixture in fixtureNames {
            let groundTruth = try fixtureRecord(fixture)
            let result = try CardCenteringAnalyzer.analyze(try fixtureData(fixture))

            XCTAssertEqual(
                result.measurement.innerReference,
                groundTruth.innerReference,
                "REQ-043 reference type mismatch for \(fixture)"
            )
        }
    }

    func testREQ044SelectedOuterTracksPhysicalCardOnDevelopmentBacks() throws {
        let backs = ["IMG_0347", "IMG_0350", "IMG_0352", "IMG_0781", "IMG_0783"]
        for fixture in backs {
            let groundTruth = try fixtureRecord(fixture)
            let result = try CardCenteringAnalyzer.analyze(try fixtureData(fixture))
            let mapping = try XCTUnwrap(result.coordinateMapping, fixture)
            let rawOuter = try XCTUnwrap(
                CardCenteringQuad(groundTruth.cardOuterQuad),
                fixture
            )
            let expectedOuter = mapping.workingQuad(fromNative: rawOuter)
            let actualOuter = result.measurement.geometryOuterQuad
            let cardHeight = expectedOuter.rectifiedHeight

            for side in GroundTruthSide.allCases {
                let expectedEdge = edgeEndpoints(expectedOuter, side: side)
                let actualEdge = edgeEndpoints(actualOuter, side: side)
                let dx = expectedEdge.1.x - expectedEdge.0.x
                let dy = expectedEdge.1.y - expectedEdge.0.y
                let length = max(hypot(dx, dy), .ulpOfOne)
                let errors = [actualEdge.0, actualEdge.1].map { point in
                    abs(dx * (point.y - expectedEdge.0.y) - dy * (point.x - expectedEdge.0.x)) / length
                }
                XCTAssertLessThanOrEqual(
                    errors.max() ?? .infinity,
                    groundTruthEdgeTolerance(groundTruth, side: side, cardHeight: cardHeight),
                    "REQ-044 selected outer misses the physical \(side.rawValue) edge for \(fixture)"
                )
            }
        }
    }

    func testREQ044BoundedJointSelectionExperimentRecordsL1Outcome() throws {
        let output = try centeringDiagnosticDirectory("REQ-044")
        var captured: CardCenteringJointSelectionDiagnostic?
        var capturedAnalysis: CardCenteringAnalysisDiagnostic?
        CardCenteringAnalyzer.jointSelectionEnabled = true
        CardCenteringAnalyzer.frontBottomCandidateGenerationEnabled = true
        CardCenteringAnalyzer.jointSelectionDiagnosticSink = { captured = $0 }
        CardCenteringAnalyzer.analysisDiagnosticSink = { capturedAnalysis = $0 }
        defer {
            CardCenteringAnalyzer.jointSelectionEnabled = false
            CardCenteringAnalyzer.frontBottomCandidateGenerationEnabled = true
            CardCenteringAnalyzer.jointSelectionDiagnosticSink = nil
            CardCenteringAnalyzer.analysisDiagnosticSink = nil
        }

        func measuredRatios(
            _ result: CardCenteringAnalysis,
            fixture: String
        ) throws -> (lr: Double, tb: Double)? {
            guard let inner = result.measurement.geometryInnerQuad else { return nil }
            let mapping = try XCTUnwrap(result.coordinateMapping, fixture)
            let outer = mapping.nativeQuad(fromWorking: result.measurement.geometryOuterQuad)
            let nativeInner = mapping.nativeQuad(fromWorking: inner)
            let distances = outer.borderDistances(to: nativeInner)
            return (
                100 * distances.left / max(distances.left + distances.right, .ulpOfOne),
                100 * distances.top / max(distances.top + distances.bottom, .ulpOfOne)
            )
        }

        var records: [REQ044JointSelectionRecord] = []
        var gradeableCount = 0
        var confidentAndCorrectCount = 0
        var automaticCandidateWrongCount = 0

        for fixture in fixtureNames {
            captured = nil
            capturedAnalysis = nil
            let groundTruth = try fixtureRecord(fixture)
            let result = try CardCenteringAnalyzer.analyze(try fixtureData(fixture))
            let measured = try measuredRatios(result, fixture: fixture)
            let expectedLR = groundTruth.expected.lrRatio
            let expectedTB = groundTruth.expected.tbRatio
            let lrError = measured.flatMap { actual in
                expectedLR.map { abs(actual.lr - $0) }
            }
            let tbError = measured.flatMap { actual in
                expectedTB.map { abs(actual.tb - $0) }
            }
            let ratioPass: Bool
            if groundTruth.innerQuad == nil {
                ratioPass = result.measurement.isDeclined
            } else {
                gradeableCount += 1
                ratioPass = lrError.map { $0 <= 2 } == true
                    && tbError.map { $0 <= 2 } == true
                let candidateWasAutomatic = result.measurement.requiresManualInnerConfirmation
                if candidateWasAutomatic, ratioPass {
                    confidentAndCorrectCount += 1
                } else if candidateWasAutomatic {
                    automaticCandidateWrongCount += 1
                }
            }
            records.append(
                REQ044JointSelectionRecord(
                    fixture: fixture,
                    expectedLR: expectedLR,
                    expectedTB: expectedTB,
                    measuredLR: measured?.lr,
                    measuredTB: measured?.tb,
                    lrErrorPP: lrError,
                    tbErrorPP: tbError,
                    ratioPassAt2PP: ratioPass,
                    confidenceState: result.measurement.confidence.state.rawValue,
                    innerSource: capturedAnalysis?.innerSource ?? .none,
                    diagnostic: captured
                )
            )
            print(
                "REQ-044 fixture=\(fixture) accepted=\(captured?.accepted ?? false) "
                    + "state=\(result.measurement.confidence.state.rawValue) "
                    + String(format: "lrError=%.2f tbError=%.2f", lrError ?? .nan, tbError ?? .nan)
            )
        }

        let coverage = Double(confidentAndCorrectCount) / Double(max(gradeableCount, 1))
        XCTAssertGreaterThan(
            automaticCandidateWrongCount,
            0,
            "REQ-044 must retain evidence that the bounded selector did not clear the safety bar"
        )
        XCTAssertLessThan(
            coverage,
            0.80,
            "REQ-044 must not be recorded as a passing automatic selector experiment"
        )
        XCTAssertEqual(records.count, fixtureNames.count)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(
            to: output.appendingPathComponent("joint-selection-l1.json"),
            options: .atomic
        )

        let markdown = [
            "# REQ-044 bounded joint-selection experiment",
            "",
            "Development-only L1 measurement with the DEBUG selector switch enabled. The sealed holdout was not evaluated and no contract threshold was changed.",
            "",
            String(format: "Gradeable fixtures: %d", gradeableCount),
            String(format: "Confident-and-correct: %d/%d (%.1f%%)", confidentAndCorrectCount, gradeableCount, coverage * 100),
            "Automatic candidates wrong under the pre-hybrid confidence gate: \(automaticCandidateWrongCount)",
            "",
            "| Fixture | State | Inner source | Accepted | Candidate count | Baseline aspect | Selected aspect | LR error pp | TB error pp | Ratio pass |",
            "|---|---|---|---|---:|---:|---:|---:|---:|---|"
        ] + records.map { record in
            let diagnostic = record.diagnostic
            let baselineAspect = diagnostic.map { String(format: "%.4f", $0.baselineAspect) } ?? "—"
            let selectedAspect = diagnostic?.selectedAspect.map { String(format: "%.4f", $0) } ?? "—"
            let candidateCount = diagnostic?.candidateCount.description ?? "—"
            let lr = record.lrErrorPP.map { String(format: "%.2f", $0) } ?? "—"
            let tb = record.tbErrorPP.map { String(format: "%.2f", $0) } ?? "—"
            return "| \(record.fixture) | \(record.confidenceState) | \(record.innerSource.rawValue) | \(diagnostic?.accepted.description ?? "—") | \(candidateCount) | \(baselineAspect) | \(selectedAspect) | \(lr) | \(tb) | \(record.ratioPassAt2PP) |"
        }
        try Data((markdown.joined(separator: "\n") + "\n").utf8).write(
            to: output.appendingPathComponent("joint-selection-l1.md"),
            options: .atomic
        )
    }

    func testHybridSeedAgainstLeaveOneOutFamilyPrior() throws {
        let output = try centeringDiagnosticDirectory("hybrid-seed-prior")
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = repository
            .appendingPathComponent("TestFixtures/TradingCards/Supplementary/corpus-manifest.json")
        let manifest = try JSONDecoder().decode(
            CenteringCorpusManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let familyByFixture = Dictionary(
            uniqueKeysWithValues: manifest.entries.compactMap { entry -> (String, String)? in
                let file = URL(fileURLWithPath: entry.file)
                guard file.pathExtension.lowercased() == "heic" else { return nil }
                return (file.deletingPathExtension().lastPathComponent, entry.game)
            }
        )

        struct Sample {
            let fixture: String
            let family: String
            let depths: [GroundTruthSide: Double]
        }

        func normalizedDepths(
            outer: CardCenteringQuad,
            inner: CardCenteringQuad
        ) -> [GroundTruthSide: Double] {
            let distances = outer.borderDistances(to: inner)
            return [
                .left: distances.left / max(outer.rectifiedWidth, .ulpOfOne),
                .top: distances.top / max(outer.rectifiedHeight, .ulpOfOne),
                .right: distances.right / max(outer.rectifiedWidth, .ulpOfOne),
                .bottom: distances.bottom / max(outer.rectifiedHeight, .ulpOfOne)
            ]
        }

        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            let middle = sorted.count / 2
            guard !sorted.isEmpty else { return .nan }
            return sorted.count.isMultiple(of: 2)
                ? (sorted[middle - 1] + sorted[middle]) / 2
                : sorted[middle]
        }

        var gradeableFixtures: [String] = []
        for name in fixtureNames where try fixtureRecord(name).innerQuad != nil {
            gradeableFixtures.append(name)
        }
        var samples: [Sample] = []
        for fixture in gradeableFixtures {
            let record = try fixtureRecord(fixture)
            let family = try XCTUnwrap(familyByFixture[fixture], fixture)
            let outer = try XCTUnwrap(CardCenteringQuad(record.cardOuterQuad), fixture)
            let inner = try XCTUnwrap(record.innerQuad.flatMap(CardCenteringQuad.init), fixture)
            samples.append(
                Sample(
                    fixture: fixture,
                    family: family,
                    depths: normalizedDepths(outer: outer, inner: inner)
                )
            )
        }

        XCTAssertEqual(samples.count, 9)
        var records: [HybridSeedPriorRecord] = []

        for sample in samples {
            let result = try CardCenteringAnalyzer.analyze(try fixtureData(sample.fixture))
            let mapping = try XCTUnwrap(result.coordinateMapping, sample.fixture)
            let groundTruth = try fixtureRecord(sample.fixture)
            let groundTruthOuter = try XCTUnwrap(CardCenteringQuad(groundTruth.cardOuterQuad), sample.fixture)
            let seed = try XCTUnwrap(result.measurement.geometryInnerQuad, sample.fixture)
            let seedNative = mapping.nativeQuad(fromWorking: seed)
            let detectorDepths = normalizedDepths(outer: groundTruthOuter, inner: seedNative)

            for side in GroundTruthSide.allCases {
                let priorSamples = samples.filter {
                    $0.family == sample.family && $0.fixture != sample.fixture
                }
                let priorDepth = median(priorSamples.compactMap { $0.depths[side] })
                let expectedDepth = try XCTUnwrap(sample.depths[side], "missing GT (sample.fixture) (side.rawValue)")
                let detectorDepth = try XCTUnwrap(detectorDepths[side], "missing seed (sample.fixture) (side.rawValue)")
                let detectorErrorPP = abs(detectorDepth - expectedDepth) * 100
                let priorErrorPP = priorDepth.isFinite
                    ? abs(priorDepth - expectedDepth) * 100
                    : nil
                records.append(
                    HybridSeedPriorRecord(
                        fixture: sample.fixture,
                        family: sample.family,
                        side: side.rawValue,
                        expectedDepth: expectedDepth,
                        detectorDepth: detectorDepth,
                        leaveOneOutPriorDepth: priorDepth.isFinite ? priorDepth : nil,
                        detectorErrorPP: detectorErrorPP,
                        priorErrorPP: priorErrorPP,
                        detectorWins: priorErrorPP.map { detectorErrorPP < $0 },
                        priorWins: priorErrorPP.map { $0 < detectorErrorPP }
                    )
                )
            }
        }

        XCTAssertEqual(records.count, 36)
        XCTAssertTrue(records.allSatisfy { $0.priorErrorPP != nil })

        let grouped = Dictionary(grouping: records) { "\($0.family)/\($0.side)" }
        let summaries = grouped.keys.sorted().map { key -> HybridSeedPriorSummary in
            let group = grouped[key]!
            return HybridSeedPriorSummary(
                family: group[0].family,
                side: group[0].side,
                sampleCount: group.count,
                detectorMedianErrorPP: median(group.map(\.detectorErrorPP)),
                priorMedianErrorPP: median(group.compactMap(\.priorErrorPP)),
                detectorWins: group.filter { $0.detectorWins == true }.count,
                priorWins: group.filter { $0.priorWins == true }.count,
                ties: group.filter { $0.detectorWins == false && $0.priorWins == false }.count
            )
        }

        for summary in summaries {
            print(
                "HYBRID-SEED family=\(summary.family) side=\(summary.side) "
                    + String(
                        format: "detectorMedian=%.2f priorMedian=%.2f detectorWins=%d priorWins=%d ties=%d",
                        summary.detectorMedianErrorPP,
                        summary.priorMedianErrorPP,
                        summary.detectorWins,
                        summary.priorWins,
                        summary.ties
                    )
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(
            to: output.appendingPathComponent("seed-vs-family-prior.json"),
            options: .atomic
        )
        try encoder.encode(summaries).write(
            to: output.appendingPathComponent("summary.json"),
            options: .atomic
        )

        let markdown = [
            "# Hybrid detector seed versus leave-one-out family prior",
            "",
            "Development-only diagnostic over the nine gradeable historical fixtures. Depths are normalized by the annotated card width for left/right and height for top/bottom. The family prior is a median of the other gradeable fixtures in the same corpus family; no holdout was read and no production threshold changed.",
            "",
            "| Family | Side | Samples | Detector median error pp | Prior median error pp | Detector wins | Prior wins | Ties |",
            "|---|---|---:|---:|---:|---:|---:|---:|"
        ] + summaries.map {
            String(
                format: "| %@ | %@ | %d | %.2f | %.2f | %d | %d | %d |",
                $0.family,
                $0.side,
                $0.sampleCount,
                $0.detectorMedianErrorPP,
                $0.priorMedianErrorPP,
                $0.detectorWins,
                $0.priorWins,
                $0.ties
            )
        }
        try Data((markdown.joined(separator: "\n") + "\n").utf8).write(
            to: output.appendingPathComponent("summary.md"),
            options: .atomic
        )
    }

    func testREQ041ControlledFrontBottomGeneratorAB() throws {
        let output = try centeringDiagnosticDirectory("REQ-041-AB")
        var captured: CardCenteringAnalysisDiagnostic?
        CardCenteringAnalyzer.analysisDiagnosticSink = { captured = $0 }
        defer {
            CardCenteringAnalyzer.analysisDiagnosticSink = nil
            CardCenteringAnalyzer.frontBottomCandidateGenerationEnabled = true
        }

        func run(arm: String, enabled: Bool) throws -> [REQ041ControlledABRecord] {
            CardCenteringAnalyzer.frontBottomCandidateGenerationEnabled = enabled
            var records: [REQ041ControlledABRecord] = []
            for fixture in fixtureNames {
                captured = nil
                let start = CFAbsoluteTimeGetCurrent()
                _ = try CardCenteringAnalyzer.analyze(try fixtureData(fixture))
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                let diagnostic = try XCTUnwrap(
                    captured,
                    "REQ-041 A/B must capture stage timings for \(arm)/\(fixture)"
                )
                let attribution = diagnostic.stageTimings.total / max(elapsed, .ulpOfOne)
                XCTAssertGreaterThanOrEqual(attribution, 0.90)
                records.append(
                    REQ041ControlledABRecord(
                        arm: arm,
                        fixture: fixture,
                        elapsedSeconds: elapsed,
                        stageTimings: diagnostic.stageTimings,
                        attributedFraction: attribution
                    )
                )
            }
            return records
        }

        let withoutGenerator = try run(arm: "without-front-bottom-generator", enabled: false)
        let withGenerator = try run(arm: "with-front-bottom-generator", enabled: true)
        let records = withoutGenerator + withGenerator
        XCTAssertEqual(records.count, fixtureNames.count * 2)

        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            let middle = sorted.count / 2
            return sorted.count.isMultiple(of: 2)
                ? (sorted[middle - 1] + sorted[middle]) / 2
                : sorted[middle]
        }

        for arm in ["without-front-bottom-generator", "with-front-bottom-generator"] {
            let armRecords = records.filter { $0.arm == arm }
            let inner = armRecords.map { $0.stageTimings.innerCandidateGeneration }
            let wall = armRecords.map(\.elapsedSeconds)
            print(
                "REQ-041 A/B arm=\(arm) "
                    + String(format: "innerMedian=%.4f innerMax=%.4f wallMedian=%.4f wallMax=%.4f", median(inner), inner.max() ?? 0, median(wall), wall.max() ?? 0)
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(
            to: output.appendingPathComponent("front-generator-ab.json"),
            options: .atomic
        )

        var markdown = [
            "# REQ-041 front-bottom generator controlled A/B",
            "",
            "Both arms use the same raw-fixture harness and simulator session. The generator is observational in DEBUG and is compiled out of Release; no production selection is changed by this measurement.",
            "",
            "| Arm | Analyses | Inner-generation median | Inner-generation max | Wall median | Wall max |",
            "|---|---:|---:|---:|---:|---:|"
        ]
        for arm in ["without-front-bottom-generator", "with-front-bottom-generator"] {
            let armRecords = records.filter { $0.arm == arm }
            let inner = armRecords.map { $0.stageTimings.innerCandidateGeneration }
            let wall = armRecords.map(\.elapsedSeconds)
            markdown.append(
                String(
                    format: "| %@ | %d | %.4f | %.4f | %.4f | %.4f |",
                    arm,
                    armRecords.count,
                    median(inner),
                    inner.max() ?? 0,
                    median(wall),
                    wall.max() ?? 0
                )
            )
        }
        try Data((markdown.joined(separator: "\n") + "\n").utf8).write(
            to: output.appendingPathComponent("front-generator-ab.md"),
            options: .atomic
        )
    }

    func testREQ041ProfilesNamedStageTimingsAcrossAllFixtures() throws {
        let output = try centeringDiagnosticDirectory("REQ-041")

        let stageSpecs: [(String, KeyPath<CardCenteringStageTimingDiagnostic, Double>)] = [
            ("decodeOrientationDownscale", \.decodeOrientationDownscale),
            ("colorPreparation", \.colorPreparation),
            ("visionRequests", \.visionRequests),
            ("scalarFields", \.scalarFields),
            ("outerCandidateRefinement", \.outerCandidateRefinement),
            ("innerCandidateGeneration", \.innerCandidateGeneration),
            ("jointSelection", \.jointSelection),
            ("rectification", \.rectification),
            ("resultConstruction", \.resultConstruction)
        ]

        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            let middle = sorted.count / 2
            return sorted.count.isMultiple(of: 2)
                ? (sorted[middle - 1] + sorted[middle]) / 2
                : sorted[middle]
        }

        var records: [REQ041StageTimingRecord] = []
        var captured: CardCenteringAnalysisDiagnostic?
        CardCenteringAnalyzer.analysisDiagnosticSink = { captured = $0 }
        defer { CardCenteringAnalyzer.analysisDiagnosticSink = nil }

        // Keep the complete repeated corpus below XCTest's per-test watchdog.
        // The analyzer takes roughly 2.7 seconds per raw HEIC on the pinned
        // simulator, so two passes still provide repeated median/max data
        // without turning the diagnostic itself into a timeout experiment.
        for repetition in 1...2 {
            for fixture in fixtureNames {
                captured = nil
                let start = CFAbsoluteTimeGetCurrent()
                _ = try CardCenteringAnalyzer.analyze(try fixtureData(fixture))
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                let diagnostic = try XCTUnwrap(
                    captured,
                    "REQ-041 must capture stage timings for \(fixture), repetition \(repetition)"
                )
                let timings = diagnostic.stageTimings
                XCTAssertTrue(elapsed.isFinite && elapsed > 0, "invalid wall time for \(fixture)")
                for (name, keyPath) in stageSpecs {
                    let value = timings[keyPath: keyPath]
                    XCTAssertTrue(value.isFinite && value >= 0, "invalid \(name) timing for \(fixture)")
                }
                let attribution = timings.total / elapsed
                XCTAssertGreaterThanOrEqual(
                    attribution,
                    0.90,
                    "REQ-041 must attribute at least 90% of \(fixture) wall time to named stages"
                )
                records.append(
                    REQ041StageTimingRecord(
                        fixture: fixture,
                        repetition: repetition,
                        elapsedSeconds: elapsed,
                        stageTimings: timings,
                        attributedFraction: attribution
                    )
                )
                print(
                    "REQ-041 fixture=\(fixture) repetition=\(repetition) "
                        + String(format: "elapsed=%.3f attributed=%.3f", elapsed, attribution)
                )
            }
        }

        XCTAssertEqual(records.count, fixtureNames.count * 2)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(
            to: output.appendingPathComponent("stage-timings.json"),
            options: .atomic
        )

        var markdown = [
            "# REQ-041 named stage timing profile",
            "",
            "Signed DEBUG analyses on the iOS 26.5 iPhone 17 Pro simulator. Each fixture was analyzed twice.",
            "The attribution fraction is the sum of the named stage timers divided by the independently measured wall time.",
            "",
            "| Stage | Median seconds | Max seconds | Median share of wall time |",
            "|---|---:|---:|---:|"
        ]
        for (name, keyPath) in stageSpecs {
            let values = records.map { $0.stageTimings[keyPath: keyPath] }
            let wall = records.map(\.elapsedSeconds)
            let shares = zip(values, wall).map { $0 / max($1, .ulpOfOne) }
            markdown.append(
                String(
                    format: "| `%@` | %.4f | %.4f | %.3f |",
                    name,
                    median(values),
                    values.max() ?? 0,
                    median(shares)
                )
            )
        }
        let attribution = records.map(\.attributedFraction)
        markdown.append(contentsOf: [
            "",
            String(format: "Named-stage attribution median/max: %.3f / %.3f", median(attribution), attribution.max() ?? 0),
            String(format: "Wall-time median/max: %.4f / %.4f seconds", median(records.map(\.elapsedSeconds)), records.map(\.elapsedSeconds).max() ?? 0)
        ])
        try Data((markdown.joined(separator: "\n") + "\n").utf8).write(
            to: output.appendingPathComponent("stage-timings.md"),
            options: .atomic
        )
    }
#endif

    func testINV2SmallRotationPreservesReportedRatios() throws {
        let data = try fixtureData(holdout)
        let baseline = try confidentRatios(data)
        for degrees in [-3.0, 3.0] {
            let variant = try renderedVariant(data, rotationDegrees: CGFloat(degrees))
            let measured = try confidentRatios(variant)
            XCTAssertLessThanOrEqual(ratioError(measured, baseline), 1.5, "rotation \(degrees)°")
        }
    }

    func testINV3FittedSkewTracksTheAppliedRotationAcrossTheCorpus() throws {
        let angles: [CGFloat] = [-8, -5, -3, -1, 0, 1, 3, 5, 8]
        for name in fixtureNames {
            let data = try fixtureData(name)
            for angle in angles {
                let variant = try renderedVariant(data, rotationDegrees: angle)
                let analysis = try CardCenteringAnalyzer.analyze(variant)
                if let detected = analysis.detectedSkewDegrees {
                    XCTAssertEqual(detected, Double(angle), accuracy: 0.25, "\(name) angle \(angle)")
                    XCTAssertEqual(analysis.appliedRotationDegrees, -Double(angle), accuracy: 0.25, "\(name) angle \(angle)")
                } else if angle != 0 {
                    XCTFail("missing fitted skew for \(name) angle \(angle)")
                }
            }
        }
    }

    func testINV4HorizontalMirrorComplementsLeftRightOnly() throws {
        let data = try fixtureData(holdout)
        let baseline = try confidentRatios(data)
        let mirrored = try confidentRatios(try renderedVariant(data, mirrorX: true))
        XCTAssertLessThanOrEqual(abs(mirrored.lr - (100 - baseline.lr)), 0.5)
        XCTAssertLessThanOrEqual(abs(mirrored.tb - baseline.tb), 0.5)
    }

    func testINV5QuarterTurnsMapThePerSideRatios() throws {
        let data = try fixtureData(holdout)
        let baseline = try confidentRatios(data)
        let expected: [(CGFloat, (Double, Double), (Double, Double))] = [
            (90, (baseline.tb, 100 - baseline.lr), (100 - baseline.tb, baseline.lr)),
            (180, (100 - baseline.lr, 100 - baseline.tb), (100 - baseline.lr, 100 - baseline.tb)),
            (270, (100 - baseline.tb, baseline.lr), (baseline.tb, 100 - baseline.lr))
        ]
        for (degrees, first, second) in expected {
            let measured = try confidentRatios(try renderedVariant(data, rotationDegrees: degrees))
            let error = min(ratioError(measured, (lr: first.0, tb: first.1)), ratioError(measured, (lr: second.0, tb: second.1)))
            XCTAssertLessThanOrEqual(error, 0.5, "quarter turn \(degrees)°")
        }
    }

    func testINV6ReencodedExifOrientationsPreserveTheSameDisplayedResult() throws {
        for name in ["IMG_0348", "IMG_0780", holdout] {
            let data = try fixtureData(name)
            // Compare every EXIF encoding with the same canonical displayed
            // bitmap used to construct the variants. Comparing the variants
            // with the original HEIC would also measure a resolution and
            // resampling change, which is outside INV-6.
            let canonicalData = try XCTUnwrap(try normalisedImage(data).pngData())
            let baseline = try confidentRatios(canonicalData)
            for orientation in [1, 3, 6, 8] {
                let variant = try reencodedVariant(data, exifOrientation: orientation)
                let measured = try confidentRatios(variant)
                XCTAssertLessThanOrEqual(ratioError(measured, baseline), 0.5, "\(name) EXIF \(orientation)")
            }
        }
    }

    func testINV7UniformScaleDoesNotChangeRatios() throws {
        let data = try fixtureData(holdout)
        let baseline = try confidentRatios(data)
        for scale in [CGFloat(0.6), 1.5] {
            let measured = try confidentRatios(try renderedVariant(data, scale: scale))
            XCTAssertLessThanOrEqual(ratioError(measured, baseline), 1.0, "scale \(scale)")
        }
    }

    func testINV8BenignCropWithEightPercentCardMarginPreservesRatios() throws {
        let data = try fixtureData(holdout)
        let baseline = try confidentRatios(data)
        let record = try fixtureRecord(holdout)
        let measured = try confidentRatios(try benignCropVariant(data, record: record))
        XCTAssertLessThanOrEqual(ratioError(measured, baseline), 1.0)
    }

    func testINV9SleevedCardsDoNotSelectTheEncasementQuad() throws {
        for name in fixtureNames {
            let record = try fixtureRecord(name)
            guard let sleeveValues = record.encasementOuterQuad else { continue }
            let analysis = try CardCenteringAnalyzer.analyze(try fixtureData(name))
            guard !analysis.measurement.isDeclined else { continue }
            let mapping = try XCTUnwrap(analysis.coordinateMapping, name)
            let detected = mapping.nativeQuad(fromWorking: analysis.measurement.geometryOuterQuad)
            let card = try XCTUnwrap(CardCenteringQuad(record.cardOuterQuad), name)
            let sleeve = try XCTUnwrap(CardCenteringQuad(sleeveValues), name)
            XCTAssertLessThan(
                maxCornerDistance(detected, card),
                maxCornerDistance(detected, sleeve),
                "\(name) must select the physical card rather than the encasement"
            )
        }
    }

    func testINV10ConfidentResultsStayInsideTheFourPercentAspectGuard() throws {
        for name in fixtureNames {
            let analysis = try CardCenteringAnalyzer.analyze(try fixtureData(name))
            if !analysis.measurement.isDeclined {
                XCTAssertLessThanOrEqual(analysis.measurement.confidence.aspectResidual, 0.04, name)
                XCTAssertTrue(analysis.measurement.confidence.innerReferencePresent, name)
            }
        }
    }

    func testREQ022AnalysisPerformanceOverAllFixtures() throws {
        var durations: [Double] = []
        for name in fixtureNames {
            let data = try fixtureData(name)
            let start = CFAbsoluteTimeGetCurrent()
            _ = try CardCenteringAnalyzer.analyze(data)
            durations.append(CFAbsoluteTimeGetCurrent() - start)
        }
        let sorted = durations.sorted()
        let median = sorted[sorted.count / 2]
        let maximum = sorted.max() ?? 0
        XCTAssertLessThanOrEqual(median, 0.8)
        XCTAssertLessThanOrEqual(maximum, 1.5)
    }

#if DEBUG
    func testREQ031ResolutionAccuracyAndLatencyCurve() throws {
        let dimensions = [1_200, 1_600, 2_000, 2_400]
        let output = try centeringDiagnosticDirectory("E7")

        func measuredRatios(_ analysis: CardCenteringAnalysis) -> (lr: Double, tb: Double)? {
            guard let inner = analysis.measurement.geometryInnerQuad else { return nil }
            let distances = analysis.measurement.geometryOuterQuad.borderDistances(to: inner)
            return (
                100 * distances.left / max(distances.left + distances.right, .ulpOfOne),
                100 * distances.top / max(distances.top + distances.bottom, .ulpOfOne)
            )
        }

        var records: [E7ResolutionCurveRecord] = []
        for dimension in dimensions {
            for name in fixtureNames {
                let data = try fixtureData(name)
                let groundTruth = try fixtureRecord(name)
                let start = CFAbsoluteTimeGetCurrent()
                let analysis = try CardCenteringAnalyzer.analyzeForBenchmark(
                    data,
                    workingMaxDimension: CGFloat(dimension)
                )
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                let measured = measuredRatios(analysis)
                let expectedLR = groundTruth.expected.lrRatio
                let expectedTB = groundTruth.expected.tbRatio
                let lrError: Double?
                if let actual = measured?.lr, let expected = expectedLR {
                    lrError = abs(actual - expected)
                } else {
                    lrError = nil
                }
                let tbError: Double?
                if let actual = measured?.tb, let expected = expectedTB {
                    tbError = abs(actual - expected)
                } else {
                    tbError = nil
                }
                let ratioPass: Bool
                if groundTruth.innerQuad == nil {
                    ratioPass = analysis.measurement.isDeclined
                } else {
                    ratioPass = lrError.map { $0 <= 2 } == true
                        && tbError.map { $0 <= 2 } == true
                }
                records.append(
                    E7ResolutionCurveRecord(
                        fixture: name,
                        workingMaxDimension: dimension,
                        detectionMaxDimension: dimension,
                        elapsedSeconds: elapsed,
                        workingWidth: analysis.measurement.imageWidth,
                        workingHeight: analysis.measurement.imageHeight,
                        cardHeightWorkingPx: analysis.measurement.geometryOuterQuad.rectifiedHeight,
                        confidenceState: analysis.measurement.confidence.state.rawValue,
                        confidenceScore: analysis.measurement.confidence.score,
                        innerReference: analysis.measurement.innerReference.rawValue,
                        expectedLR: expectedLR,
                        expectedTB: expectedTB,
                        measuredLR: measured?.lr,
                        measuredTB: measured?.tb,
                        lrErrorPP: lrError,
                        tbErrorPP: tbError,
                        ratioPassAt2PP: ratioPass,
                        detectedSkewDegrees: analysis.detectedSkewDegrees,
                        appliedRotationDegrees: analysis.appliedRotationDegrees,
                        rectificationResidualDegrees: analysis.measurement.rectification?.residualDegrees,
                        rectificationReprojectionRMS: analysis.measurement.rectification?.reprojectionRMS
                    )
                )
                XCTAssertTrue(elapsed.isFinite, "non-finite latency for \(name) at \(dimension)")
                XCTAssertGreaterThan(analysis.measurement.imageWidth, 20, "invalid width for \(name) at \(dimension)")
                XCTAssertGreaterThan(analysis.measurement.imageHeight, 20, "invalid height for \(name) at \(dimension)")
                print(
                    "E7_CURVE fixture=\(name) max=\(dimension) "
                        + String(format: "elapsed=%.3f", elapsed)
                        + " state=\(analysis.measurement.confidence.state.rawValue) "
                        + " ratioPassAt2PP=\(ratioPass)"
                )
            }
        }

        XCTAssertEqual(records.count, dimensions.count * fixtureNames.count)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(
            to: output.appendingPathComponent("resolution-curve.json"),
            options: .atomic
        )

        var markdown = [
            "# E7 resolution and latency curve",
            "",
            "This diagnostic uses the production analyzer entry point with only its DEBUG benchmark resolution override. Ground truth was rederived under REQ-027; `ratioPassAt2PP` is adjudicable against the current records but does not by itself close the broader L1/REQ-045 gate.",
            "",
            "| Max working dimension | Median seconds | Max seconds | Gradeable/confident | Ratio pass at 2 pp |",
            "|---:|---:|---:|---:|---:|"
        ]
        for dimension in dimensions {
            let subset = records.filter { $0.workingMaxDimension == dimension }
            let sortedDurations = subset.map(\.elapsedSeconds).sorted()
            let median = sortedDurations[sortedDurations.count / 2]
            let maximum = sortedDurations.max() ?? 0
            let confident = subset.filter { $0.confidenceState == CardCenteringConfidenceState.confident.rawValue }.count
            let ratioPasses = subset.filter(\.ratioPassAt2PP).count
            markdown.append(
                String(
                    format: "| %d | %.3f | %.3f | %d/%d | %d/%d |",
                    dimension,
                    median,
                    maximum,
                    confident,
                    subset.count,
                    ratioPasses,
                    subset.count
                )
            )
        }
        markdown.append(contentsOf: [
            "",
            "## Per-fixture records",
            "",
            "| Fixture | Working max | Detection max | Seconds | Working size | Card H px | State | LR error pp | TB error pp |",
            "|---|---:|---:|---:|---:|---:|---|---:|---:|"
        ])
        for record in records {
            let lr = record.lrErrorPP.map { String(format: "%.3f", $0) } ?? "—"
            let tb = record.tbErrorPP.map { String(format: "%.3f", $0) } ?? "—"
            markdown.append(
                String(
                    format: "| `%@` | %d | %d | %.3f | %dx%d | %.1f | %@ | %@ | %@ |",
                    record.fixture,
                    record.workingMaxDimension,
                    record.detectionMaxDimension,
                    record.elapsedSeconds,
                    record.workingWidth,
                    record.workingHeight,
                    record.cardHeightWorkingPx,
                    record.confidenceState,
                    lr,
                    tb
                )
            )
        }
        try Data((markdown.joined(separator: "\n") + "\n").utf8).write(
            to: output.appendingPathComponent("resolution-curve.md"),
            options: .atomic
        )
    }

    func testREQ031LowResolutionDetectionFullResolutionRefinement() throws {
        let dimensions = [1_200, 1_600, 2_000, 2_400]
        let output = try centeringDiagnosticDirectory("E7")

        func measuredRatios(_ analysis: CardCenteringAnalysis) -> (lr: Double, tb: Double)? {
            guard let inner = analysis.measurement.geometryInnerQuad else { return nil }
            let distances = analysis.measurement.geometryOuterQuad.borderDistances(to: inner)
            return (
                100 * distances.left / max(distances.left + distances.right, .ulpOfOne),
                100 * distances.top / max(distances.top + distances.bottom, .ulpOfOne)
            )
        }

        var records: [E7ResolutionCurveRecord] = []
        for dimension in dimensions {
            let detectionDimension = min(1_200, dimension)
            for name in fixtureNames {
                let data = try fixtureData(name)
                let groundTruth = try fixtureRecord(name)
                let start = CFAbsoluteTimeGetCurrent()
                let analysis = try CardCenteringAnalyzer.analyzeForBenchmark(
                    data,
                    workingMaxDimension: CGFloat(dimension),
                    detectionMaxDimension: CGFloat(detectionDimension)
                )
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                let measured = measuredRatios(analysis)
                let expectedLR = groundTruth.expected.lrRatio
                let expectedTB = groundTruth.expected.tbRatio
                let lrError: Double?
                if let actual = measured?.lr, let expected = expectedLR {
                    lrError = abs(actual - expected)
                } else {
                    lrError = nil
                }
                let tbError: Double?
                if let actual = measured?.tb, let expected = expectedTB {
                    tbError = abs(actual - expected)
                } else {
                    tbError = nil
                }
                let ratioPass: Bool
                if groundTruth.innerQuad == nil {
                    ratioPass = analysis.measurement.isDeclined
                } else {
                    ratioPass = lrError.map { $0 <= 2 } == true
                        && tbError.map { $0 <= 2 } == true
                }
                records.append(
                    E7ResolutionCurveRecord(
                        fixture: name,
                        workingMaxDimension: dimension,
                        detectionMaxDimension: detectionDimension,
                        elapsedSeconds: elapsed,
                        workingWidth: analysis.measurement.imageWidth,
                        workingHeight: analysis.measurement.imageHeight,
                        cardHeightWorkingPx: analysis.measurement.geometryOuterQuad.rectifiedHeight,
                        confidenceState: analysis.measurement.confidence.state.rawValue,
                        confidenceScore: analysis.measurement.confidence.score,
                        innerReference: analysis.measurement.innerReference.rawValue,
                        expectedLR: expectedLR,
                        expectedTB: expectedTB,
                        measuredLR: measured?.lr,
                        measuredTB: measured?.tb,
                        lrErrorPP: lrError,
                        tbErrorPP: tbError,
                        ratioPassAt2PP: ratioPass,
                        detectedSkewDegrees: analysis.detectedSkewDegrees,
                        appliedRotationDegrees: analysis.appliedRotationDegrees,
                        rectificationResidualDegrees: analysis.measurement.rectification?.residualDegrees,
                        rectificationReprojectionRMS: analysis.measurement.rectification?.reprojectionRMS
                    )
                )
                XCTAssertTrue(elapsed.isFinite, "non-finite latency for \(name) at \(dimension)")
                XCTAssertGreaterThan(analysis.measurement.imageWidth, 20, "invalid width for \(name) at \(dimension)")
                XCTAssertGreaterThan(analysis.measurement.imageHeight, 20, "invalid height for \(name) at \(dimension)")
            }
        }

        XCTAssertEqual(records.count, dimensions.count * fixtureNames.count)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(
            to: output.appendingPathComponent("low-detection-curve.json"),
            options: .atomic
        )

        var markdown = [
            "# E7 low-resolution detection with full-resolution refinement",
            "",
            "Vision and scalar outline detection run at the detection maximum; the profile stage runs at the working maximum. Ground truth was rederived under REQ-027, so the ratio-error columns are adjudicable; this benchmark does not by itself close the broader L1/REQ-045 gate.",
            "",
            "| Working max | Detection max | Median seconds | Max seconds | Confident | Ratio pass at 2 pp |",
            "|---:|---:|---:|---:|---:|---:|"
        ]
        for dimension in dimensions {
            let subset = records.filter { $0.workingMaxDimension == dimension }
            let sortedDurations = subset.map(\.elapsedSeconds).sorted()
            let median = sortedDurations[sortedDurations.count / 2]
            let maximum = sortedDurations.max() ?? 0
            let confident = subset.filter { $0.confidenceState == CardCenteringConfidenceState.confident.rawValue }.count
            let ratioPasses = subset.filter(\.ratioPassAt2PP).count
            markdown.append(
                String(
                    format: "| %d | %d | %.3f | %.3f | %d/%d | %d/%d |",
                    dimension,
                    min(1_200, dimension),
                    median,
                    maximum,
                    confident,
                    subset.count,
                    ratioPasses,
                    subset.count
                )
            )
        }
        markdown.append(contentsOf: [
            "",
            "## Per-fixture records",
            "",
            "| Fixture | Working max | Detection max | Seconds | Working size | Card H px | State | LR error pp | TB error pp |",
            "|---|---:|---:|---:|---:|---:|---|---:|---:|"
        ])
        for record in records {
            let lr = record.lrErrorPP.map { String(format: "%.3f", $0) } ?? "—"
            let tb = record.tbErrorPP.map { String(format: "%.3f", $0) } ?? "—"
            markdown.append(
                String(
                    format: "| `%@` | %d | %d | %.3f | %dx%d | %.1f | %@ | %@ | %@ |",
                    record.fixture,
                    record.workingMaxDimension,
                    record.detectionMaxDimension,
                    record.elapsedSeconds,
                    record.workingWidth,
                    record.workingHeight,
                    record.cardHeightWorkingPx,
                    record.confidenceState,
                    lr,
                    tb
                )
            )
        }
        try Data((markdown.joined(separator: "\n") + "\n").utf8).write(
            to: output.appendingPathComponent("low-detection-curve.md"),
            options: .atomic
        )
    }
#endif

    @MainActor
    func testREQ017ManualGuidesCanRecoverADeclinedMeasurement() {
        let outer = CardCenteringQuad(
            topLeft: CardCenteringPoint(x: 0, y: 0),
            topRight: CardCenteringPoint(x: 500, y: 0),
            bottomRight: CardCenteringPoint(x: 500, y: 500),
            bottomLeft: CardCenteringPoint(x: 0, y: 500)
        )
        var declined = CardCenteringMeasurement(
            imageWidth: 1_000,
            imageHeight: 1_400,
            outerQuad: outer,
            innerQuad: nil,
            warnings: [],
            innerReference: .none
        )
        declined.refreshWarnings()

        let model = CardCenteringViewModel()
        model.measurement = declined
        let xRange = 0...999
        let yRange = 0...1_399
        model.updateOuter(\.left, to: 0, within: xRange)
        model.updateOuter(\.right, to: 700, within: xRange)
        model.updateOuter(\.top, to: 0, within: yRange)
        model.updateOuter(\.bottom, to: 980, within: yRange)
        model.updateInner(\.left, to: 70, within: xRange)
        model.updateInner(\.right, to: 630, within: xRange)
        model.updateInner(\.top, to: 98, within: yRange)
        model.updateInner(\.bottom, to: 882, within: yRange)

        let recovered = model.measurement
        XCTAssertNotNil(recovered)
        XCTAssertFalse(recovered?.isDeclined ?? true)
        XCTAssertEqual(recovered?.leftRightCentering, "50.0 / 50.0")
        XCTAssertEqual(recovered?.topBottomCentering, "50.0 / 50.0")
    }

    func testREQ024ProductionSourcesDoNotContainFixtureIdentityBranches() throws {
        let fileManager = FileManager.default
        let productionURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TradingCardScanner", isDirectory: true)
        let fixtureNames = [
            "IMG_0347", "IMG_0348", "IMG_0349", "IMG_0350", "IMG_0351",
            "IMG_0352", "IMG_0780", "IMG_0781", "IMG_0782", "IMG_0783"
        ]
        let files = try XCTUnwrap(
            fileManager.enumerator(
                at: productionURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        )

        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            for fixtureName in fixtureNames {
                XCTAssertFalse(
                    source.contains(fixtureName),
                    "production source (url.lastPathComponent) must not branch on (fixtureName)"
                )
            }
        }
    }

    func testREQ033EvidenceStatusClassifiesRecoveredRuntimeAndProvisionalGT() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let statusURL = repository
            .appendingPathComponent("review", isDirectory: true)
            .appendingPathComponent("centering-evidence", isDirectory: true)
            .appendingPathComponent("after", isDirectory: true)
            .appendingPathComponent("simulator-status-2026-09-11.md")
        let tableURL = repository
            .appendingPathComponent("review", isDirectory: true)
            .appendingPathComponent("centering-evidence", isDirectory: true)
            .appendingPathComponent("evidence-table.md")
        let status = try String(contentsOf: statusURL, encoding: .utf8)
        let table = try String(contentsOf: tableURL, encoding: .utf8)

        XCTAssertTrue(status.contains("1,076 tests; 1,045 passed; 24 failed; 7 skipped"))
        XCTAssertTrue(status.contains("EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86"))
        XCTAssertTrue(status.localizedCaseInsensitiveContains("not blocked"))
        XCTAssertTrue(table.contains("UNADJUDICATED"))
        XCTAssertTrue(table.contains("FAILING"))
        XCTAssertFalse(table.localizedCaseInsensitiveContains("OPEN — simulator unavailable"))
    }
}

#if DEBUG
private struct E0RendererMetadata: Codable {
    let sourceWidth: Double
    let sourceHeight: Double
    let canvasWidth: Double
    let canvasHeight: Double
    let scale: Double
    let rotationDegrees: Double
    let mirrorX: Bool
}

private struct E0VariantDump: Codable {
    let fixture: String
    let variant: String
    let renderer: E0RendererMetadata
    let workingWidth: Int
    let workingHeight: Int
    let outerQuadWorking: CardCenteringQuad
    let outerQuadNative: CardCenteringQuad?
    let finalAnalysis: E0FinalAnalysisDiagnostic
    let profiles: [CardCenteringProfileDiagnostic]
}

private struct E0DistanceDiagnostic: Codable {
    let left: Double
    let top: Double
    let right: Double
    let bottom: Double
}

private struct E0RectificationDiagnostic: Codable {
    let targetSize: CardCenteringSize
    let residualDegrees: Double
    let aspectResidual: Double
    let reprojectionRMS: Double
    let isValid: Bool
}

private struct E0FinalAnalysisDiagnostic: Codable {
    let measurementImageWidth: Int
    let measurementImageHeight: Int
    let appliedRotationDegrees: Double
    let detectedSkewDegrees: Double?
    let confidenceState: String
    let confidenceScore: Double
    let innerReference: String
    let confidenceReason: String?
    let detectionNotes: [String]
    let outerQuadWorking: CardCenteringQuad
    let innerQuadWorking: CardCenteringQuad?
    let outerQuadNative: CardCenteringQuad?
    let innerQuadNative: CardCenteringQuad?
    let rectifiedOuterQuad: CardCenteringQuad?
    let rectifiedInnerQuad: CardCenteringQuad?
    let borderDistances: E0DistanceDiagnostic?
    let rectification: E0RectificationDiagnostic?
    let leftRightCentering: String
    let topBottomCentering: String
    let scalarOuterAgreesWithVision: Bool
    let scalarPinned: Bool?
    let outlineHasInner: Bool
    let innerSource: CardCenteringInnerSource
    let visionOuterQuad: CardCenteringQuad?
    let scalarOuter: CardCenteringEdges?
    let scalarInner: CardCenteringEdges?
    let scalarOutlineQuad: CardCenteringQuad?
    let selectedOuterSource: String
    let selectedSleeveAmbiguity: Double
    let proposedOuterQuad: CardCenteringQuad?
    let refinedOuterQuad: CardCenteringQuad?
    let outerRefinementAccepted: Bool

    init(
        analysis: CardCenteringAnalysis,
        branch: CardCenteringAnalysisDiagnostic
    ) {
        let measurement = analysis.measurement
        let outerWorking = measurement.geometryOuterQuad
        let innerWorking = measurement.geometryInnerQuad
        let mapping = analysis.coordinateMapping
        let rectification = measurement.rectification
        let rectifiedOuter = rectification?.rectifiedQuad(from: outerWorking)
        let rectifiedInner = innerWorking.flatMap { rectification?.rectifiedQuad(from: $0) }
        let distances: E0DistanceDiagnostic?
        if let innerWorking {
            let measured = rectification.map {
                $0.rectifiedQuad(from: outerWorking).borderDistances(to: $0.rectifiedQuad(from: innerWorking))
            } ?? outerWorking.borderDistances(to: innerWorking)
            distances = E0DistanceDiagnostic(
                left: measured.left,
                top: measured.top,
                right: measured.right,
                bottom: measured.bottom
            )
        } else {
            distances = nil
        }
        self.measurementImageWidth = measurement.imageWidth
        self.measurementImageHeight = measurement.imageHeight
        self.appliedRotationDegrees = analysis.appliedRotationDegrees
        self.detectedSkewDegrees = analysis.detectedSkewDegrees
        self.confidenceState = measurement.confidence.state.rawValue
        self.confidenceScore = measurement.confidence.score
        self.innerReference = measurement.innerReference.rawValue
        self.confidenceReason = measurement.confidence.reason
        self.detectionNotes = measurement.detectionNotes
        self.outerQuadWorking = outerWorking
        self.innerQuadWorking = innerWorking
        self.outerQuadNative = mapping?.nativeQuad(fromWorking: outerWorking)
        self.innerQuadNative = innerWorking.flatMap { mapping?.nativeQuad(fromWorking: $0) }
        self.rectifiedOuterQuad = rectifiedOuter
        self.rectifiedInnerQuad = rectifiedInner
        self.borderDistances = distances
        self.rectification = rectification.map {
            E0RectificationDiagnostic(
                targetSize: $0.targetSize,
                residualDegrees: $0.residualDegrees,
                aspectResidual: $0.aspectResidual,
                reprojectionRMS: $0.reprojectionRMS,
                isValid: $0.isValid
            )
        }
        self.leftRightCentering = measurement.leftRightCentering
        self.topBottomCentering = measurement.topBottomCentering
        self.scalarOuterAgreesWithVision = branch.scalarOuterAgreesWithVision
        self.scalarPinned = branch.scalarPinned
        self.outlineHasInner = branch.outlineHasInner
        self.innerSource = branch.innerSource
        self.visionOuterQuad = branch.visionOuterQuad
        self.scalarOuter = branch.scalarOuter
        self.scalarInner = branch.scalarInner
        self.scalarOutlineQuad = branch.scalarOutlineQuad
        self.selectedOuterSource = branch.selectedOuterSource
        self.selectedSleeveAmbiguity = branch.selectedSleeveAmbiguity
        self.proposedOuterQuad = branch.proposedOuterQuad
        self.refinedOuterQuad = branch.refinedOuterQuad
        self.outerRefinementAccepted = branch.outerRefinementAccepted
    }
}

private struct EAFixtureDump: Codable {
    let fixture: String
    let finalAnalysis: E0FinalAnalysisDiagnostic
    let profileFailures: [CardCenteringProfileFailureDiagnostic]
    let profileSelections: [EAFixtureProfileSelection]
}

private struct EAFixtureProfileSelection: Codable {
    let side: String
    let selectedNormalizedDepthBeforeRefinement: Double
    let selectedNormalizedDepthAfterRefinement: Double
    let selectedScore: Double
    let selectedSupport: Double
    let threshold: Double
    let shallowCandidateCount: Int

    init(_ diagnostic: CardCenteringProfileDiagnostic) {
        side = diagnostic.side
        selectedNormalizedDepthBeforeRefinement = diagnostic.selectedNormalizedDepthBeforeRefinement
        selectedNormalizedDepthAfterRefinement = diagnostic.selectedNormalizedDepthAfterRefinement
        selectedScore = diagnostic.scores[diagnostic.selectedIndex]
        selectedSupport = diagnostic.supports[diagnostic.selectedIndex]
        threshold = diagnostic.threshold
        shallowCandidateCount = diagnostic.shallowCandidates.count
    }
}

private struct EDOuterRefinementDump: Codable {
    let fixture: String
    let reports: [CardCenteringOuterRefinementDiagnostic]
}

private struct E1ResolutionRecord: Codable {
    let fixture: String
    let variant: String
    let sourceStorageWidth: Int
    let sourceStorageHeight: Int
    let sourceDisplayWidth: Double
    let sourceDisplayHeight: Double
    let baseWorkingCardWidthPx: Double
    let baseWorkingCardHeightPx: Double
    let baseWorkingShortEdgePx: Double
    let baseWorkingLongEdgePx: Double
    let rawWorkingCardWidthPx: Double
    let rawWorkingCardHeightPx: Double
    let rawWorkingShortEdgePx: Double
    let rawWorkingLongEdgePx: Double
    let equalizedWorkingCardHeightPx: Double
    let equalizedWorkingCardWidthPx: Double
    let equalizedWorkingShortEdgePx: Double
    let equalizedWorkingLongEdgePx: Double
    let rawRelativeToBase: Double
    let equalizedRelativeToBase: Double
    let requestedScale: Double
    let equalizedScale: Double
    let rawCanvasWidth: Double
    let rawCanvasHeight: Double
    let equalizedCanvasWidth: Double
    let equalizedCanvasHeight: Double
    let rawConfidenceState: String
    let rawMeasuredLR: Double?
    let rawMeasuredTB: Double?
    let equalizedConfidenceState: String
    let equalizedMeasuredLR: Double?
    let equalizedMeasuredTB: Double?
}

private struct EENormalizationRecord: Codable {
    let fixture: String
    let variant: String
    let space: String
    let confidenceState: String
    let innerSource: String
    let outerRefinementAccepted: Bool
    let side: String
    let mappedBaseSide: String?
    let workingWidth: Int
    let workingHeight: Int
    let cardWidthWorkingPx: Double
    let cardHeightWorkingPx: Double
    let sampleRadiusPixels: Double
    let sampleRadiusNormalized: Double
    let selectedNormalizedDepthBeforeRefinement: Double
    let selectedNormalizedDepthAfterRefinement: Double
    let selectedScore: Double
    let selectedSupport: Double
    let baseline: Double
    let mad: Double
    let threshold: Double
    let shallowCandidateCount: Int
    let outerLineDisplacementPixels: Double?
    let innerLineDisplacementPixels: Double?
}

private struct EENormalizationDump: Codable {
    let fixture: String
    let variant: String
    let space: String
    let confidenceState: String
    let innerSource: String
    let outerRefinementAccepted: Bool
    let records: [EENormalizationRecord]
}

private struct E7ResolutionCurveRecord: Codable {
    let fixture: String
    let workingMaxDimension: Int
    let detectionMaxDimension: Int
    let elapsedSeconds: Double
    let workingWidth: Int
    let workingHeight: Int
    let cardHeightWorkingPx: Double
    let confidenceState: String
    let confidenceScore: Double
    let innerReference: String
    let expectedLR: Double?
    let expectedTB: Double?
    let measuredLR: Double?
    let measuredTB: Double?
    let lrErrorPP: Double?
    let tbErrorPP: Double?
    let ratioPassAt2PP: Bool
    let detectedSkewDegrees: Double?
    let appliedRotationDegrees: Double
    let rectificationResidualDegrees: Double?
    let rectificationReprojectionRMS: Double?
}

private struct REQ041StageTimingRecord: Codable {
    let fixture: String
    let repetition: Int
    let elapsedSeconds: Double
    let stageTimings: CardCenteringStageTimingDiagnostic
    let attributedFraction: Double
}

#if DEBUG
private struct REQ041ControlledABRecord: Codable {
    let arm: String
    let fixture: String
    let elapsedSeconds: Double
    let stageTimings: CardCenteringStageTimingDiagnostic
    let attributedFraction: Double
}

private struct REQ043BackIdentityRecord: Codable {
    let fixture: String
    let diagnostic: CardCenteringBackIdentityDiagnostic
}

private struct REQ044JointSelectionRecord: Codable {
    let fixture: String
    let expectedLR: Double?
    let expectedTB: Double?
    let measuredLR: Double?
    let measuredTB: Double?
    let lrErrorPP: Double?
    let tbErrorPP: Double?
    let ratioPassAt2PP: Bool
    let confidenceState: String
    let innerSource: CardCenteringInnerSource
    let diagnostic: CardCenteringJointSelectionDiagnostic?
}

private struct HybridSeedPriorRecord: Codable {
    let fixture: String
    let family: String
    let side: String
    let expectedDepth: Double
    let detectorDepth: Double
    let leaveOneOutPriorDepth: Double?
    let detectorErrorPP: Double
    let priorErrorPP: Double?
    let detectorWins: Bool?
    let priorWins: Bool?
}

private struct HybridSeedPriorSummary: Codable {
    let family: String
    let side: String
    let sampleCount: Int
    let detectorMedianErrorPP: Double
    let priorMedianErrorPP: Double
    let detectorWins: Int
    let priorWins: Int
    let ties: Int
}
#endif

private struct REQ042CandidateRecallRecord: Codable {
    let family: String
    let side: String
    let candidateCount: Int
    let bestErrorPx: Double?
    let bestSource: String?
    let bestSemanticRole: String?
    let tolerancePx: Double?
    let anyWithinTolerance: Bool?
}

private struct REQ042FixtureDiagnosticRecord: Codable {
    let fixture: String
    let groundTruthInnerReference: String
    let confidenceState: String
    let selectedInnerSource: String
    let selectedOuterSource: String
    let analysis: CardCenteringAnalysisDiagnostic
    let ledger: CardCenteringCandidateLedgerDiagnostic
    let recall: [REQ042CandidateRecallRecord]
}

/// Differential instrumentation for the current profile implementation.
/// Keep this test temporary: its purpose is to localize metamorphic drift,
/// not to become a production correctness gate.
final class CenteringProfileDumpTests: XCTestCase {
    private struct Variant {
        let name: String
        let rotationDegrees: CGFloat
        let mirrorX: Bool
        let scale: CGFloat
    }

    private let variants = [
        Variant(name: "base", rotationDegrees: 0, mirrorX: false, scale: 1),
        Variant(name: "mirrorX", rotationDegrees: 0, mirrorX: true, scale: 1),
        Variant(name: "rot90", rotationDegrees: 90, mirrorX: false, scale: 1),
        Variant(name: "rot180", rotationDegrees: 180, mirrorX: false, scale: 1),
        Variant(name: "rot270", rotationDegrees: 270, mirrorX: false, scale: 1),
        Variant(name: "scale0.6", rotationDegrees: 0, mirrorX: false, scale: 0.6)
    ]

    private func fixtureData(_ name: String) throws -> Data {
        let bundle = Bundle(for: CardCenteringGroundTruthTests.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "HEIC", subdirectory: "TradingCards/HEIC")
        )
        return try Data(contentsOf: url)
    }

    private func normalisedImage(_ data: Data) throws -> UIImage {
        let source = try XCTUnwrap(UIImage(data: data))
        let scale = min(1, 1_200 / max(source.size.width, source.size.height))
        let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func renderedVariant(
        _ data: Data,
        variant: Variant,
        appliedScale overrideScale: CGFloat? = nil,
        rawSource: Bool = false
    ) throws -> (data: Data, renderer: E0RendererMetadata) {
        let image = rawSource
            ? try XCTUnwrap(UIImage(data: data))
            : try normalisedImage(data)
        let sourceSize = image.size
        let appliedScale = overrideScale ?? variant.scale
        let drawSize = CGSize(
            width: sourceSize.width * appliedScale,
            height: sourceSize.height * appliedScale
        )
        let radians = variant.rotationDegrees * .pi / 180
        let cosine = abs(cos(radians))
        let sine = abs(sin(radians))
        let rotatedSize = CGSize(
            width: cosine * drawSize.width + sine * drawSize.height,
            height: sine * drawSize.width + cosine * drawSize.height
        )
        let margin = max(24, max(rotatedSize.width, rotatedSize.height) * 0.12)
        let canvasSize = CGSize(
            width: ceil(rotatedSize.width + margin * 2),
            height: ceil(rotatedSize.height + margin * 2)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: canvasSize, format: format).image { context in
            UIColor(white: 0.76, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))
            let cg = context.cgContext
            cg.translateBy(x: canvasSize.width / 2, y: canvasSize.height / 2)
            cg.rotate(by: radians)
            cg.scaleBy(x: variant.mirrorX ? -1 : 1, y: 1)
            image.draw(in: CGRect(
                x: -drawSize.width / 2,
                y: -drawSize.height / 2,
                width: drawSize.width,
                height: drawSize.height
            ))
        }
        return (
            try XCTUnwrap(rendered.pngData()),
            E0RendererMetadata(
                sourceWidth: sourceSize.width,
                sourceHeight: sourceSize.height,
                canvasWidth: canvasSize.width,
                canvasHeight: canvasSize.height,
                scale: appliedScale,
                rotationDegrees: variant.rotationDegrees,
                mirrorX: variant.mirrorX
            )
        )
    }

    private func fixtureRecord(_ name: String) throws -> GroundTruthRecord {
        let bundle = Bundle(for: CardCenteringGroundTruthTests.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "\(name).gt",
                withExtension: "json",
                subdirectory: "TradingCards/GroundTruth"
            )
        )
        return try JSONDecoder().decode(GroundTruthRecord.self, from: Data(contentsOf: url))
    }

    private func gtQuad(_ record: GroundTruthRecord, in sourceSize: CGSize) -> CardCenteringQuad {
        let xScale = sourceSize.width / CGFloat(record.orientedPixelSize.w)
        let yScale = sourceSize.height / CGFloat(record.orientedPixelSize.h)
        let points = record.cardOuterQuad.map {
            CardCenteringPoint(x: $0[0] * Double(xScale), y: $0[1] * Double(yScale))
        }
        return CardCenteringQuad(
            topLeft: points[0],
            topRight: points[1],
            bottomRight: points[2],
            bottomLeft: points[3]
        )
    }

    private func transformedGTQuad(
        _ record: GroundTruthRecord,
        sourceSize: CGSize,
        renderer: E0RendererMetadata,
        variant: Variant
    ) -> CardCenteringQuad {
        let sourceQuad = gtQuad(record, in: sourceSize)
        let sourceCenter = CardCenteringPoint(
            x: sourceSize.width / 2,
            y: sourceSize.height / 2
        )
        let canvasCenter = CardCenteringPoint(
            x: renderer.canvasWidth / 2,
            y: renderer.canvasHeight / 2
        )
        let radians = Double(variant.rotationDegrees) * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)

        func transform(_ point: CardCenteringPoint) -> CardCenteringPoint {
            let scaledX = (point.x - sourceCenter.x) * renderer.scale
            let scaledY = (point.y - sourceCenter.y) * renderer.scale
            let mirroredX = variant.mirrorX ? -scaledX : scaledX
            return CardCenteringPoint(
                x: canvasCenter.x + mirroredX * cosine - scaledY * sine,
                y: canvasCenter.y + mirroredX * sine + scaledY * cosine
            )
        }

        return CardCenteringQuad(
            topLeft: transform(sourceQuad.topLeft),
            topRight: transform(sourceQuad.topRight),
            bottomRight: transform(sourceQuad.bottomRight),
            bottomLeft: transform(sourceQuad.bottomLeft)
        )
    }

    private func workingGTQuad(
        _ record: GroundTruthRecord,
        sourceSize: CGSize,
        renderer: E0RendererMetadata,
        variant: Variant
    ) -> CardCenteringQuad {
        let transformed = transformedGTQuad(
            record,
            sourceSize: sourceSize,
            renderer: renderer,
            variant: variant
        )
        let workingScale = min(
            1,
            1_200 / max(renderer.canvasWidth, renderer.canvasHeight)
        )

        func scaled(_ point: CardCenteringPoint) -> CardCenteringPoint {
            CardCenteringPoint(
                x: point.x * workingScale,
                y: point.y * workingScale
            )
        }

        return CardCenteringQuad(
            topLeft: scaled(transformed.topLeft),
            topRight: scaled(transformed.topRight),
            bottomRight: scaled(transformed.bottomRight),
            bottomLeft: scaled(transformed.bottomLeft)
        )
    }

    private func equalizedScale(
        for variant: Variant,
        sourceSize: CGSize,
        record: GroundTruthRecord,
        targetWorkingShortEdge: Double
    ) -> CGFloat {
        let quad = gtQuad(record, in: sourceSize)
        let sourceShortEdge = min(quad.rectifiedWidth, quad.rectifiedHeight)

        // Once the analyzer's 1,200px cap is engaged, increasing the rendered
        // scale leaves the working card size on a plateau. Choose the first
        // scale that reaches the target instead of a binary-search endpoint
        // on that plateau. The short edge is used so a quarter-turn does not
        // appear to change resolution merely because width and height swap.
        let scaleAtTarget = targetWorkingShortEdge / sourceShortEdge
        return CGFloat(max(Double(variant.scale), scaleAtTarget))
    }

    private func edgeEndpoints(
        _ side: String,
        in quad: CardCenteringQuad
    ) -> (CardCenteringPoint, CardCenteringPoint)? {
        switch side {
        case "left": return (quad.topLeft, quad.bottomLeft)
        case "top": return (quad.topLeft, quad.topRight)
        case "right": return (quad.topRight, quad.bottomRight)
        case "bottom": return (quad.bottomLeft, quad.bottomRight)
        default: return nil
        }
    }

    private func edgePoint(
        _ side: String,
        in quad: CardCenteringQuad,
        progress: Double
    ) -> CardCenteringPoint? {
        guard let endpoints = edgeEndpoints(side, in: quad) else { return nil }
        return CardCenteringPoint(
            x: endpoints.0.x + (endpoints.1.x - endpoints.0.x) * progress,
            y: endpoints.0.y + (endpoints.1.y - endpoints.0.y) * progress
        )
    }

    private func profilePoint(
        _ diagnostic: CardCenteringProfileDiagnostic,
        progress: Double,
        normalizedDepth: Double
    ) -> CardCenteringPoint? {
        guard let endpoints = edgeEndpoints(diagnostic.side, in: diagnostic.outerQuadWorking) else {
            return nil
        }
        let tangentX = endpoints.1.x - endpoints.0.x
        let tangentY = endpoints.1.y - endpoints.0.y
        let length = max(hypot(tangentX, tangentY), .ulpOfOne)
        var normalX = -tangentY / length
        var normalY = tangentX / length
        let centre = diagnostic.outerQuadWorking.points.reduce(
            into: CardCenteringPoint(x: 0, y: 0)
        ) { result, point in
            result.x += point.x / 4
            result.y += point.y / 4
        }
        let midpoint = edgePoint(diagnostic.side, in: diagnostic.outerQuadWorking, progress: 0.5)!
        if (centre.x - midpoint.x) * normalX + (centre.y - midpoint.y) * normalY < 0 {
            normalX = -normalX
            normalY = -normalY
        }
        let origin = edgePoint(diagnostic.side, in: diagnostic.outerQuadWorking, progress: progress)!
        let axisLength = diagnostic.side == "left" || diagnostic.side == "right"
            ? diagnostic.cardWidthWorkingPx
            : diagnostic.cardHeightWorkingPx
        let distance = normalizedDepth * axisLength
        return CardCenteringPoint(
            x: origin.x + normalX * distance,
            y: origin.y + normalY * distance
        )
    }

    private func workingScale(for renderer: E0RendererMetadata) -> Double {
        min(1, 1_200 / max(renderer.canvasWidth, renderer.canvasHeight))
    }

    private func sourcePoint(
        from workingPoint: CardCenteringPoint,
        renderer: E0RendererMetadata,
        variant: Variant
    ) -> CardCenteringPoint {
        let scale = workingScale(for: renderer)
        let canvasX = workingPoint.x / scale - renderer.canvasWidth / 2
        let canvasY = workingPoint.y / scale - renderer.canvasHeight / 2
        let radians = Double(variant.rotationDegrees) * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        var unrotatedX = canvasX * cosine + canvasY * sine
        let unrotatedY = -canvasX * sine + canvasY * cosine
        if variant.mirrorX { unrotatedX = -unrotatedX }
        return CardCenteringPoint(
            x: renderer.sourceWidth / 2 + unrotatedX / renderer.scale,
            y: renderer.sourceHeight / 2 + unrotatedY / renderer.scale
        )
    }

    private func baseWorkingPoint(
        from sourcePoint: CardCenteringPoint,
        renderer: E0RendererMetadata
    ) -> CardCenteringPoint {
        let x = renderer.canvasWidth / 2
            + (sourcePoint.x - renderer.sourceWidth / 2) * renderer.scale
        let y = renderer.canvasHeight / 2
            + (sourcePoint.y - renderer.sourceHeight / 2) * renderer.scale
        let scale = workingScale(for: renderer)
        return CardCenteringPoint(x: x * scale, y: y * scale)
    }

    private func canonicalWorkingPoint(
        _ point: CardCenteringPoint,
        renderer: E0RendererMetadata,
        variant: Variant,
        baseRenderer: E0RendererMetadata
    ) -> CardCenteringPoint {
        baseWorkingPoint(
            from: sourcePoint(from: point, renderer: renderer, variant: variant),
            renderer: baseRenderer
        )
    }

    private func pointDistance(_ lhs: CardCenteringPoint, _ rhs: CardCenteringPoint) -> Double {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func distanceToSegment(
        _ point: CardCenteringPoint,
        _ start: CardCenteringPoint,
        _ end: CardCenteringPoint
    ) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > .ulpOfOne else { return pointDistance(point, start) }
        let amount = Swift.min(
            1,
            Swift.max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared)
        )
        return pointDistance(
            point,
            CardCenteringPoint(x: start.x + dx * amount, y: start.y + dy * amount)
        )
    }

    private func nearestBaseSide(
        for point: CardCenteringPoint,
        in quad: CardCenteringQuad
    ) -> String? {
        let sides = ["left", "top", "right", "bottom"]
        return sides.min { lhs, rhs in
            let lhsEndpoints = edgeEndpoints(lhs, in: quad)!
            let rhsEndpoints = edgeEndpoints(rhs, in: quad)!
            return distanceToSegment(point, lhsEndpoints.0, lhsEndpoints.1)
                < distanceToSegment(point, rhsEndpoints.0, rhsEndpoints.1)
        }
    }

    private func lineDisplacement(
        for diagnostic: CardCenteringProfileDiagnostic,
        inner: Bool,
        baseProfiles: [String: CardCenteringProfileDiagnostic],
        baseOuter: CardCenteringQuad,
        renderer: E0RendererMetadata,
        variant: Variant,
        baseRenderer: E0RendererMetadata
    ) -> (side: String?, displacement: Double?) {
        let progressValues = [0.15, 0.50, 0.85]
        let variantPoints: [CardCenteringPoint]
        if inner {
            variantPoints = progressValues.compactMap {
                profilePoint(
                    diagnostic,
                    progress: $0,
                    normalizedDepth: diagnostic.selectedNormalizedDepthAfterRefinement
                )
            }
        } else {
            variantPoints = progressValues.compactMap {
                edgePoint(diagnostic.side, in: diagnostic.outerQuadWorking, progress: $0)
            }
        }
        guard variantPoints.count == progressValues.count else { return (nil, nil) }
        let canonicalPoints = variantPoints.map {
            canonicalWorkingPoint(
                $0,
                renderer: renderer,
                variant: variant,
                baseRenderer: baseRenderer
            )
        }
        guard let baseSide = nearestBaseSide(for: canonicalPoints[1], in: baseOuter) else {
            return (nil, nil)
        }
        let expectedPoints: [CardCenteringPoint]
        if inner {
            guard let baseDiagnostic = baseProfiles[baseSide] else { return (baseSide, nil) }
            expectedPoints = progressValues.compactMap {
                profilePoint(
                    baseDiagnostic,
                    progress: $0,
                    normalizedDepth: baseDiagnostic.selectedNormalizedDepthAfterRefinement
                )
            }
        } else {
            expectedPoints = progressValues.compactMap {
                edgePoint(baseSide, in: baseOuter, progress: $0)
            }
        }
        guard expectedPoints.count == progressValues.count else { return (baseSide, nil) }

        let direct = zip(canonicalPoints, expectedPoints)
            .map { pointDistance($0.0, $0.1) }
            .reduce(0, +) / Double(progressValues.count)
        let reversed = zip(canonicalPoints, expectedPoints.reversed())
            .map { pointDistance($0.0, $0.1) }
            .reduce(0, +) / Double(progressValues.count)
        return (baseSide, min(direct, reversed))
    }

    private func measurementSnapshot(_ data: Data) throws -> (
        state: String,
        lr: Double?,
        tb: Double?
    ) {
        let measurement = try CardCenteringAnalyzer.analyze(data).measurement
        guard let inner = measurement.geometryInnerQuad else {
            return (measurement.confidence.state.rawValue, nil, nil)
        }
        let distances = measurement.geometryOuterQuad.borderDistances(to: inner)
        return (
            measurement.confidence.state.rawValue,
            100 * distances.left / max(distances.left + distances.right, .ulpOfOne),
            100 * distances.top / max(distances.top + distances.bottom, .ulpOfOne)
        )
    }

    private func outputDirectory() throws -> URL {
        try centeringDiagnosticDirectory("E0")
    }

    func testDumpDifferentialProfilesForCleanAndSleevedFixtures() throws {
        let output = try outputDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var allDumps: [E0VariantDump] = []

        for fixture in ["IMG_0783", "IMG_0347"] {
            let data = try fixtureData(fixture)
            for variant in variants {
                let rendered = try renderedVariant(data, variant: variant)
                var captured: [CardCenteringProfileDiagnostic] = []
                var capturedBranch: CardCenteringAnalysisDiagnostic?
                CardCenteringAnalyzer.profileDiagnosticSink = { diagnostic in
                    captured.append(diagnostic)
                }
                CardCenteringAnalyzer.analysisDiagnosticSink = { diagnostic in
                    capturedBranch = diagnostic
                }
                let analysis: CardCenteringAnalysis
                defer {
                    CardCenteringAnalyzer.profileDiagnosticSink = nil
                    CardCenteringAnalyzer.analysisDiagnosticSink = nil
                }
                analysis = try CardCenteringAnalyzer.analyze(rendered.data)
                let mapping = analysis.coordinateMapping
                let branch = try XCTUnwrap(
                    capturedBranch,
                    "E0 must capture the final analyzer branch for (fixture) / (variant.name)"
                )
                let dump = E0VariantDump(
                    fixture: fixture,
                    variant: variant.name,
                    renderer: rendered.renderer,
                    workingWidth: analysis.measurement.imageWidth,
                    workingHeight: analysis.measurement.imageHeight,
                    outerQuadWorking: captured.first?.outerQuadWorking
                        ?? analysis.measurement.geometryOuterQuad,
                    outerQuadNative: captured.first.flatMap { diagnostic in
                        mapping?.nativeQuad(fromWorking: diagnostic.outerQuadWorking)
                    },
                    finalAnalysis: E0FinalAnalysisDiagnostic(
                        analysis: analysis,
                        branch: branch
                    ),
                    profiles: captured
                )
                let url = output.appendingPathComponent("\(fixture)_\(variant.name).json")
                try encoder.encode(dump).write(to: url, options: .atomic)
                allDumps.append(dump)
                XCTAssertEqual(
                    Set(captured.map(\.side)),
                    Set(["left", "top", "right", "bottom"]),
                    "E0 must capture all four edges for \(fixture) / \(variant.name)"
                )
                print(
                    "E0_DUMP fixture=\(fixture) variant=\(variant.name) "
                        + "working=\(dump.workingWidth)x\(dump.workingHeight) "
                        + "profiles=\(captured.count)"
                )
            }
        }

        let manifestURL = output.appendingPathComponent("manifest.json")
        try encoder.encode(allDumps).write(to: manifestURL, options: .atomic)
    }

    func testEADiagnoseInnerReferenceBranchForAllRealFixtures() throws {
        let output = try centeringDiagnosticDirectory("EA")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let fixtures = [
            "IMG_0347", "IMG_0348", "IMG_0349", "IMG_0350", "IMG_0351",
            "IMG_0352", "IMG_0780", "IMG_0781", "IMG_0782", "IMG_0783"
        ]
        var dumps: [EAFixtureDump] = []

        for fixture in fixtures {
            var capturedBranch: CardCenteringAnalysisDiagnostic?
            var capturedFailures: [CardCenteringProfileFailureDiagnostic] = []
            var capturedProfiles: [CardCenteringProfileDiagnostic] = []
            CardCenteringAnalyzer.profileDiagnosticSink = { diagnostic in
                capturedProfiles.append(diagnostic)
            }
            CardCenteringAnalyzer.profileFailureDiagnosticSink = { diagnostic in
                capturedFailures.append(diagnostic)
            }
            CardCenteringAnalyzer.analysisDiagnosticSink = { diagnostic in
                capturedBranch = diagnostic
            }
            defer {
                CardCenteringAnalyzer.analysisDiagnosticSink = nil
                CardCenteringAnalyzer.profileDiagnosticSink = nil
                CardCenteringAnalyzer.profileFailureDiagnosticSink = nil
            }
            let analysis = try CardCenteringAnalyzer.analyze(try fixtureData(fixture))
            let branch = try XCTUnwrap(
                capturedBranch,
                "E-A must capture the final analyzer branch for " + fixture
            )
            let dump = EAFixtureDump(
                fixture: fixture,
                finalAnalysis: E0FinalAnalysisDiagnostic(
                    analysis: analysis,
                    branch: branch
                ),
                profileFailures: capturedFailures,
                profileSelections: capturedProfiles.map(EAFixtureProfileSelection.init)
            )
            try encoder.encode(dump).write(
                to: output.appendingPathComponent(fixture + ".json"),
                options: .atomic
            )
            dumps.append(dump)
            let scalarPinned = dump.finalAnalysis.scalarPinned.map { String($0) } ?? "nil"
            print(
                "E-A fixture=\(fixture) "
                    + "state=\(dump.finalAnalysis.confidenceState) "
                    + "innerReference=\(dump.finalAnalysis.innerReference) "
                    + "innerSource=\(dump.finalAnalysis.innerSource.rawValue) "
                    + "scalarAgrees=\(dump.finalAnalysis.scalarOuterAgreesWithVision) "
                    + "scalarPinned=\(scalarPinned) "
                    + "outlineHasInner=\(dump.finalAnalysis.outlineHasInner) "
                    + "profileFailures=\(dump.profileFailures.map { $0.reason }.joined(separator: ","))"
            )
        }

        try encoder.encode(dumps).write(
            to: output.appendingPathComponent("summary.json"),
            options: .atomic
        )
        XCTAssertEqual(dumps.count, fixtures.count)
    }

    func testEBSleevedFixturesAcquireIndependentInnerEvidence() throws {
        let fixtures = [
            "IMG_0347", "IMG_0349", "IMG_0350", "IMG_0351", "IMG_0352"
        ]
        for fixture in fixtures {
            let analysis = try CardCenteringAnalyzer.analyze(try fixtureData(fixture))
            XCTAssertNotEqual(
                analysis.measurement.innerReference,
                .none,
                "E-B (fixture) must not lose its inner reference solely because scalar evidence is pinned"
            )
            XCTAssertNotNil(
                analysis.measurement.geometryInnerQuad,
                "E-B (fixture) must expose the independently measured inner quad"
            )
        }
    }

    func testEDumpOuterRefinementDecisionsForAllRealFixtures() throws {
        let output = try centeringDiagnosticDirectory("ED")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let fixtures = [
            "IMG_0347", "IMG_0348", "IMG_0349", "IMG_0350", "IMG_0351",
            "IMG_0352", "IMG_0780", "IMG_0781", "IMG_0782", "IMG_0783"
        ]
        var dumps: [EDOuterRefinementDump] = []

        for fixture in fixtures {
            var reports: [CardCenteringOuterRefinementDiagnostic] = []
            CardCenteringAnalyzer.outerRefinementDiagnosticSink = { reports.append($0) }
            defer { CardCenteringAnalyzer.outerRefinementDiagnosticSink = nil }
            _ = try CardCenteringAnalyzer.analyze(try fixtureData(fixture))
            let dump = EDOuterRefinementDump(fixture: fixture, reports: reports)
            try encoder.encode(dump).write(
                to: output.appendingPathComponent(fixture + "-outer-refinement.json"),
                options: .atomic
            )
            dumps.append(dump)
            func median(_ values: [Double]) -> String {
                guard !values.isEmpty else { return "nil" }
                let sorted = values.sorted()
                let middle = sorted.count / 2
                let value = sorted.count.isMultiple(of: 2)
                    ? (sorted[middle - 1] + sorted[middle]) / 2
                    : sorted[middle]
                return String(format: "%.3f", value)
            }
            for report in reports {
                let offsetMedianText = report.offsetMedian.map { String(format: "%.2f", $0) } ?? "nil"
                print(
                    "E-D-OUTER fixture=\(fixture) side=\(report.side) "
                        + "accepted=\(report.accepted) median=\(offsetMedianText) "
                        + "width=\(median(report.acceptedTransitionWidths)) "
                        + "contrast=\(median(report.acceptedContrastDeltas)) "
                        + "strength=\(median(report.acceptedStrengths)) "
                        + "count=\(report.acceptedOffsets.count)/\(report.minimumAccepted) "
                        + "guard=\(String(format: "%.2f", report.maximumLocalOffset)) "
                        + "reason=\(report.reason ?? "none")"
                )
            }
        }

        try encoder.encode(dumps).write(
            to: output.appendingPathComponent("outer-refinement.json"),
            options: .atomic
        )
        XCTAssertEqual(dumps.count, fixtures.count)
    }

    func testREQ044OuterRefinementRejectsBroadAmbiguousTransitions() throws {
        let fixtures = ["IMG_0347", "IMG_0350"]

        for fixture in fixtures {
            var reports: [CardCenteringOuterRefinementDiagnostic] = []
            CardCenteringAnalyzer.outerRefinementDiagnosticSink = { reports.append($0) }
            defer { CardCenteringAnalyzer.outerRefinementDiagnosticSink = nil }

            _ = try CardCenteringAnalyzer.analyze(try fixtureData(fixture))

            let left = try XCTUnwrap(
                reports.first(where: { $0.side == GroundTruthSide.left.rawValue }),
                fixture
            )
            XCTAssertFalse(
                left.accepted,
                "REQ-044 must reject the broad ambiguous left transition for (fixture)"
            )
        }
    }

    func testE1MetamorphicVariantsCanBeResolutionEqualizedFromRawHEIC() throws {
        let output = try centeringDiagnosticDirectory("E1")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var records: [E1ResolutionRecord] = []

        for fixture in ["IMG_0783", "IMG_0347"] {
            let data = try fixtureData(fixture)
            let source = try XCTUnwrap(UIImage(data: data))
            let storageWidth = try XCTUnwrap(source.cgImage).width
            let storageHeight = try XCTUnwrap(source.cgImage).height
            let groundTruth = try fixtureRecord(fixture)
            let baseVariant = try XCTUnwrap(variants.first)
            let baseRendered = try renderedVariant(
                data,
                variant: baseVariant,
                rawSource: true
            )
            let baseQuad = workingGTQuad(
                groundTruth,
                sourceSize: source.size,
                renderer: baseRendered.renderer,
                variant: baseVariant
            )
            let baseWidth = baseQuad.rectifiedWidth
            let baseHeight = baseQuad.rectifiedHeight
            let baseShortEdge = min(baseWidth, baseHeight)
            let baseLongEdge = max(baseWidth, baseHeight)

            for variant in variants {
                // Every variant starts from the original HEIC bytes. The
                // UIImage draw preserves the fixture's declared display
                // orientation, while the renderer applies only the requested
                // metamorphic transform.
                let rawRendered = try renderedVariant(
                    data,
                    variant: variant,
                    rawSource: true
                )
                let rawQuad = workingGTQuad(
                    groundTruth,
                    sourceSize: source.size,
                    renderer: rawRendered.renderer,
                    variant: variant
                )
                let rawWidth = rawQuad.rectifiedWidth
                let rawHeight = rawQuad.rectifiedHeight
                let rawShortEdge = min(rawWidth, rawHeight)
                let rawLongEdge = max(rawWidth, rawHeight)
                let scale = equalizedScale(
                    for: variant,
                    sourceSize: source.size,
                    record: groundTruth,
                    targetWorkingShortEdge: baseShortEdge
                )
                let equalized = try renderedVariant(
                    data,
                    variant: variant,
                    appliedScale: scale,
                    rawSource: true
                )
                let equalizedQuad = workingGTQuad(
                    groundTruth,
                    sourceSize: source.size,
                    renderer: equalized.renderer,
                    variant: variant
                )
                let equalizedWidth = equalizedQuad.rectifiedWidth
                let equalizedHeight = equalizedQuad.rectifiedHeight
                let equalizedShortEdge = min(equalizedWidth, equalizedHeight)
                let equalizedLongEdge = max(equalizedWidth, equalizedHeight)
                let equalizedError = abs(equalizedShortEdge - baseShortEdge) / baseShortEdge
                XCTAssertLessThanOrEqual(
                    equalizedError,
                    0.005,
                    "GT-derived working card short-edge drift for \(fixture)/\(variant.name)"
                )
                let rawMeasurement = try measurementSnapshot(rawRendered.data)
                let equalizedMeasurement = try measurementSnapshot(equalized.data)
                records.append(
                    E1ResolutionRecord(
                        fixture: fixture,
                        variant: variant.name,
                        sourceStorageWidth: storageWidth,
                        sourceStorageHeight: storageHeight,
                        sourceDisplayWidth: source.size.width,
                        sourceDisplayHeight: source.size.height,
                        baseWorkingCardWidthPx: baseWidth,
                        baseWorkingCardHeightPx: baseHeight,
                        baseWorkingShortEdgePx: baseShortEdge,
                        baseWorkingLongEdgePx: baseLongEdge,
                        rawWorkingCardWidthPx: rawWidth,
                        rawWorkingCardHeightPx: rawHeight,
                        rawWorkingShortEdgePx: rawShortEdge,
                        rawWorkingLongEdgePx: rawLongEdge,
                        equalizedWorkingCardHeightPx: equalizedHeight,
                        equalizedWorkingCardWidthPx: equalizedWidth,
                        equalizedWorkingShortEdgePx: equalizedShortEdge,
                        equalizedWorkingLongEdgePx: equalizedLongEdge,
                        rawRelativeToBase: rawShortEdge / baseShortEdge,
                        equalizedRelativeToBase: equalizedShortEdge / baseShortEdge,
                        requestedScale: Double(variant.scale),
                        equalizedScale: Double(scale),
                        rawCanvasWidth: rawRendered.renderer.canvasWidth,
                        rawCanvasHeight: rawRendered.renderer.canvasHeight,
                        equalizedCanvasWidth: equalized.renderer.canvasWidth,
                        equalizedCanvasHeight: equalized.renderer.canvasHeight,
                        rawConfidenceState: rawMeasurement.state,
                        rawMeasuredLR: rawMeasurement.lr,
                        rawMeasuredTB: rawMeasurement.tb,
                        equalizedConfidenceState: equalizedMeasurement.state,
                        equalizedMeasuredLR: equalizedMeasurement.lr,
                        equalizedMeasuredTB: equalizedMeasurement.tb
                    )
                )
                print(
                    "E1_RAW_EQ fixture=\(fixture) variant=\(variant.name) "
                        + String(format: "rawShort=%.1f equalizedShort=%.1f baseShort=%.1f", rawShortEdge, equalizedShortEdge, baseShortEdge)
                        + " rawState=\(rawMeasurement.state) equalizedState=\(equalizedMeasurement.state)"
                )
            }
        }
        try encoder.encode(records).write(
            to: output.appendingPathComponent("resolution.json"),
            options: .atomic
        )
    }

    func testEEDumpPostRefinementProfileNormalization() throws {
        let output = try centeringDiagnosticDirectory("ED")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var dumps: [EENormalizationDump] = []

        func capture(_ data: Data) throws -> (
            analysis: CardCenteringAnalysis,
            branch: CardCenteringAnalysisDiagnostic,
            profiles: [CardCenteringProfileDiagnostic]
        ) {
            var branch: CardCenteringAnalysisDiagnostic?
            var profiles: [CardCenteringProfileDiagnostic] = []
            CardCenteringAnalyzer.analysisDiagnosticSink = { branch = $0 }
            CardCenteringAnalyzer.profileDiagnosticSink = { profiles.append($0) }
            defer {
                CardCenteringAnalyzer.analysisDiagnosticSink = nil
                CardCenteringAnalyzer.profileDiagnosticSink = nil
            }
            let analysis = try CardCenteringAnalyzer.analyze(data)
            return (
                analysis,
                try XCTUnwrap(branch, "E-E must capture the final analyzer branch"),
                profiles
            )
        }

        for fixture in ["IMG_0783", "IMG_0347"] {
            let data = try fixtureData(fixture)
            let source = try XCTUnwrap(UIImage(data: data))
            let groundTruth = try fixtureRecord(fixture)
            let baseVariant = try XCTUnwrap(variants.first)
            let baseRendered = try renderedVariant(data, variant: baseVariant, rawSource: true)
            let baseCaptured = try capture(baseRendered.data)
            let baseProfiles = Dictionary(
                uniqueKeysWithValues: baseCaptured.profiles.map { ($0.side, $0) }
            )
            let baseOuter = try XCTUnwrap(baseCaptured.profiles.first?.outerQuadWorking)
            let baseWidth = workingGTQuad(
                groundTruth,
                sourceSize: source.size,
                renderer: baseRendered.renderer,
                variant: baseVariant
            ).rectifiedWidth
            let baseHeight = workingGTQuad(
                groundTruth,
                sourceSize: source.size,
                renderer: baseRendered.renderer,
                variant: baseVariant
            ).rectifiedHeight
            let baseShortEdge = min(baseWidth, baseHeight)

            for variant in variants {
                let raw = try renderedVariant(data, variant: variant, rawSource: true)
                let equalizedScale = equalizedScale(
                    for: variant,
                    sourceSize: source.size,
                    record: groundTruth,
                    targetWorkingShortEdge: baseShortEdge
                )
                let equalized = try renderedVariant(
                    data,
                    variant: variant,
                    appliedScale: equalizedScale,
                    rawSource: true
                )

                for (space, rendered) in [("raw", raw), ("equalized", equalized)] {
                    let captured = try capture(rendered.data)
                    let confidenceState = captured.analysis.measurement.confidence.state.rawValue
                    let innerSource = captured.analysis.measurement.innerReference.rawValue
                    let records = captured.profiles.map { diagnostic in
                        let outerDisplacement = lineDisplacement(
                            for: diagnostic,
                            inner: false,
                            baseProfiles: baseProfiles,
                            baseOuter: baseOuter,
                            renderer: rendered.renderer,
                            variant: variant,
                            baseRenderer: baseRendered.renderer
                        )
                        let innerDisplacement = lineDisplacement(
                            for: diagnostic,
                            inner: true,
                            baseProfiles: baseProfiles,
                            baseOuter: baseOuter,
                            renderer: rendered.renderer,
                            variant: variant,
                            baseRenderer: baseRendered.renderer
                        )
                        return EENormalizationRecord(
                            fixture: fixture,
                            variant: variant.name,
                            space: space,
                            confidenceState: confidenceState,
                            innerSource: innerSource,
                            outerRefinementAccepted: captured.branch.outerRefinementAccepted,
                            side: diagnostic.side,
                            mappedBaseSide: innerDisplacement.side ?? outerDisplacement.side,
                            workingWidth: diagnostic.workingWidth,
                            workingHeight: diagnostic.workingHeight,
                            cardWidthWorkingPx: diagnostic.cardWidthWorkingPx,
                            cardHeightWorkingPx: diagnostic.cardHeightWorkingPx,
                            sampleRadiusPixels: diagnostic.sampleRadiusPixels,
                            sampleRadiusNormalized: diagnostic.sampleRadiusNormalized,
                            selectedNormalizedDepthBeforeRefinement: diagnostic.selectedNormalizedDepthBeforeRefinement,
                            selectedNormalizedDepthAfterRefinement: diagnostic.selectedNormalizedDepthAfterRefinement,
                            selectedScore: diagnostic.scores[diagnostic.selectedIndex],
                            selectedSupport: diagnostic.supports[diagnostic.selectedIndex],
                            baseline: diagnostic.baseline,
                            mad: diagnostic.mad,
                            threshold: diagnostic.threshold,
                            shallowCandidateCount: diagnostic.shallowCandidates.count,
                            outerLineDisplacementPixels: outerDisplacement.displacement,
                            innerLineDisplacementPixels: innerDisplacement.displacement
                        )
                    }
                    XCTAssertEqual(
                        records.count,
                        4,
                        "E-E must retain all four edge profiles for \(fixture)/\(variant.name)/\(space)"
                    )
                    dumps.append(
                        EENormalizationDump(
                            fixture: fixture,
                            variant: variant.name,
                            space: space,
                            confidenceState: confidenceState,
                            innerSource: innerSource,
                            outerRefinementAccepted: captured.branch.outerRefinementAccepted,
                            records: records
                        )
                    )
                    print(
                        "E-E fixture=\(fixture) variant=\(variant.name) space=\(space) "
                            + "state=\(confidenceState) profiles=\(records.count)"
                    )
                }
            }
        }

        XCTAssertEqual(dumps.count, 24)
        XCTAssertEqual(dumps.flatMap(\.records).count, 96)
        try encoder.encode(dumps).write(
            to: output.appendingPathComponent("profile-normalization.json"),
            options: .atomic
        )

        var markdown = [
            "# E-E post-refinement profile normalization",
            "",
            "Raw and effective-resolution-equalized variants start from the original HEIC bytes.",
            "The records are diagnostic only while REQ-027 ground truth remains provisional.",
            "",
            "| Fixture | Variant | Space | State | Side | Base side | Depth before | Depth after | Support | Threshold | Outer Δ px | Inner Δ px |",
            "|---|---|---|---|---|---|---:|---:|---:|---:|---:|---:|"
        ]
        for dump in dumps {
            for record in dump.records {
                let baseSide = record.mappedBaseSide ?? "—"
                let outer = record.outerLineDisplacementPixels.map { String(format: "%.3f", $0) } ?? "—"
                let inner = record.innerLineDisplacementPixels.map { String(format: "%.3f", $0) } ?? "—"
                markdown.append(
                    String(
                        format: "| %@ | %@ | %@ | %@ | %@ | %@ | %.6f | %.6f | %.3f | %.3f | %@ | %@ |",
                        record.fixture,
                        record.variant,
                        record.space,
                        record.confidenceState,
                        record.side,
                        baseSide,
                        record.selectedNormalizedDepthBeforeRefinement,
                        record.selectedNormalizedDepthAfterRefinement,
                        record.selectedSupport,
                        record.threshold,
                        outer,
                        inner
                    )
                )
            }
        }
        try Data((markdown.joined(separator: "\n") + "\n").utf8).write(
            to: output.appendingPathComponent("profile-normalization.md"),
            options: .atomic
        )
    }

    func testEDOuterProposalIsReplacedByDeterministicRefinement() throws {
        var captured: CardCenteringAnalysisDiagnostic?
        CardCenteringAnalyzer.analysisDiagnosticSink = { diagnostic in
            captured = diagnostic
        }
        defer { CardCenteringAnalyzer.analysisDiagnosticSink = nil }

        _ = try CardCenteringAnalyzer.analyze(try fixtureData("IMG_0783"))
        let diagnostic = try XCTUnwrap(captured)
        XCTAssertNotNil(diagnostic.proposedOuterQuad)
        XCTAssertTrue(
            diagnostic.outerRefinementAccepted,
            "E-D must replace the Vision outer proposal with a deterministic edge fit"
        )
        XCTAssertNotNil(diagnostic.refinedOuterQuad)
    }
}
#endif

private enum GroundTruthSide: String, CaseIterable {
    case left, top, right, bottom
}

private func groundTruthEdgeTolerance(
    _ record: GroundTruthRecord,
    side: GroundTruthSide,
    cardHeight: Double
) -> Double {
    let measuredBand = record.edgeBands[side.rawValue] ?? 0
    let minimum = cardHeight * 0.0025
    let maximum = cardHeight * 0.01
    let clampedBand = min(max(measuredBand, minimum), maximum)
    return record.ambiguousEdges.contains(side.rawValue)
        ? max(measuredBand, clampedBand)
        : clampedBand
}

private func edgeEndpoints(
    _ quad: CardCenteringQuad,
    side: GroundTruthSide
) -> (CardCenteringPoint, CardCenteringPoint) {
    switch side {
    case .left: (quad.topLeft, quad.bottomLeft)
    case .top: (quad.topLeft, quad.topRight)
    case .right: (quad.topRight, quad.bottomRight)
    case .bottom: (quad.bottomLeft, quad.bottomRight)
    }
}

/// Signed displacement of the detected edge midpoint along the normal of the
/// independently annotated GT edge. The sign is useful when inspecting a
/// failure; the L1 gate applies the absolute magnitude.
private func signedNormalOffset(
    _ detected: CardCenteringQuad,
    from expected: CardCenteringQuad,
    side: GroundTruthSide
) -> Double {
    let expectedEdge = edgeEndpoints(expected, side: side)
    let detectedEdge = edgeEndpoints(detected, side: side)
    let dx = expectedEdge.1.x - expectedEdge.0.x
    let dy = expectedEdge.1.y - expectedEdge.0.y
    let length = hypot(dx, dy)
    guard length > .ulpOfOne else { return .infinity }
    let expectedMid = CardCenteringPoint(
        x: (expectedEdge.0.x + expectedEdge.1.x) / 2,
        y: (expectedEdge.0.y + expectedEdge.1.y) / 2
    )
    let detectedMid = CardCenteringPoint(
        x: (detectedEdge.0.x + detectedEdge.1.x) / 2,
        y: (detectedEdge.0.y + detectedEdge.1.y) / 2
    )
    let normalX = -dy / length
    let normalY = dx / length
    return (detectedMid.x - expectedMid.x) * normalX
        + (detectedMid.y - expectedMid.y) * normalY
}

private func averagePoint(_ quad: CardCenteringQuad) -> CardCenteringPoint {
    let points = quad.points
    return CardCenteringPoint(
        x: points.map(\.x).reduce(0, +) / Double(points.count),
        y: points.map(\.y).reduce(0, +) / Double(points.count)
    )
}

final class CardCenteringCorpusManifestTests: XCTestCase {
    private let historicalFiles: Set<String> = [
        "IMG_0347.HEIC", "IMG_0348.HEIC", "IMG_0349.HEIC", "IMG_0350.HEIC",
        "IMG_0351.HEIC", "IMG_0352.HEIC", "IMG_0780.HEIC", "IMG_0781.HEIC",
        "IMG_0782.HEIC", "IMG_0783.HEIC"
    ]

    private let newFiles: Set<String> = [
        "Document_2026-06-06_150110.png", "Document_2026-06-06_150759.png",
        "Document_2026-06-06_151610.png", "Document_2026-06-06_152530.png",
        "Document_2026-06-06_153042.png", "Document_2026-06-06_174520.png",
        "Document_2026-06-06_175439.png", "Document_2026-06-08_084920.png",
        "Document_2026-06-08_085837.png", "Document_2026-06-08_090644.png",
        "Document_2026-06-08_091509.png", "IMG_0795.HEIC", "IMG_0796.HEIC",
        "IMG_0797.HEIC", "IMG_0798.HEIC", "IMG_0799.HEIC", "IMG_0800.HEIC",
        "IMG_0801.HEIC", "IMG_0802.HEIC", "IMG_0803.HEIC", "IMG_0804.HEIC",
        "IMG_0809.HEIC", "IMG_0810.HEIC", "IMG_0811.HEIC", "IMG_0813.HEIC",
        "IMG_0856.HEIC", "IMG_1023.HEIC", "IMG_1036.HEIC", "IMG_1038.HEIC",
        "IMG_1302.HEIC", "IMG_1475-2.HEIC", "IMG_1477-2.HEIC", "IMG_1712.HEIC",
        "IMG_1716.HEIC"
    ]

    private let interimHoldoutFiles: Set<String> = [
        "Document_2026-06-06_150110.png", "Document_2026-06-08_091509.png",
        "IMG_0796.HEIC", "IMG_0804.HEIC", "IMG_0856.HEIC", "IMG_1023.HEIC",
        "IMG_1036.HEIC", "IMG_1302.HEIC", "IMG_1475-2.HEIC", "IMG_1716.HEIC"
    ]

    func testCorpusManifestIsCompleteAndCryptographicallyFrozen() throws {
        let bundle = Bundle(for: CardCenteringCorpusManifestTests.self)
        let manifestURL = try XCTUnwrap(
            bundle.url(
                forResource: "corpus-manifest",
                withExtension: "json",
                subdirectory: "TradingCards/Supplementary"
            ),
            "missing supplementary corpus manifest"
        )
        let manifest = try JSONDecoder().decode(
            CenteringCorpusManifest.self,
            from: Data(contentsOf: manifestURL)
        )

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.status, "interim_holdout_frozen")
        XCTAssertEqual(manifest.entries.count, historicalFiles.count + newFiles.count)
        XCTAssertEqual(manifest.holdoutFreeze.freezeId, "card-centering-holdout-interim-2026-09-20")
        XCTAssertEqual(manifest.holdoutFreeze.frozenAt, "2026-09-20")
        XCTAssertEqual(manifest.holdoutFreeze.split, "HOLDOUT-INTERIM")
        XCTAssertEqual(manifest.holdoutFreeze.selectedCount, interimHoldoutFiles.count)
        XCTAssertTrue(manifest.holdoutFreeze.selectedBeforePerceptionChanges)
        XCTAssertEqual(manifest.holdoutFreeze.analysisStatus, "sealed_not_evaluated")
        XCTAssertEqual(manifest.holdoutFreeze.groundTruthStatus, "not_assigned")
        XCTAssertEqual(manifest.holdoutFreeze.captureCohortCount, 9)
        XCTAssertEqual(Set(manifest.holdoutFreeze.formatSet), Set(["heic", "png"]))
        XCTAssertEqual(manifest.holdoutFreeze.finalREQ040Gate, "open")
        XCTAssertEqual(
            Set(manifest.holdoutFreeze.limitations),
            Set([
                "known_camera_captures_share_one_iPhone_15_Pro_Max",
                "PNG_capture_role_is_unknown",
                "no_new_ground_truth"
            ])
        )

        let entriesByFile = Dictionary(uniqueKeysWithValues: manifest.entries.map { ($0.file, $0) })
        XCTAssertEqual(Set(entriesByFile.keys), historicalFiles.union(newFiles))
        XCTAssertEqual(
            Set(manifest.entries.filter { $0.split == "DEV-HISTORICAL" }.map(\.file)),
            historicalFiles
        )
        XCTAssertEqual(
            Set(manifest.entries.filter { $0.split == "HOLDOUT-INTERIM" }.map(\.file)),
            interimHoldoutFiles
        )
        XCTAssertEqual(
            manifest.entries.filter { $0.split == "DEVELOPMENT" }.count,
            newFiles.count - interimHoldoutFiles.count
        )

        for entry in manifest.entries {
            XCTAssertEqual(entry.root, "TestFixtures/TradingCards/HEIC", entry.file)
            XCTAssertEqual(entry.sha256.count, 64, entry.file)
            XCTAssertTrue(entry.sha256.allSatisfy(\.isHexDigit), entry.file)
            XCTAssertGreaterThan(entry.width, 0, entry.file)
            XCTAssertGreaterThan(entry.height, 0, entry.file)
            XCTAssertFalse(entry.captureCohort.isEmpty, entry.file)
            XCTAssertFalse(entry.provenance.isEmpty, entry.file)
            XCTAssertFalse(entry.face.isEmpty, entry.file)
            XCTAssertFalse(entry.referenceClass.isEmpty, entry.file)
            XCTAssertFalse(entry.encasement.isEmpty, entry.file)
            XCTAssertFalse(entry.background.isEmpty, entry.file)
            XCTAssertFalse(entry.finish.isEmpty, entry.file)

            let fileURL = try XCTUnwrap(
                bundle.url(
                    forResource: URL(fileURLWithPath: entry.file).deletingPathExtension().lastPathComponent,
                    withExtension: URL(fileURLWithPath: entry.file).pathExtension,
                    subdirectory: "TradingCards/HEIC"
                ),
                "missing corpus image \(entry.file)"
            )
            let data = try Data(contentsOf: fileURL)
            let actualHash = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            XCTAssertEqual(actualHash, entry.sha256, entry.file)

            let expectedAnalysisStatus = entry.split == "DEV-HISTORICAL"
                ? "previously_evaluated"
                : entry.split == "HOLDOUT-INTERIM" ? "sealed_not_evaluated" : "not_evaluated"
            XCTAssertEqual(entry.analysisStatus, expectedAnalysisStatus, entry.file)
            XCTAssertEqual(
                entry.groundTruthStatus,
                entry.split == "DEV-HISTORICAL" ? "verified_rederived" : "not_assigned",
                entry.file
            )
        }

        for holdout in interimHoldoutFiles {
            XCTAssertEqual(entriesByFile[holdout]?.split, "HOLDOUT-INTERIM", holdout)
            XCTAssertEqual(entriesByFile[holdout]?.analysisStatus, "sealed_not_evaluated", holdout)
        }
    }
}

private func distance(_ lhs: CardCenteringPoint, _ rhs: CardCenteringPoint) -> Double {
    hypot(lhs.x - rhs.x, lhs.y - rhs.y)
}

private func maxCornerDistance(_ lhs: CardCenteringQuad, _ rhs: CardCenteringQuad) -> Double {
    zip(lhs.points, rhs.points).map { first, second in
        hypot(first.x - second.x, first.y - second.y)
    }.max() ?? .infinity
}

private struct GroundTruthRecord: Decodable {
    let schema: Int
    let fixture: String
    let sourcePixelSize: GroundTruthSize
    let orientedPixelSize: GroundTruthSize
    let exifOrientation: Int
    let face: String
    let encasement: String
    let capture: String
    let cardOuterQuad: [[Double]]
    let cardCornerRadiusPx: Double
    let encasementOuterQuad: [[Double]]?
    let innerQuad: [[Double]]?
    let innerReference: CardCenteringInnerReference
    let edgeBands: [String: Double]
    let ambiguousEdges: [String]
    let expected: GroundTruthExpected
    let conditions: [String]
    let provenance: GroundTruthProvenance
}

private struct GroundTruthSize: Codable, Equatable {
    let w: Int
    let h: Int

    init(width: Int, height: Int) {
        w = width
        h = height
    }
}

private struct GroundTruthExpected: Decodable {
    let lrRatio: Double?
    let tbRatio: Double?
    let skewDegrees: Double
}

private struct GroundTruthProvenance: Decodable {
    let method: String
    let annotators: [String]
    let agreementPx: Double?
    let toolVersion: String
    let date: String
    let notes: String
}

private extension CardCenteringQuad {
    init?(_ values: [[Double]]) {
        guard values.count == 4,
              values.allSatisfy({ $0.count == 2 && $0.allSatisfy { $0.isFinite } }) else {
            return nil
        }
        self.init(
            topLeft: CardCenteringPoint(x: values[0][0], y: values[0][1]),
            topRight: CardCenteringPoint(x: values[1][0], y: values[1][1]),
            bottomRight: CardCenteringPoint(x: values[2][0], y: values[2][1]),
            bottomLeft: CardCenteringPoint(x: values[3][0], y: values[3][1])
        )
    }
}

private struct CenteringCorpusManifest: Decodable {
    let schemaVersion: Int
    let status: String
    let holdoutFreeze: CenteringHoldoutFreeze
    let entries: [CenteringCorpusEntry]
}

private struct CenteringHoldoutFreeze: Decodable {
    let freezeId: String
    let frozenAt: String
    let split: String
    let selectedCount: Int
    let selectedBeforePerceptionChanges: Bool
    let analysisStatus: String
    let groundTruthStatus: String
    let captureCohortCount: Int
    let formatSet: [String]
    let finalREQ040Gate: String
    let limitations: [String]
}

private struct CenteringCorpusEntry: Decodable {
    let file: String
    let root: String
    let split: String
    let sha256: String
    let width: Int
    let height: Int
    let captureCohort: String
    let provenance: String
    let face: String
    let game: String
    let referenceClass: String
    let encasement: String
    let background: String
    let finish: String
    let analysisStatus: String
    let groundTruthStatus: String
}

private struct TestCacheEnvelope<Value: Codable>: Codable {
    let storedAt: Date
    let value: Value
}

private struct EmptyTCGdexSource: TCGdexCatalogSource {
    func fetchSetDirectory(locale: TCGdexLocale) async throws -> [CatalogSetReference] { [] }
    func fetchSet(id: String, locale: TCGdexLocale) async throws -> TCGdexSetCatalog {
        throw TCGdexError.cardNotFound
    }
    func fetchCard(
        setID: String,
        localID: String,
        locale: TCGdexLocale,
        ignoringCache: Bool
    ) async throws -> TCGdexCard {
        throw TCGdexError.cardNotFound
    }
    func fetchCard(id: String, locale: TCGdexLocale) async throws -> TCGdexCard {
        throw TCGdexError.cardNotFound
    }
}

private final class OpusJustTCGURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var body = Data()
    nonisolated(unsafe) private static var routeBodies: [String: Data] = [:]
    private static let lock = NSLock()

    static func reset(body: String) {
        lock.lock()
        Self.body = Data(body.utf8)
        Self.routeBodies = [:]
        lock.unlock()
    }

    static func reset(routes: [String: String]) {
        lock.lock()
        Self.body = Data()
        Self.routeBodies = routes.mapValues { Data($0.utf8) }
        lock.unlock()
    }

    private static func payload(for request: URLRequest) -> Data {
        let path = request.url?.path ?? ""
        if path.hasSuffix("/v1/sets"), let sets = routeBodies["sets"] {
            return sets
        }
        if request.url?.query?.contains("condition=Sealed") == true,
           let sealed = routeBodies["sealed"] {
            return sealed
        }
        return body
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://opus.invalid")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        Self.lock.lock()
        let payload = Self.payload(for: request)
        Self.lock.unlock()
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
