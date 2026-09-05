import AVFoundation
import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import TradingCardScanner

private enum UncoveredSurfaceFixtures {
    static func tcgdexCard(
        id: String = "test-set-001",
        localID: String = "001",
        name: String = "Test Card",
        variants: [PhysicalVariant] = [.normal]
    ) -> TCGdexCard {
        TCGdexCard(
            id: id,
            localId: localID,
            name: name,
            image: nil,
            rarity: "Common",
            set: TCGdexSetBrief(
                id: "test-set",
                name: "Test Set",
                cardCount: TCGdexCardCount(total: 10, official: 10)
            ),
            variants: TCGdexVariants(
                firstEdition: variants.contains(.firstEdition),
                holo: variants.contains(.holo),
                normal: variants.contains(.normal),
                reverse: variants.contains(.reverse),
                wPromo: nil
            ),
            pricing: nil,
            variantsDetailed: nil
        )
    }

    static func identifiedCard(
        id: String = "test-set-001",
        localID: String = "001",
        name: String = "Test Card",
        variants: [PhysicalVariant] = [.normal]
    ) -> IdentifiedCard {
        .pokemon(
            tcgdexCard(id: id, localID: localID, name: name, variants: variants),
            setCode: "TST"
        )
    }

    static func scanRequest(
        purpose: ScanPurpose = .collection,
        encounterID: UUID = UUID()
    ) -> ScanRequest {
        ScanRequest(
            identifier: .pokemon(
                setCode: "TST",
                cardNumber: "001",
                printedTotal: 10,
                setDefinition: PokemonSetDefinition(
                    printedCode: "TST",
                    tcgdexSetID: "test-set",
                    officialCount: 10,
                    releaseIndex: 0
                )
            ),
            purpose: purpose,
            generation: 1,
            encounterID: encounterID
        )
    }

    static func resolvedScan(
        purpose: ScanPurpose = .collection,
        encounterID: UUID = UUID()
    ) -> ResolvedScan {
        ResolvedScan(
            request: scanRequest(purpose: purpose, encounterID: encounterID),
            card: identifiedCard(),
            resolved: ResolvedVariant(variant: .normal, resolution: .uniqueInCatalog),
            pokemonPrintRun: nil,
            options: [.normal]
        )
    }

    static func recentScan() -> RecentScan {
        RecentScan(
            identifier: scanRequest().identifier,
            card: identifiedCard(),
            resolved: ResolvedVariant(variant: .normal, resolution: .uniqueInCatalog),
            options: [.normal],
            mutation: CollectionMutation(
                collectionKey: "test-set-001#normal",
                activityID: UUID(),
                didInsert: true,
                ledgerOperationIDs: [UUID()]
            )
        )
    }

    static func collectedCard(
        collectionKey: String,
        providerID: String,
        name: String = "Test Card",
        quantity: Int = 1,
        dateAdded: Date = .now,
        variant: PhysicalVariant? = .normal
    ) -> CollectedCard {
        CollectedCard(
            collectionKey: collectionKey,
            game: .pokemon,
            providerID: providerID,
            name: name,
            setName: "Test Set",
            setCode: "TST",
            cardNumber: "001",
            rarity: "Common",
            imageURL: nil,
            thumbnailURL: nil,
            variant: variant,
            variantResolution: .userConfirmed,
            quantity: quantity,
            dateAdded: dateAdded
        )
    }

    static func catalogSummary() -> CatalogCardSummary {
        CatalogCardSummary(
            game: .pokemon,
            providerID: "test-set-001",
            setID: CatalogSetID(game: .pokemon, providerID: "test-set"),
            setName: "Test Set",
            setCode: "TST",
            name: "Test Card",
            collectorNumber: "001",
            thumbnailURL: nil,
            imageURL: nil
        )
    }

    static func priceLookup(amount: Double = 12.34) -> PriceLookup {
        .price(
            NormalizedPrice(
                unitMarketPriceUSD: amount,
                currencyCode: "USD",
                source: .tcgplayer,
                sourceVariantID: "normal",
                sourceUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                fetchedAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
        )
    }

    static func fullSchema() -> Schema {
        Schema([
            CollectedCard.self,
            PriceRecord.self,
            ProductIdentity.self,
            CollectionActivity.self,
            InventoryEvent.self,
            ReferenceQuote.self,
            PriceObservation.self,
            PriceCheckDay.self,
            PortfolioDailyClose.self,
            LocalArtworkOverride.self
        ])
    }

    @MainActor
    static func inMemoryContainer(for schema: Schema) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    static func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 240, height: 336)).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 240, height: 336))
            UIColor.systemBlue.setFill()
            renderer.fill(CGRect(x: 24, y: 24, width: 192, height: 288))
        }
    }
}

