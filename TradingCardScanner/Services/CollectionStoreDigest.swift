import CryptoKit
import Foundation
import SwiftData

struct CollectionStoreDigest: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var storeIDSuffix: String
    var collectedCardCount: Int
    var totalQuantity: Int
    var priceRecordCount: Int
    var productIdentityCount: Int
    var collectionActivityCount: Int
    var inventoryEventCount: Int
    var materialSHA256: String
}
enum CollectionStoreDigestError: LocalizedError, Equatable {
    case fetchFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "The collection digest could not read the structured records."
        case .encodingFailed:
            return "The collection digest could not encode its canonical records."
        }
    }
}

enum CollectionStoreDigester {
    static func make(
        in context: ModelContext,
        storeID: UUID
    ) throws -> CollectionStoreDigest {
        let cards: [CollectedCard]
        let priceRecords: [PriceRecord]
        let productIdentities: [ProductIdentity]
        let activities: [CollectionActivity]
        let events: [InventoryEvent]
        do {
            cards = try context.fetch(FetchDescriptor<CollectedCard>())
            priceRecords = try context.fetch(FetchDescriptor<PriceRecord>())
            productIdentities = try context.fetch(FetchDescriptor<ProductIdentity>())
            activities = try context.fetch(FetchDescriptor<CollectionActivity>())
            events = try context.fetch(FetchDescriptor<InventoryEvent>())
        } catch {
            throw CollectionStoreDigestError.fetchFailed
        }

        let canonical = CanonicalStore(
            cards: cards.map(CardProjection.init).sorted(by: stableOrder),
            priceRecords: priceRecords.map(PriceRecordProjection.init).sorted(by: stableOrder),
            productIdentities: productIdentities.map(ProductIdentityProjection.init).sorted(by: stableOrder),
            activities: activities.map(ActivityProjection.init).sorted(by: stableOrder),
            events: events.map(InventoryEventProjection.init).sorted(by: stableOrder)
        )

        let bytes: Data
        do {
            bytes = try canonicalEncoder.encode(canonical)
        } catch {
            throw CollectionStoreDigestError.encodingFailed
        }
        let hash = SHA256.hash(data: bytes)
            .map { String(format: "%02x", $0) }
            .joined()

        return CollectionStoreDigest(
            formatVersion: SelfFormat.version,
            storeIDSuffix: SelfFormat.storeIDSuffix(storeID),
            collectedCardCount: cards.count,
            totalQuantity: cards.reduce(into: 0) { $0 += $1.quantity },
            priceRecordCount: priceRecords.count,
            productIdentityCount: productIdentities.count,
            collectionActivityCount: activities.count,
            inventoryEventCount: events.count,
            materialSHA256: hash
        )
    }

    static func redactedJSON(for snapshot: CloudSyncDiagnosticsSnapshot) throws -> Data {
        try diagnosticsEncoder.encode(snapshot)
    }

    private enum SelfFormat {
        static let version = CollectionStoreDigest.currentFormatVersion

        static func storeIDSuffix(_ storeID: UUID) -> String {
            let value = storeID.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            return String(value.suffix(8))
        }
    }

    private static let canonicalEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    private static let diagnosticsEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static func stableOrder<T: Encodable>(_ lhs: T, _ rhs: T) -> Bool {
        guard let left = try? canonicalEncoder.encode(lhs),
              let right = try? canonicalEncoder.encode(rhs) else {
            return false
        }
        return left.lexicographicallyPrecedes(right)
    }
}

struct CloudSyncDiagnosticsSnapshot: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var appVersion: String
    var buildNumber: String
    var osVersion: String
    var deviceClass: String
    var storageModeRaw: String
    var cloudAccountStatusRaw: String
    var attachmentStateRaw: String
    var storeIDSuffix: String
    var digest: CollectionStoreDigest
    var lastBootstrapErrorCategory: String?
    var generatedAt: Date
}

private struct CanonicalStore: Codable {
    var cards: [CardProjection]
    var priceRecords: [PriceRecordProjection]
    var productIdentities: [ProductIdentityProjection]
    var activities: [ActivityProjection]
    var events: [InventoryEventProjection]
}

private struct CardProjection: Codable {
    var collectionKey: String
    var game: String
    var providerID: String
    var name: String
    var setName: String
    var setCode: String
    var cardNumber: String
    var rarity: String?
    var imageURL: String?
    var thumbnailURL: String?
    var userArtworkFilename: String?
    var quantity: Int
    var dateAdded: Double
    var variantID: String?
    var variantLabel: String?
    var magicTreatmentIDsRaw: [String]
    var magicTreatmentQualifiersJSON: String?
    var magicTreatmentMigrationVersion: Int
    var magicContentKindRaw: String
    var pokemonPrintRunRaw: String?
    var variantResolutionRaw: String?
    var identityResolutionRaw: String
    var setReleaseOrder: Int
    var catalogMetadataCheckedAt: Double?
    var catalogMetadataVersion: Int
    var activityBackfillVersion: Int
    var activityBackfillAnchorID: String?
    var catalogProviderID: String?
    var tcgplayerURL: String?
    var tcgplayerProductID: String?
    var tcgplayerSKUID: String?
    var itemKindRaw: String
    var justTCGCardID: String?
    var justTCGVariantID: String?
    var justTCGAPIVersion: String?
    var gradingCompanyRaw: String?
    var gradeRaw: String?
    var gradeLabel: String?
    var gradingQualifier: String?
    var certificationNumber: String?
    var marketRegionRaw: String?

