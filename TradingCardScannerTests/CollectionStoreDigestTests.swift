import SwiftData
import XCTest
@testable import TradingCardScanner

@MainActor
final class CollectionStoreDigestTests: XCTestCase {
    private let storeID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let fixedDate = Date(timeIntervalSinceReferenceDate: 1234)

    private func makeContainer() throws -> ModelContainer {
        try ProductionRowFixtures.makeContainer()
    }

    private func seed(_ context: ModelContext, reversed: Bool) throws {
        let cardA = CollectedCard(
            collectionKey: "pokemon:sv08.5:074:normal",
            game: .pokemon,
            providerID: "sv08.5-074",
            name: "Eevee",
            setName: "Prismatic Evolutions",
            setCode: "PRE",
            cardNumber: "074",
            rarity: "Illustration Rare",
            imageURL: "https://example.invalid/eevee",
            thumbnailURL: nil,
            variant: .normal,
            variantResolution: .uniqueInCatalog,
            quantity: 2,
            dateAdded: fixedDate
        )
        cardA.catalogProviderID = "sv08.5-074"
        cardA.tcgplayerSKUID = "sku-private"
        cardA.certificationNumber = "cert-private"

        let cardB = CollectedCard(
            collectionKey: "magic:neo:001:foil",
            game: .magic,
            providerID: "neo-001",
            name: "Forest",
            setName: "Kamigawa",
            setCode: "NEO",
            cardNumber: "001",
            rarity: "Common",
            imageURL: nil,
            thumbnailURL: nil,
            variant: .foil,
            variantResolution: .userConfirmed,
            quantity: 1,
            dateAdded: fixedDate
        )

        let priceA = PriceRecord(
            key: "pokemon:sv08.5-074:normal",
            game: .pokemon,
            printingID: "sv08.5-074",
            variantID: PhysicalVariant.normal.id
        )
        priceA.unitMarketPriceUSD = 12.34
        priceA.fetchedAt = fixedDate
        priceA.currencyCode = "USD"

        let priceB = PriceRecord(
            key: "magic:neo-001:foil",
            game: .magic,
            printingID: "neo-001",
            variantID: PhysicalVariant.foil.id
        )
        priceB.unitMarketPriceUSD = 3.21
        priceB.fetchedAt = fixedDate

        let product = ProductIdentity(
            key: priceA.key,
            vendor: .justTCG,
            vendorCardID: "vendor-card",
            vendorVariantID: "vendor-variant",
            resolvedAt: fixedDate
        )

        let activity = CollectionActivity(
            card: cardA,
            source: .scan,
            quantity: 2,
            occurredAt: fixedDate,
            ledgerOperationIDs: [UUID(uuidString: "22222222-2222-2222-2222-222222222222")!]
        )
        activity.id = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        activity.backfillAnchorCard = cardA

        let event = InventoryEvent(
            operationID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            leg: nil,
            kind: .acquire,
            source: .scan,
            collectionKey: cardA.collectionKey,
            priceStorageKey: priceA.key,
            deltaQuantity: 2,
            occurredAt: fixedDate,
            recordedAt: fixedDate,
            valuation: .unpriced
        )
        event.eventID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

        let rows: [any PersistentModel] = reversed
            ? [event, activity, product, priceB, priceA, cardB, cardA]
            : [cardA, cardB, priceA, priceB, product, activity, event]
        for row in rows { context.insert(row) }
        try context.save()
    }

    func testLogicalRowsInsertedInDifferentOrdersHaveTheSameDigest() throws {
        let first = try makeContainer()
        try seed(first.mainContext, reversed: false)
        let second = try makeContainer()
        try seed(second.mainContext, reversed: true)

        XCTAssertEqual(
            try CollectionStoreDigester.make(in: first.mainContext, storeID: storeID),
            try CollectionStoreDigester.make(in: second.mainContext, storeID: storeID)
        )
    }

    func testEveryMaterialCategoryChangesTheDigest() throws {
        let container = try makeContainer()
        try seed(container.mainContext, reversed: false)
        let baseline = try CollectionStoreDigester.make(in: container.mainContext, storeID: storeID)

        let card = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<CollectedCard>()).first
        )
        card.quantity += 1
        try container.mainContext.save()
        let quantityChanged = try CollectionStoreDigester.make(in: container.mainContext, storeID: storeID)
        XCTAssertNotEqual(quantityChanged.materialSHA256, baseline.materialSHA256)

        card.quantity -= 1
        card.variantLabel = "different"
        try container.mainContext.save()
        let identityChanged = try CollectionStoreDigester.make(in: container.mainContext, storeID: storeID)
        XCTAssertNotEqual(identityChanged.materialSHA256, baseline.materialSHA256)

        let event = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<InventoryEvent>()).first
        )
        event.deltaQuantity = 7
        try container.mainContext.save()
        let ledgerChanged = try CollectionStoreDigester.make(in: container.mainContext, storeID: storeID)
        XCTAssertNotEqual(ledgerChanged.materialSHA256, baseline.materialSHA256)
    }

    func testDuplicateLogicalIdentitiesRemainVisibleInCountsAndDigest() throws {
        let container = try makeContainer()
        let first = CollectedCard(
            collectionKey: "duplicate",
            game: .pokemon,
            providerID: "same",
            name: "Same",
            setName: "Set",
            setCode: "SET",
            cardNumber: "1",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .normal,
            variantResolution: .uniqueInCatalog,
            quantity: 1,
            dateAdded: fixedDate
        )
        let second = CollectedCard(
            collectionKey: "duplicate",
            game: .pokemon,
            providerID: "same",
            name: "Same",
            setName: "Set",
            setCode: "SET",
            cardNumber: "1",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .normal,
            variantResolution: .uniqueInCatalog,
            quantity: 2,
            dateAdded: fixedDate
        )
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()

        let digest = try CollectionStoreDigester.make(in: container.mainContext, storeID: storeID)
        XCTAssertEqual(digest.collectedCardCount, 2)
        XCTAssertEqual(digest.totalQuantity, 3)
    }

    func testDiagnosticJSONContainsOnlyRedactedFacts() throws {
        let digest = CollectionStoreDigest(
            formatVersion: 1,
            storeIDSuffix: "eeeeeeee",
            collectedCardCount: 1,
            totalQuantity: 2,
            priceRecordCount: 1,
            productIdentityCount: 1,
            collectionActivityCount: 1,
            inventoryEventCount: 1,
            materialSHA256: String(repeating: "a", count: 64)
        )
        let snapshot = CloudSyncDiagnosticsSnapshot(
            schemaVersion: 1,
            appVersion: "1.0",
            buildNumber: "1",
            osVersion: "test",
            deviceClass: "iPhone",
            storageModeRaw: "cloudKit",
            cloudAccountStatusRaw: "available",
            attachmentStateRaw: "attached",
            storeIDSuffix: "eeeeeeee",
            digest: digest,
            lastBootstrapErrorCategory: nil,
            generatedAt: fixedDate
        )
        let json = String(data: try CollectionStoreDigester.redactedJSON(for: snapshot), encoding: .utf8)!
        XCTAssertFalse(json.contains("Eevee"))
        XCTAssertFalse(json.contains("cert-private"))
        XCTAssertFalse(json.contains("store-file.identity"))
        XCTAssertFalse(json.contains("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        XCTAssertTrue(json.contains("materialSHA256"))
        XCTAssertTrue(json.contains("eeeeeeee"))
    }
}