final class TradingCardScannerAppSurfaceTests: XCTestCase {
    func testStorageModesExposeTheirPersistencePromise() {
        let cloud = TradingCardScannerApp.StorageMode.cloudKit
        XCTAssertEqual(cloud.label, "iCloud sync enabled")
        XCTAssertEqual(cloud.detail, "The collection uses this device's iCloud account.")
        XCTAssertTrue(cloud.isCloudSyncing)

        let local = TradingCardScannerApp.StorageMode.localOnly
        XCTAssertEqual(local.label, "On this device only")
        XCTAssertEqual(
            local.detail,
            "The collection is stored locally; this launch is not using a CloudKit-backed container."
        )
        XCTAssertFalse(local.isCloudSyncing)
        XCTAssertNotEqual(cloud, local)
    }
}

@MainActor
final class AppDelegateSurfaceTests: XCTestCase {
    func testApplicationLaunchHookReturnsSuccess() {
        let delegate = AppDelegate()
        XCTAssertTrue(
            delegate.application(
                UIApplication.shared,
                didFinishLaunchingWithOptions: nil
            )
        )
    }
}

final class AppleAccountCredentialsSurfaceTests: XCTestCase {
    func testCredentialsTrimAndClearWithoutLosingTheStoredDisplayName() throws {
        let originalIdentifier = AppleAccountCredentials.userIdentifier
        let originalDisplayName = AppleAccountCredentials.displayName
        defer {
            AppleAccountCredentials.clear()
            if let originalIdentifier {
                try? AppleAccountCredentials.store(
                    userIdentifier: originalIdentifier,
                    displayName: originalDisplayName
                )
            }
        }

        AppleAccountCredentials.clear()
        XCTAssertNil(AppleAccountCredentials.userIdentifier)
        XCTAssertNil(AppleAccountCredentials.displayName)
        XCTAssertFalse(AppleAccountCredentials.isSignedIn)

        try AppleAccountCredentials.store(
            userIdentifier: "  test-user-123  ",
            displayName: "  Test Collector  "
        )
        XCTAssertEqual(AppleAccountCredentials.userIdentifier, "test-user-123")
        XCTAssertEqual(AppleAccountCredentials.displayName, "Test Collector")
        XCTAssertTrue(AppleAccountCredentials.isSignedIn)

        try AppleAccountCredentials.store(userIdentifier: "test-user-456", displayName: nil)
        XCTAssertEqual(AppleAccountCredentials.userIdentifier, "test-user-456")
        XCTAssertEqual(
            AppleAccountCredentials.displayName,
            "Test Collector",
            "a later authorization may omit the name, so the first name is retained"
        )

        AppleAccountCredentials.clear()
        XCTAssertNil(AppleAccountCredentials.userIdentifier)
        XCTAssertNil(AppleAccountCredentials.displayName)
        XCTAssertFalse(AppleAccountCredentials.isSignedIn)
    }
}

@MainActor
final class BackgroundPriceRefreshSurfaceTests: XCTestCase {
    func testAvailabilityCopyAndMessagesAreStable() {
        XCTAssertEqual(BackgroundPriceRefresh.Availability.available.label, "On")
        XCTAssertNil(BackgroundPriceRefresh.Availability.available.detail)
        XCTAssertEqual(BackgroundPriceRefresh.Availability.denied.label, "Off")
        XCTAssertTrue(
            BackgroundPriceRefresh.Availability.denied.detail?.contains("Background App Refresh") == true
        )
        XCTAssertEqual(BackgroundPriceRefresh.Availability.restricted.label, "Restricted")
        XCTAssertTrue(
            BackgroundPriceRefresh.Availability.restricted.detail?.contains("restricts") == true
        )
    }

    func testForegroundGuardDoesNotStartHeadlessWork() async {
        let processingSucceeded = await BackgroundPriceRefresh.run(.processing)
        let appRefreshSucceeded = await BackgroundPriceRefresh.run(.appRefresh)
        XCTAssertTrue(processingSucceeded)
        XCTAssertTrue(appRefreshSucceeded)
    }
}

final class CameraCapabilitiesSurfaceTests: XCTestCase {
    func testHardwareProbeCacheIsModelScopedAndCanBeInvalidated() throws {
        let suiteName = "CameraCapabilitiesSurfaceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "camera.hasMacroLens")
        defaults.set(CameraCapabilities.modelIdentifier, forKey: "camera.probedModelIdentifier")
        XCTAssertTrue(CameraCapabilities.hasMacroLens(defaults: defaults))

        defaults.set(false, forKey: "camera.hasMacroLens")
        XCTAssertFalse(CameraCapabilities.hasMacroLens(defaults: defaults))

        CameraCapabilities.invalidateCache(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "camera.hasMacroLens"))
        XCTAssertNil(defaults.object(forKey: "camera.probedModelIdentifier"))