    init(_ card: CollectedCard) {
        collectionKey = card.collectionKey
        game = card.game
        providerID = card.providerID
        name = card.name
        setName = card.setName
        setCode = card.setCode
        cardNumber = card.cardNumber
        rarity = card.rarity
        imageURL = card.imageURL
        thumbnailURL = card.thumbnailURL
        userArtworkFilename = card.userArtworkFilename
        quantity = card.quantity
        dateAdded = card.dateAdded.timeIntervalSinceReferenceDate
        variantID = card.variantID
        variantLabel = card.variantLabel
        magicTreatmentIDsRaw = card.magicTreatmentIDsRaw
        magicTreatmentQualifiersJSON = card.magicTreatmentQualifiersJSON
        magicTreatmentMigrationVersion = card.magicTreatmentMigrationVersion
        magicContentKindRaw = card.magicContentKindRaw
        pokemonPrintRunRaw = card.pokemonPrintRunRaw
        variantResolutionRaw = card.variantResolutionRaw
        identityResolutionRaw = card.identityResolutionRaw
        setReleaseOrder = card.setReleaseOrder
        catalogMetadataCheckedAt = card.catalogMetadataCheckedAt?.timeIntervalSinceReferenceDate
        catalogMetadataVersion = card.catalogMetadataVersion
        activityBackfillVersion = card.activityBackfillVersion
        activityBackfillAnchorID = card.activityBackfillAnchor?.id.uuidString
        catalogProviderID = card.catalogProviderID
        tcgplayerURL = card.tcgplayerURL
        tcgplayerProductID = card.tcgplayerProductID
        tcgplayerSKUID = card.tcgplayerSKUID
        itemKindRaw = card.itemKindRaw
        justTCGCardID = card.justTCGCardID
        justTCGVariantID = card.justTCGVariantID
        justTCGAPIVersion = card.justTCGAPIVersion
        gradingCompanyRaw = card.gradingCompanyRaw
        gradeRaw = card.gradeRaw
        gradeLabel = card.gradeLabel
        gradingQualifier = card.gradingQualifier
        certificationNumber = card.certificationNumber
        marketRegionRaw = card.marketRegionRaw
    }
}

private struct PriceRecordProjection: Codable {
    var key: String
    var game: String
    var printingID: String
    var variantID: String?
    var magicTreatmentIDsRaw: [String]
    var unitMarketPriceUSD: Double?
    var currencyCode: String
    var sourceRaw: String?
    var sourceVariantID: String?
    var sourceUpdatedAt: Double?
    var fetchedAt: Double?
    var justTCGFetchedAt: Double?
    var lastCheckedAt: Double?
    var lastSuccessfulCheckAt: Double?
    var itemKindRaw: String?
    var canonicalMarketID: String?
    var marketVariantID: String?
    var marketRegionRaw: String?
    var providerGameUpdatedAt: Double?
    var historyObservationCount: Int?
    var periodChangeCount: Int?
    var periodLow: Double?
    var periodHigh: Double?
    var coefficientOfVariation: Double?
    var lastFailureAt: Double?
    var lastFailureReasonRaw: String?
    var invalidatedAt: Double?

    init(_ record: PriceRecord) {
        key = record.key
        game = record.game
        printingID = record.printingID
        variantID = record.variantID
        magicTreatmentIDsRaw = record.magicTreatmentIDsRaw
        unitMarketPriceUSD = record.unitMarketPriceUSD
        currencyCode = record.currencyCode
        sourceRaw = record.sourceRaw
        sourceVariantID = record.sourceVariantID
        sourceUpdatedAt = record.sourceUpdatedAt?.timeIntervalSinceReferenceDate
        fetchedAt = record.fetchedAt?.timeIntervalSinceReferenceDate
        justTCGFetchedAt = record.justTCGFetchedAt?.timeIntervalSinceReferenceDate
        lastCheckedAt = record.lastCheckedAt?.timeIntervalSinceReferenceDate
        lastSuccessfulCheckAt = record.lastSuccessfulCheckAt?.timeIntervalSinceReferenceDate
        itemKindRaw = record.itemKindRaw
        canonicalMarketID = record.canonicalMarketID
        marketVariantID = record.marketVariantID
        marketRegionRaw = record.marketRegionRaw
        providerGameUpdatedAt = record.providerGameUpdatedAt?.timeIntervalSinceReferenceDate
        historyObservationCount = record.historyObservationCount
        periodChangeCount = record.periodChangeCount
        periodLow = record.periodLow
        periodHigh = record.periodHigh
        coefficientOfVariation = record.coefficientOfVariation
        lastFailureAt = record.lastFailureAt?.timeIntervalSinceReferenceDate
        lastFailureReasonRaw = record.lastFailureReasonRaw
        invalidatedAt = record.invalidatedAt?.timeIntervalSinceReferenceDate
    }
}

