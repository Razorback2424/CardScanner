import Foundation
import SwiftData

/// A reusable market quote for a printing and physical variant.
///
/// This is intentionally separate from `PriceRecord`: a reference quote means
/// only that this device learned a price while browsing or price-checking. It
/// must never become evidence that an owned collection position was valued.
@Model
final class ReferenceQuote {
    @Attribute var key: String = ""

    var game: String = ""
    var printingID: String = ""
    var variantID: String?
    /// A reference quote is keyed at the same treatment-aware granularity as a
    /// collection price. The default keeps pre-treatment cache rows readable.
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

    init(
        key: String,
        game: CardGame,
        printingID: String,
        variantID: String?,
        magicTreatmentIDs: [String] = []
    ) {
        self.key = key
        self.game = game.rawValue
        self.printingID = printingID
        self.variantID = variantID
        self.magicTreatmentIDsRaw = MagicTreatmentKeyCodec.storedIDs(from: magicTreatmentIDs)
    }

    static func key(
        game: CardGame,
        printingID: String,
        variantID: String?,
        treatmentIDs: [String] = []
    ) -> String {
        PriceRecord.key(
            game: game,
            printingID: printingID,
            variantID: variantID,
            treatmentIDs: treatmentIDs
        )
    }

    var source: PriceSource? { sourceRaw.flatMap(PriceSource.init(rawValue:)) }

    var effectiveAmount: Double? {
        invalidatedAt == nil ? amount : nil
    }

    var display: PriceDisplay {
        PriceDisplay(
            amount: effectiveAmount,
            currencyCode: currencyCode,
            source: source,
            sourceUpdatedAt: sourceUpdatedAt,
            fetchedAt: retrievedAt,
            lastCheckedAt: lastCheckedAt,
            refreshFailed: lastFailureAt != nil
        )
    }

    func apply(_ lookup: PriceLookup, at date: Date) {
        if case let .price(price) = lookup, let invalidatedAt, price.fetchedAt <= invalidatedAt { return }
        lastCheckedAt = date
        lastFailureAt = nil

        switch lookup {
        case let .price(price):
            guard Money(rounding: price.unitMarketPriceUSD) != nil else {
                lastFailureAt = date
                return
            }
            amount = price.unitMarketPriceUSD
            currencyCode = price.currencyCode
            sourceRaw = price.source.rawValue
            sourceVariantID = price.sourceVariantID
            sourceUpdatedAt = price.sourceUpdatedAt
            retrievedAt = price.fetchedAt
            catalogPriceIdentity = price.catalogIdentity
            invalidatedAt = nil

        case .unavailable:
            // An exact variant miss is a real answer, but it never erases a
            // previously useful quote. The result surface renders this lookup as
            // unavailable while the cache remains available for a later failure.
            break
        }
    }

    func recordFailure(at date: Date) {
        lastCheckedAt = date
        lastFailureAt = date
    }
}