        let probed = CameraCapabilities.hasMacroLens(defaults: defaults)
        XCTAssertEqual(defaults.bool(forKey: "camera.hasMacroLens"), probed)
        XCTAssertEqual(
            defaults.string(forKey: "camera.probedModelIdentifier"),
            CameraCapabilities.modelIdentifier
        )
    }
}

@MainActor
final class PriceRefreshTargetsSurfaceTests: XCTestCase {
    func testTargetsProjectDuplicateRowsAndOptionallyIncludeImports() throws {
        let container = try UncoveredSurfaceFixtures.inMemoryContainer(
            for: Schema([CollectedCard.self, PriceRecord.self])
        )
        let context = container.mainContext
        let older = UncoveredSurfaceFixtures.collectedCard(
            collectionKey: "position-1",
            providerID: "test-set-001",
            quantity: 2,
            dateAdded: Date(timeIntervalSince1970: 100)
        )
        let newer = UncoveredSurfaceFixtures.collectedCard(
            collectionKey: "position-1",
            providerID: "test-set-001",
            quantity: 3,
            dateAdded: Date(timeIntervalSince1970: 200)
        )
        let imported = UncoveredSurfaceFixtures.collectedCard(
            collectionKey: "imported-1",
            providerID: "csv:row-1",
            name: "Imported Card"
        )
        context.insert(older)
        context.insert(newer)
        context.insert(imported)
        context.insert(
            PriceRecord(
                key: older.priceKey,
                game: .pokemon,
                printingID: older.priceStorageID,
                variantID: older.variantID
            )
        )

        let withImports = try PriceRefreshTargets.make(
            context: context,
            usesPriceFallback: false,
            includeImported: true
        )
        XCTAssertEqual(withImports.count, 2)
        XCTAssertEqual(Set(withImports.map(\.printingID)), Set([older.priceStorageID, imported.priceStorageID]))

        let withoutImports = try PriceRefreshTargets.make(
            context: context,
            usesPriceFallback: false,
            includeImported: false
        )
        XCTAssertEqual(withoutImports.count, 1)
        XCTAssertEqual(withoutImports.first?.printingID, older.priceStorageID)
        XCTAssertEqual(withoutImports.first?.setCode, "TST")
    }
}

@MainActor
final class PriceStoreRefreshRaceTests: XCTestCase {
    func testStaleRefreshIndexRechecksReadsAndWritesBeforeCreatingARecord() throws {
        let container = try UncoveredSurfaceFixtures.inMemoryContainer(
            for: Schema([PriceRecord.self, PriceObservation.self, PriceCheckDay.self])
        )
        let context = container.mainContext
        let key = PriceRecord.key(
            game: .pokemon,
            printingID: "test-set-001",
            variantID: PhysicalVariant.normal.id
        )
        let staleIndex = PriceRefreshDataIndex(context: context)
        let existing = PriceRecord(
            key: key,
            game: .pokemon,
            printingID: "test-set-001",
            variantID: PhysicalVariant.normal.id
        )
        context.insert(existing)
        try context.save()

        let store = PriceStore(context: context, index: staleIndex)
        XCTAssertEqual(store.record(forKey: key)?.key, key)

        let saved = store.store(
            UncoveredSurfaceFixtures.priceLookup(),
            game: .pokemon,
            printingID: "test-set-001",
            variantID: PhysicalVariant.normal.id
        )

        XCTAssertTrue(saved)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PriceRecord>()).count, 1)
        XCTAssertEqual(existing.unitMarketPriceUSD, 12.34)
    }
}

