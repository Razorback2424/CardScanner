import XCTest
import SwiftData
@testable import TradingCardScanner

@MainActor
final class OpusImplementationPlanTests: XCTestCase {
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
        // The owned quantity must exist before the transition so the replay can
        // attribute the full de-pricing to the two copies rather than treating
        // the first quote as a price for a not-yet-owned position.
        let firstPriceAt = Date.now.addingTimeInterval(1)
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
            epoch: Date.now.addingTimeInterval(-3_600),
            through: through,
            timeZone: .current
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
                periodStart: Date.now.addingTimeInterval(-3_600),
                periodEnd: through
            )
        )
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

private struct TestCacheEnvelope<Value: Codable>: Codable {
    let storedAt: Date
    let value: Value
}

private struct EmptyTCGdexSource: TCGdexCatalogSource {
    func fetchSetDirectory(locale: TCGdexLocale) async throws -> [CatalogSetReference] { [] }
    func fetchSet(id: String, locale: TCGdexLocale) async throws -> TCGdexSetCatalog {
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
