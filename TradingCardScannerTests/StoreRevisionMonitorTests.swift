import SwiftData
import XCTest
@testable import TradingCardScanner

@MainActor
final class StoreRevisionMonitorTests: XCTestCase {
    func testPersistedMagicMigrationFingerprintSuppressesUnchangedPendingRows() {
        let pending: Set<String> = ["magic:legacy-a", "magic:legacy-b"]
        let fingerprint = StoreRevisionFingerprinting
            .pendingMagicMigrationFingerprint(pending)

        XCTAssertTrue(StoreRevisionDecisions.shouldRunMagicMigration(
            previousPendingFingerprint: nil,
            currentPendingKeys: pending
        ))
        XCTAssertFalse(StoreRevisionDecisions.shouldRunMagicMigration(
            previousPendingFingerprint: fingerprint,
            currentPendingKeys: pending
        ))
        XCTAssertTrue(StoreRevisionDecisions.shouldRunMagicMigration(
            previousPendingFingerprint: fingerprint,
            currentPendingKeys: pending.union(["magic:new-row"])
        ))
        XCTAssertFalse(StoreRevisionDecisions.shouldRunMagicMigration(
            previousPendingFingerprint: fingerprint,
            currentPendingKeys: []
        ))
    }

    func testDerivedOnlySavesAreIgnoredAndOwnershipSavesRemainRelevant() throws {
        let container = try ModelContainer(
            for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let row = CollectedCard(
            collectionKey: "revision-filter-card",
            game: .pokemon,
            providerID: "revision-filter-card",
            name: "Filter Card",
            setName: "Filter Set",
            setCode: "FLT",
            cardNumber: "1",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .normal,
            variantResolution: .userConfirmed
        )
        let price = PriceRecord(
            key: "pokemon:revision-filter-card:normal",
            game: .pokemon,
            printingID: "revision-filter-card",
            variantID: PhysicalVariant.normal.id
        )
        let observation = PriceObservation(
            instrumentKey: price.key,
            kind: .marketUpdate,
            amount: Money(tenThousandths: 1),
            source: .tcgplayer,
            sourceVariantID: "filter",
            marketVariantID: nil,
            effectiveAt: .now,
            receivedAt: .now,
            isSourceStamped: false
        )
        let checkDay = PriceCheckDay(
            instrumentKey: price.key,
            portfolioDay: .now,
            lastSuccessfulCheckAt: .now,
            source: .tcgplayer
        )
        let close = PortfolioDailyClose(
            date: .now,
            revision: 1,
            timeZoneIdentifier: "UTC",
            closeValue: .zero,
            market: .zero,
            flow: .zero,
            corrections: .zero,
            pricingAdjustment: .zero,
            carriedForwardValue: .zero,
            coverage: .unknown,
            refreshedInstrumentCount: 0,
            carriedForwardInstrumentCount: 0,
            pricedPositionCount: 0,
            excludedCount: 0,
            inputsFingerprint: "filter",
            revisionReason: nil
        )
        let reference = ReferenceQuote(
            key: "reference-filter",
            game: .pokemon,
            printingID: "reference-filter",
            variantID: nil
        )
        let identity = ProductIdentity(key: "identity-filter", vendor: .justTCG)
        context.insert(row)
        context.insert(price)
        context.insert(observation)
        context.insert(checkDay)
        context.insert(close)
        context.insert(reference)
        context.insert(identity)
        try context.save()

        XCTAssertFalse(isRelevant([observation.persistentModelID, checkDay.persistentModelID, close.persistentModelID, reference.persistentModelID, identity.persistentModelID], passInFlight: false))
        XCTAssertFalse(isRelevant([price.persistentModelID], passInFlight: true))
        XCTAssertTrue(isRelevant([price.persistentModelID], passInFlight: false))
        XCTAssertTrue(isRelevant([row.persistentModelID, price.persistentModelID], passInFlight: true))
    }

    func testMissingIdentifierKeysUseSafeRelevantDefault() {
        let info: [AnyHashable: Any] = ["inserted": [PersistentIdentifier]()]
        XCTAssertTrue(StoreRevisionSaveFilter.isRelevantSave(userInfo: info, passInFlight: true))
        XCTAssertTrue(StoreRevisionSaveFilter.isRelevantSave(userInfo: nil, passInFlight: false))
    }

    private func isRelevant(_ identifiers: [PersistentIdentifier], passInFlight: Bool) -> Bool {
        let info: [AnyHashable: Any] = [
            ModelContext.NotificationKey.insertedIdentifiers: identifiers,
            ModelContext.NotificationKey.updatedIdentifiers: [PersistentIdentifier](),
            ModelContext.NotificationKey.deletedIdentifiers: [PersistentIdentifier]()
        ]
        return StoreRevisionSaveFilter.isRelevantSave(userInfo: info, passInFlight: passInFlight)
    }
}