@MainActor
final class CollectionProjectionTokenTests: XCTestCase {
    func testPriceWritesInvalidateTheProjectionWhileSearchStateDoesNot() throws {
        let container = try UncoveredSurfaceFixtures.inMemoryContainer(
            for: Schema([CollectedCard.self, PriceRecord.self, LocalArtworkOverride.self])
        )
        let context = container.mainContext
        let card = UncoveredSurfaceFixtures.collectedCard(
            collectionKey: "projection-position",
            providerID: "test-set-001"
        )
        let record = PriceRecord(
            key: card.priceKey,
            game: card.cardGame,
            printingID: card.priceStorageID,
            variantID: card.variantID
        )
        record.unitMarketPriceUSD = 12.34
        context.insert(card)
        context.insert(record)
        try context.save()

        let baseline = CollectionProjectionToken.make(
            cards: [card],
            priceRecords: [record],
            artworkOverrides: []
        )

        // Search, filter, and sort are applied after this fingerprint, so
        // none of that view state participates in the cache key.
        XCTAssertEqual(
            CollectionProjectionToken.make(
                cards: [card],
                priceRecords: [record],
                artworkOverrides: []
            ),
            baseline
        )

        // Artwork diagnostics read this field live in the tile, so changing it
        // must not rebuild every projected collection row.
        card.imageURL = "https://example.com/card.png"
        XCTAssertEqual(
            CollectionProjectionToken.make(
                cards: [card],
                priceRecords: [record],
                artworkOverrides: []
            ),
            baseline
        )

        record.unitMarketPriceUSD = 99.99
        let afterPriceWrite = CollectionProjectionToken.make(
            cards: [card],
            priceRecords: [record],
            artworkOverrides: []
        )
        XCTAssertNotEqual(afterPriceWrite, baseline)
    }
}

@MainActor
final class CollectionLineageIndexTests: XCTestCase {
    func testIndexedLineageValidatorMatchesFetchValidatorAcrossIntegrityCases() throws {
        let container = try UncoveredSurfaceFixtures.inMemoryContainer(
            for: Schema([InventoryEvent.self])
        )
        let context = container.mainContext
        let collectionKey = "lineage-position"
        let occurredAt = Date(timeIntervalSince1970: 1_000)
        let validOperationID = UUID()
        let reversedOperationID = UUID()
        let validEvent = InventoryEvent(
            operationID: validOperationID,
            leg: nil,
            kind: .acquire,
            source: .scan,
            collectionKey: collectionKey,
            priceStorageKey: "pokemon:test-set-001#normal",
            deltaQuantity: 1,
            occurredAt: occurredAt,
            valuation: .unpriced
        )
        let reversedSource = InventoryEvent(
            operationID: reversedOperationID,
            leg: nil,
            kind: .acquire,
            source: .scan,
            collectionKey: collectionKey,
            priceStorageKey: "pokemon:test-set-002#normal",
            deltaQuantity: 1,
            occurredAt: occurredAt,
            valuation: .unpriced
        )
        let reversal = InventoryEvent(
            operationID: UUID(),
            leg: nil,
            kind: .dispose,
            source: .correction,
            collectionKey: collectionKey,
            priceStorageKey: "pokemon:test-set-002#normal",
            deltaQuantity: -1,
            occurredAt: occurredAt,
            valuation: .unpriced,
            reversesEventID: reversedSource.eventID
        )
        context.insert(validEvent)
        context.insert(reversedSource)
        context.insert(reversal)
        try context.save()

        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        let index = CollectionStore.LineageIndex(events: events)
        let store = CollectionStore(context: context)
        let missingOperationID = UUID()
        let cases: [(String, [UUID], Int, Bool)] = [
            ("valid", [validOperationID], 1, true),
            ("already reversed", [reversedOperationID], 1, false),
            ("missing operation", [missingOperationID], 1, false),
            ("wrong quantity", [validOperationID], 2, false)
        ]

        for (label, operationIDs, quantity, expected) in cases {
            let fetched = store.hasValidLineage(
                operationIDs,
                for: collectionKey,
                quantity: quantity
            )
            let indexed = CollectionStore.hasValidLineage(
                operationIDs,
                for: collectionKey,
                quantity: quantity,
                using: index
            )
            XCTAssertEqual(fetched, indexed, "validator forms diverged for \(label)")
            XCTAssertEqual(indexed, expected, "unexpected result for \(label)")
        }
    }
}

final class JustTCGV2GradedSurfaceTests: XCTestCase {
    func testGradedIdentityGroupingAndOwnedFiltersUseExactFields() {
        let identity = GradedCardIdentity(
            name: " Charizard ",
            setName: "Base Set",
            collectorNumber: "004/102"
        )
        XCTAssertEqual(
            identity.groupingKey(game: .pokemon),
            "pokemon|base set|004/102| charizard "
        )

        let psa = UncoveredSurfaceFixtures.collectedCard(
            collectionKey: "graded-psa",
            providerID: "test-set-001"
        )
        psa.itemKindRaw = CollectionItemKind.gradedCard.rawValue
        psa.gradingCompanyRaw = GradingCompany.psa.rawValue
        psa.gradeRaw = "10"

        let cgc = UncoveredSurfaceFixtures.collectedCard(
            collectionKey: "graded-cgc",
            providerID: "test-set-002"
        )
        cgc.itemKindRaw = CollectionItemKind.gradedCard.rawValue
        cgc.gradingCompanyRaw = GradingCompany.cgc.rawValue
        cgc.gradeRaw = "9.5"

        let raw = UncoveredSurfaceFixtures.collectedCard(
            collectionKey: "raw",
            providerID: "test-set-003"
        )

        let filters = JustTCGV2GradedClient.ownedFilters(for: [psa, cgc, raw])
        XCTAssertEqual(filters.companies, [.psa, .cgc])
        XCTAssertEqual(filters.grades, ["10", "9.5"])
    }
}