private struct ProductIdentityProjection: Codable {
    var key: String
    var vendorRaw: String
    var vendorCardID: String?
    var vendorVariantID: String?
    var resolvedAt: Double?
    var magicTreatmentIDsRaw: [String]
    var unmatchedAt: Double?
    var attemptVersion: Int

    init(_ identity: ProductIdentity) {
        key = identity.key
        vendorRaw = identity.vendorRaw
        vendorCardID = identity.vendorCardID
        vendorVariantID = identity.vendorVariantID
        resolvedAt = identity.resolvedAt?.timeIntervalSinceReferenceDate
        magicTreatmentIDsRaw = identity.magicTreatmentIDsRaw
        unmatchedAt = identity.unmatchedAt?.timeIntervalSinceReferenceDate
        attemptVersion = identity.attemptVersion
    }
}

private struct ActivityProjection: Codable {
    var id: String
    var occurredAt: Double
    var sourceRaw: String
    var kindRaw: String
    var collectionKey: String
    var gameRaw: String
    var itemKindRaw: String
    var name: String
    var setName: String
    var setCode: String
    var cardNumber: String
    var variantID: String?
    var variantLabel: String?
    var magicTreatmentIDsRaw: [String]
    var magicTreatmentQualifiersJSON: String?
    var magicContentKindRaw: String
    var pokemonPrintRunRaw: String?
    var quantity: Int
    var deltaQuantity: Int
    var ledgerOperationIDs: [String]
    var removalSnapshotData: String?
    var resolvedQuantity: Int
    var correctedAt: Double?
    var backfillAnchorKey: String?

    init(_ activity: CollectionActivity) {
        id = activity.id.uuidString
        occurredAt = activity.occurredAt.timeIntervalSinceReferenceDate
        sourceRaw = activity.sourceRaw
        kindRaw = activity.kindRaw
        collectionKey = activity.collectionKey
        gameRaw = activity.gameRaw
        itemKindRaw = activity.itemKindRaw
        name = activity.name
        setName = activity.setName
        setCode = activity.setCode
        cardNumber = activity.cardNumber
        variantID = activity.variantID
        variantLabel = activity.variantLabel
        magicTreatmentIDsRaw = activity.magicTreatmentIDsRaw
        magicTreatmentQualifiersJSON = activity.magicTreatmentQualifiersJSON
        magicContentKindRaw = activity.magicContentKindRaw
        pokemonPrintRunRaw = activity.pokemonPrintRunRaw
        quantity = activity.quantity
        deltaQuantity = activity.deltaQuantity
        ledgerOperationIDs = activity.ledgerOperationIDs.map(\.uuidString)
        removalSnapshotData = activity.removalSnapshotData?.base64EncodedString()
        resolvedQuantity = activity.resolvedQuantity
        correctedAt = activity.correctedAt?.timeIntervalSinceReferenceDate
        backfillAnchorKey = activity.backfillAnchorCard?.collectionKey
    }
}

private struct InventoryEventProjection: Codable {
    var eventID: String
    var operationID: String
    var idempotencyKey: String
    var legRaw: String?
    var reversesEventID: String?
    var occurredAt: Double
    var recordedAt: Double
    var kindRaw: String
    var sourceRaw: String
    var collectionKey: String
    var priceStorageKey: String
    var deltaQuantity: Int
    var unitPriceUSDTenThousandths: Int64?
    var priceSourceAtEvent: String?
    var priceEffectiveAtEvent: Double?
    var priceReceivedAtEvent: Double?
    var localObservationID: String?
    var acquiredAt: Double?
    var pricePaidUSDTenThousandths: Int64?

    init(_ event: InventoryEvent) {
        eventID = event.eventID.uuidString
        operationID = event.operationID.uuidString
        idempotencyKey = event.idempotencyKey
        legRaw = event.legRaw
        reversesEventID = event.reversesEventID?.uuidString
        occurredAt = event.occurredAt.timeIntervalSinceReferenceDate
        recordedAt = event.recordedAt.timeIntervalSinceReferenceDate
        kindRaw = event.kindRaw
        sourceRaw = event.sourceRaw
        collectionKey = event.collectionKey
        priceStorageKey = event.priceStorageKey
        deltaQuantity = event.deltaQuantity
        unitPriceUSDTenThousandths = event.unitPriceUSDTenThousandths
        priceSourceAtEvent = event.priceSourceAtEvent
        priceEffectiveAtEvent = event.priceEffectiveAtEvent?.timeIntervalSinceReferenceDate
        priceReceivedAtEvent = event.priceReceivedAtEvent?.timeIntervalSinceReferenceDate
        localObservationID = event.localObservationID?.uuidString
        acquiredAt = event.acquiredAt?.timeIntervalSinceReferenceDate
        pricePaidUSDTenThousandths = event.pricePaidUSDTenThousandths
    }
}