@MainActor
final class SealedBrowseSurfaceTests: XCTestCase {
    func testSealedBrowseLoadsSetsProductsAndTheNextPage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SealedBrowseSurfaceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = SealedProductSummary(
            id: "sealed-1",
            name: "Test Booster Box",
            setName: "Test Set",
            variantID: "variant-1",
            marketPriceUSD: 100,
            updatedAt: .now,
            imageURL: nil
        )
        let second = SealedProductSummary(
            id: "sealed-2",
            name: "Test Collection Box",
            setName: "Test Set",
            variantID: "variant-2",
            marketPriceUSD: 50,
            updatedAt: .now,
            imageURL: nil
        )
        let set = SealedSetSummary(
            id: "test-set",
            name: "Test Set",
            sealedCount: 2,
            game: .pokemon,
            releaseDate: Date(timeIntervalSince1970: 200)
        )
        let provider = UncoveredSealedBrowseProvider(
            sets: [set],
            products: [first, second]
        )
        let model = SealedBrowseModel(
            client: provider,
            cache: CatalogCacheStore(root: root),
            isConfigured: { true }
        )

        await model.loadSetsIfNeeded(game: .pokemon)
        XCTAssertEqual(model.sets, [set])
        XCTAssertFalse(model.isLoading)

        await model.loadProducts(game: .pokemon, setID: set.id)
        XCTAssertEqual(model.products, [first])
        XCTAssertTrue(model.hasMore)

        await model.loadMore(game: .pokemon, setID: set.id)
        XCTAssertEqual(model.products, [first, second])
        XCTAssertFalse(model.hasMore)
        XCTAssertFalse(model.isLoading)
        let setRequestCount = await provider.setRequestCount()
        let productOffsets = await provider.productOffsets()
        XCTAssertEqual(setRequestCount, 1)
        XCTAssertEqual(productOffsets, [0, 1])
    }

    func testSealedBrowseStatesMissingCredentialsWithoutCallingTheProvider() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SealedBrowseSurfaceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = UncoveredSealedBrowseProvider()
        let model = SealedBrowseModel(
            client: provider,
            cache: CatalogCacheStore(root: root),
            isConfigured: { false }
        )

        await model.loadProducts(game: .magic, setID: nil)

        XCTAssertEqual(
            model.errorMessage,
            "Add a pricing API key in Settings to browse sealed products."
        )
        XCTAssertTrue(model.products.isEmpty)
        let productOffsets = await provider.productOffsets()
        XCTAssertEqual(productOffsets, [])
    }

    func testSealedBrowseErrorCopyNamesQuotaAndCredentialStates() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let budget = SealedBrowseModel.message(for: JustTCGTransport.TransportError.budgetReached(resetAt: date))
        let monthly = SealedBrowseModel.message(for: JustTCGTransport.TransportError.monthlyBudgetReached(resetAt: date))
        let rate = SealedBrowseModel.message(for: JustTCGTransport.TransportError.rateLimited(retryAt: date))

        XCTAssertTrue(budget.contains("Daily request budget reached"))
        XCTAssertTrue(monthly.contains("Monthly request budget reached"))
        XCTAssertTrue(rate.contains("Paused by the provider"))
        XCTAssertEqual(
            SealedBrowseModel.message(for: JustTCGTransport.TransportError.missingCredentials),
            "Add a pricing API key in Settings to browse sealed products."
        )
    }
}

@MainActor
final class ScanFeedbackSurfaceTests: XCTestCase {
    func testAllFeedbackTransitionsAreSafeToPrepareAndInvoke() {
        let feedback = ScanFeedback()
        feedback.prepare()
        feedback.added()
        feedback.needsChoice()
        feedback.choiceMade()
        feedback.problem()
        feedback.undone()
    }
}

@MainActor
final class CardCenteringSurfaceTests: XCTestCase {
    func testRotationIsClampedAndGuideEditsRefreshWarnings() {
        let model = CardCenteringViewModel()
        model.adjustRotation(by: 60)
        XCTAssertEqual(model.rotationDegrees, 45)
        model.adjustRotation(by: -100)
        XCTAssertEqual(model.rotationDegrees, -45)
        model.resetRotation()
        XCTAssertEqual(model.rotationDegrees, 0)

        model.measurement = CardCenteringMeasurement(
            imageWidth: 240,
            imageHeight: 336,
            outer: CardCenteringEdges(left: 20, top: 20, right: 220, bottom: 316),
            inner: CardCenteringEdges(left: 30, top: 30, right: 210, bottom: 306),
            warnings: []
        )
        model.updateOuter(\.left, to: -10, within: 0...240)
        model.updateInner(\.right, to: 500, within: 0...240)

        XCTAssertEqual(model.measurement?.outer.left, 0)
        XCTAssertEqual(model.measurement?.inner.right, 240)
        XCTAssertFalse(model.measurement?.warnings.isEmpty ?? true)
    }

    func testExportUsesTheCurrentImageAndMeasurement() throws {
        let model = CardCenteringViewModel()
        model.image = UncoveredSurfaceFixtures.image()
        model.measurement = CardCenteringMeasurement(
            imageWidth: 240,
            imageHeight: 336,
            outer: CardCenteringEdges(left: 20, top: 20, right: 220, bottom: 316),
            inner: CardCenteringEdges(left: 30, top: 30, right: 210, bottom: 306),
            warnings: []
        )

        let url = try XCTUnwrap(model.makeExportFile())
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertGreaterThan(try Data(contentsOf: url).count, 0)
        XCTAssertTrue(url.lastPathComponent.contains("Card Centering"))
    }
}

@MainActor
final class CameraPreviewSurfaceTests: XCTestCase {
    func testPreviewViewBuildsNonInteractiveOverlayLayers() {
        let view = PreviewView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        XCTAssertFalse(view.isUserInteractionEnabled)
        XCTAssertEqual(
            ObjectIdentifier(PreviewView.layerClass),
            ObjectIdentifier(AVCaptureVideoPreviewLayer.self)
        )
        XCTAssertGreaterThanOrEqual(view.previewLayer.sublayers?.count ?? 0, 2)

        view.syncSuccessCount(0)
        view.syncSuccessCount(1)
        view.syncSuccessCount(1)

        let preview = CameraPreview(scanner: CardScanner(), successCount: 1)
        XCTAssertNotNil(preview)
    }
}

@MainActor
final class ViewConstructionSmokeTests: XCTestCase {
    func testStatelessAndStatefulScreensCanBeConstructed() throws {
        let history = PortfolioHistoryStore()
        let portfolio = PortfolioEngine()
        let refresh = PriceRefreshController()
        let card = UncoveredSurfaceFixtures.collectedCard(
            collectionKey: "detail",
            providerID: "test-set-001"
        )
        let recent = UncoveredSurfaceFixtures.recentScan()
        let identified = UncoveredSurfaceFixtures.identifiedCard()
        let transportDefaultsSuite = "ViewConstructionSmokeTests.\(UUID().uuidString)"
        let transportDefaults = try XCTUnwrap(UserDefaults(suiteName: transportDefaultsSuite))
        defer { transportDefaults.removePersistentDomain(forName: transportDefaultsSuite) }
        let graded = GradedVariant(
            id: "graded-1",
            cardID: "card-1",
            company: .psa,
            grade: CardGrade(value: "10"),
            marketPriceUSD: 100,
            updatedAt: .now
        )

        _ = ContentView()
        _ = ScannerView()
        _ = SettingsView()
        _ = CenteringCameraView(onCapture: { _ in })
        _ = CardCenteringView()
        _ = CollectionActivityLogView()
        _ = CollectionCardDetailView(
            card: card,
            price: .unknown,
            history: history,
            unpricedReason: nil,
            artworkReason: nil,
            onRemoved: { _ in }
        )
        _ = CatalogCardDetailView(
            summary: UncoveredSurfaceFixtures.catalogSummary(),
            catalog: EmptyUncoveredBrowseCatalog()
        )
        _ = PortfolioView(
            portfolio: portfolio,
            refresh: refresh,
            history: history,
            onRefresh: {},
            onOpenCollectionSortedByPrice: {}
        )
        _ = PortfolioHistoryView(history: history, onOpenDetails: { _ in })
        _ = PriceCheckResultView(initialResult: PriceCheckResult(
            resolvedScan: UncoveredSurfaceFixtures.resolvedScan(purpose: .priceCheck),
            quote: UncoveredSurfaceFixtures.priceLookup(),
            checkedAt: .now
        ))
        _ = ScanReviewSheet(scan: recent, onCorrect: { _ in .saved }, onDelete: {})
        _ = GradedVariantPickerView(
            card: identified,
            setReleaseOrder: 0,
            transport: JustTCGTransport(
                configuration: .init(minimumRequestInterval: 0),
                session: .shared,
                ledger: JustTCGRequestLedger(
                    defaults: transportDefaults
                ),
                pacer: JustTCGPacer(),
                apiKeyOverride: nil
            )
        )
        _ = GradedSlabConfirmationView(
            card: identified,
            variant: graded,
            setReleaseOrder: 0,
            onAdded: { _ in }
        )
        _ = RemovalUndoBanner(name: "Test Card", onUndo: {}, onDismiss: {})
        _ = PriceFallbackSettingsSection().body

        let sealedProduct = SealedProductSummary(
            id: "sealed-test",
            name: "Test Booster Box",
            setName: "Test Set",
            variantID: "sealed-variant",
            marketPriceUSD: 20,
            updatedAt: .now,
            imageURL: nil
        )
        let sealedSet = SealedSetSummary(
            id: "sealed-set",
            name: "Test Set",
            sealedCount: 1,
            game: .pokemon,
            releaseDate: nil
        )
        let sealedModel = SealedBrowseModel(
            client: EmptyUncoveredSealedBrowseProvider(),
            cache: CatalogCacheStore(
                root: FileManager.default.temporaryDirectory
                    .appendingPathComponent("BackgroundViewConstruction-\(UUID().uuidString)", isDirectory: true)
            ),
            isConfigured: { false }
        )
        _ = SealedSetDirectoryView(game: .pokemon, model: sealedModel)
        _ = SealedProductGridView(game: .pokemon, set: sealedSet, model: sealedModel)
        _ = SealedProductTile(product: sealedProduct).body
        _ = SealedProductDetailView(game: .pokemon, product: sealedProduct)
    }

    func testContentWidthLimitsRemainTheDocumentedSizes() {
        XCTAssertEqual(ContentWidthLimit.standard.points, 700)
        XCTAssertEqual(ContentWidthLimit.wide.points, 1_100)
        XCTAssertEqual(ContentWidthLimit.artwork.points, 460)
        _ = Text("content").contentWidthLimit(.wide)
    }
}

@MainActor
final class ScannerOverlaySmokeTests: XCTestCase {
    func testOverlayBodiesRenderTheScannerStateShapes() {
        let resolvedScan = UncoveredSurfaceFixtures.resolvedScan()
        let candidate = CollectionCommitCandidate(resolvedScan: resolvedScan)
        let recent = UncoveredSurfaceFixtures.recentScan()
        let proof = SpatialResetProof(encounterID: resolvedScan.request.encounterID)
        let duplicate = PendingDuplicateConfirmation(
            candidate: candidate,
            matchingSpatialResetProof: proof,
            previousScanID: recent.id,
            previousPresentationToken: UUID()
        )
        let choice = PendingVariantChoice(
            request: resolvedScan.request,
            card: resolvedScan.card,
            options: [.normal, .holo],
            pokemonPrintRun: nil,
            catalogRetrievedAt: .now,
            lockDidNotApply: nil
        )
        let printRun = PendingPrintRunChoice(
            request: resolvedScan.request,
            card: resolvedScan.card,
            options: [.firstEdition, .unlimited],
            catalogRetrievedAt: .now
        )
        let identity = PokemonCatalogCardIdentity(
            providerID: "test-set-001",
            setID: "test-set",
            setName: "Test Set",
            localID: "001",
            name: "Test Card"
        )
        let identityChoice = PendingIdentityChoice(
            request: resolvedScan.request,
            evidence: PokemonHistoricalScanEvidence(
                number: PokemonPrintedNumberEvidence(
                    localID: "001",
                    denominator: 10,
                    scheme: .officialSet
                ),
                titleCandidates: ["TEST CARD"]
            ),
            candidates: [identity]
        )
        let offer = HeldDuplicateOffer(
            offerID: UUID(),
            previousScanID: recent.id,
            previousPresentationToken: UUID(),
            encounterID: resolvedScan.request.encounterID,
            identity: candidate.identity,
            suppressionKey: resolvedScan.request.identifier.suppressionKey,
            cardName: "Test Card",
            printedIdentifier: "TST 001/10"
        )
        let receipt = ScanReceipt(
            scanID: recent.id,
            name: "Test Card",
            identifier: "TST 001/10",
            variantLabel: "Normal",
            treatmentDiagnostics: [],
            thumbnailURL: nil
        )

        _ = ScanAssistanceView(message: "Hold the card steady").body
        _ = HeldDuplicateOfferView(offer: offer, onAddAnother: {}).body
        _ = DuplicateConfirmationBar(confirmation: duplicate, onSameCard: {}, onAddAnother: {}).body
        _ = VariantChoiceBar(choice: choice, onChoose: { _ in }, onDismiss: {}).body
        _ = PrintRunChoiceBar(choice: printRun, onChoose: { _ in }, onDismiss: {}).body
        _ = IdentityChoiceBar(choice: identityChoice, onChoose: { _ in }, onDismiss: {}).body
        _ = ScanReceiptCard(receipt: receipt, onUndo: {}, onOpen: {}).body
        _ = RecentScanRail(scans: [recent], onSelect: { _ in }, onDelete: { _ in }).body
        _ = CardThumbnail(url: nil, width: 40).body
        _ = ScanNoteView(note: ScanNote(text: "No exact finish", tone: .problem)).body
    }
}

#if DEBUG
@MainActor
final class PortfolioDebugFixtureSurfaceTests: XCTestCase {
    func testMovementFixtureSeedsAnIdempotentCollectionAndHistory() throws {
        let container = try UncoveredSurfaceFixtures.inMemoryContainer(
            for: Schema([
                CollectedCard.self,
                PriceRecord.self,
                CollectionActivity.self,
                InventoryEvent.self,
                PriceObservation.self,
                PriceCheckDay.self
            ])
        )
        let context = container.mainContext
        let defaults = UserDefaults.standard
        let originalEpoch = defaults.object(forKey: PortfolioEpoch.defaultsKey)
        defer {
            if let originalEpoch {
                defaults.set(originalEpoch, forKey: PortfolioEpoch.defaultsKey)
            } else {
                defaults.removeObject(forKey: PortfolioEpoch.defaultsKey)
            }
        }

        PortfolioDebugFixtures.seedMovementIfNeeded(in: context)
        let firstCards = try context.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(firstCards.count, 1)
        XCTAssertEqual(firstCards.first?.quantity, 3)
        XCTAssertFalse(try context.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
        XCTAssertFalse(try context.fetch(FetchDescriptor<PriceObservation>()).isEmpty)
        XCTAssertFalse(try context.fetch(FetchDescriptor<PriceCheckDay>()).isEmpty)

        PortfolioDebugFixtures.seedMovementIfNeeded(in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectedCard>()).count, 1)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CollectedCard>()).first?.quantity,
            3
        )
    }
}
#endif

private actor EmptyUncoveredBrowseCatalog: BrowseCatalogProviding {
    func sets(for game: CardGame) async throws -> [CatalogSet] { [] }

    func cards(in set: CatalogSet, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        CatalogPage(items: [], nextCursor: nil)
    }

    func searchCards(
        named query: String,
        game: CardGame,
        setIDs: Set<CatalogSetID>,
        cursor: String?
    ) async throws -> CatalogPage<CatalogCardSummary> {
        CatalogPage(items: [], nextCursor: nil)
    }

    func details(for summary: CatalogCardSummary) async throws -> CatalogCardDetails {
        throw BrowseCatalogError.badResponse
    }

    func sortPrices(for cards: [CatalogCardSummary]) async -> [String: Double] { [:] }
    func prepareCatalog() async {}
}

private actor UncoveredSealedBrowseProvider: SealedBrowseProviding {
    private let setsByGame: [CardGame: [SealedSetSummary]]
    private let productsByGame: [CardGame: [SealedProductSummary]]
    private var setRequests = 0
    private var offsets: [Int] = []

    init(
        sets: [SealedSetSummary] = [],
        products: [SealedProductSummary] = []
    ) {
        self.setsByGame = [.pokemon: sets, .magic: sets]
        self.productsByGame = [.pokemon: products, .magic: products]
    }

    func searchSealedProducts(
        game: CardGame,
        setID: String?,
        query: String?,
        offset: Int
    ) async throws -> MarketCatalogPage<SealedProductSummary> {
        offsets.append(offset)
        let all = productsByGame[game] ?? []
        let items = Array(all.dropFirst(offset).prefix(1))
        return MarketCatalogPage(
            items: items,
            total: all.count,
            offset: offset,
            limit: 1,
            hasMore: offset + items.count < all.count
        )
    }

    func sealedSets(game: CardGame) async throws -> [SealedSetSummary] {
        setRequests += 1
        return setsByGame[game] ?? []
    }

    func setRequestCount() -> Int { setRequests }
    func productOffsets() -> [Int] { offsets }
}

private actor EmptyUncoveredSealedBrowseProvider: SealedBrowseProviding {
    func searchSealedProducts(
        game: CardGame,
        setID: String?,
        query: String?,
        offset: Int
    ) async throws -> MarketCatalogPage<SealedProductSummary> {
        MarketCatalogPage(items: [], total: 0, offset: offset, limit: 1, hasMore: false)
    }

    func sealedSets(game: CardGame) async throws -> [SealedSetSummary] { [] }
}
