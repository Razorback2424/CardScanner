import Foundation
import SwiftData

/// A stable diagnosis for an owned item that has no exact market price.
///
/// The raw value is intentionally support-friendly: it is written to diagnostic
/// CSVs and shown in the detail UI, so a screenshot and an export describe the
/// same state without someone having to infer it from a blank price.
enum PricingDiagnosticReason: String, Equatable, Sendable {
    case notChecked = "not_checked"
    case identityResolvedAfterFailedCheck = "identity_resolved_after_failed_check"
    case sealedProductPendingMatch = "sealed_product_match_pending"
    case sealedProductUnmatched = "sealed_product_unmatched"
    case noExactVariantPrice = "no_exact_variant_price"
    case gradedVariantUnavailable = "graded_variant_unavailable"
    case providerRequestFailed = "provider_request_failed"
    case gradedMarketPriceNull = "graded_market_price_null"
    case justTCGVariantUnresolved = "justtcg_variant_unresolved"

    var title: String {
        switch self {
        case .notChecked: return "Price not checked"
        case .identityResolvedAfterFailedCheck: return "Ready to retry pricing"
        case .sealedProductPendingMatch: return "Product match pending"
        case .sealedProductUnmatched: return "Product not matched"
        case .noExactVariantPrice: return "Exact variant has no price"
        case .gradedVariantUnavailable: return "Graded variant not found"
        case .providerRequestFailed: return "Price provider request failed"
        case .gradedMarketPriceNull: return "Graded market price unavailable"
        case .justTCGVariantUnresolved: return "Market variant not resolved"
        }
    }

    var detail: String {
        switch self {
        case .notChecked:
            return "Refresh prices to check this item."
        case .identityResolvedAfterFailedCheck:
            return "The catalog identity was resolved after the last failed price check. Refresh prices to try again."
        case .sealedProductPendingMatch:
            return "The imported sealed product has not completed a marketplace match yet."
        case .sealedProductUnmatched:
            return "The sealed marketplace catalog was searched, but no unambiguous product matched this imported row. It will not retry automatically until matching rules improve."
        case .noExactVariantPrice:
            return "The provider does not publish a price for the exact variant you own."
        case .gradedVariantUnavailable:
            return "No exact marketplace variant matches this grader and grade."
        case .providerRequestFailed:
            return "The last provider request failed. A later refresh can try again."
        case .gradedMarketPriceNull:
            return "The exact graded listing exists, but the provider currently reports no market price."
        case .justTCGVariantUnresolved:
            return "The marketplace card was identified, but its exact physical variant was not."
        }
    }
}

enum PricingDiagnostics {
    static func unpricedReason(
        for card: CollectedCard,
        record: PriceRecord?
    ) -> PricingDiagnosticReason {
        if card.itemKind == .sealedProduct, card.justTCGVariantID == nil {
            if card.justTCGCardID != nil { return .noExactVariantPrice }
            return CollectionCatalogNormalizer.isDefinitiveSealedMiss(card)
                ? .sealedProductUnmatched
                : .sealedProductPendingMatch
        }

        if card.itemKind == .gradedCard, card.justTCGVariantID == nil {
            return .gradedVariantUnavailable
        }

        guard let record, record.lastCheckedAt != nil else { return .notChecked }

        if card.catalogProviderID != nil,
           record.lastFailureAt != nil,
           let metadataCheckedAt = card.catalogMetadataCheckedAt,
           metadataCheckedAt > (record.lastCheckedAt ?? .distantPast) {
            return .identityResolvedAfterFailedCheck
        }

        switch card.itemKind {
        case .sealedProduct:
            return .noExactVariantPrice
        case .gradedCard:
            return record.lastFailureAt != nil
                ? .providerRequestFailed
                : .gradedMarketPriceNull
        case .rawCard:
            if record.lastFailureAt != nil { return .providerRequestFailed }
            if card.justTCGVariantID == nil, card.justTCGCardID != nil {
                return .justTCGVariantUnresolved
            }
            return .noExactVariantPrice
        }
    }
}

/// Why an owned item still has no artwork. Kept separate from price diagnostics
/// because a provider can publish either fact without publishing the other.
enum ArtworkDiagnosticReason: String, Equatable, Sendable {
    case lookupPending = "artwork_lookup_pending"
    case productNotMatched = "catalog_identity_not_resolved"
    case providerHasNoArtwork = "provider_has_no_artwork"

    var title: String {
        switch self {
        case .lookupPending: return "Artwork lookup pending"
        case .productNotMatched: return "Product artwork not matched"
        case .providerHasNoArtwork: return "Provider has no artwork"
        }
    }

    var detail: String {
        switch self {
        case .lookupPending:
            return "The next eligible refresh will ask the marketplace for this product image."
        case .productNotMatched:
            return "This imported product has not been matched unambiguously to a marketplace listing."
        case .providerHasNoArtwork:
            return "The marketplace listing was checked but does not publish a usable product image. You can add your own photo."
        }
    }
}

enum ArtworkDiagnostics {
    static func reason(for card: CollectedCard) -> ArtworkDiagnosticReason? {
        guard card.userArtworkFilename == nil, card.imageURL == nil else { return nil }

        if card.itemKind == .sealedProduct {
            if CollectionCatalogNormalizer.isDefinitiveSealedMiss(card) {
                return .productNotMatched
            }
            if card.justTCGVariantID == nil { return .productNotMatched }
            return shouldRetrySealedArtwork(for: card)
                ? .lookupPending
                : .providerHasNoArtwork
        }

        if card.catalogMetadataCheckedAt == nil { return .lookupPending }
        return card.catalogProviderID == nil ? .productNotMatched : .providerHasNoArtwork
    }

    /// Existing rows and rows last checked by older matching rules receive one
    /// marketplace backfill. A current-version response with no image is a
    /// terminal provider fact and must not consume quota forever.
    static func shouldRetrySealedArtwork(for card: CollectedCard) -> Bool {
        guard card.itemKind == .sealedProduct,
              card.imageURL == nil,
              card.justTCGVariantID != nil else {
            return false
        }
        return card.catalogMetadataCheckedAt == nil
            || card.catalogMetadataVersion != CollectionCatalogNormalizer.metadataVersion
    }
}

/// Reads and writes `PriceRecord`s.
///
/// Prices are keyed by printing plus variant, never by collection row, so eight
/// owned copies of one printing are one record to fetch, one to refresh and one
/// to keep fresh.
@MainActor
struct PriceStore {
    let context: ModelContext

    func record(forKey key: String) -> PriceRecord? {
        var descriptor = FetchDescriptor<PriceRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func allRecords() -> [PriceRecord] {
        (try? context.fetch(FetchDescriptor<PriceRecord>())) ?? []
    }

    nonisolated static func record(
        for card: CollectedCard,
        in recordsByKey: [String: PriceRecord]
    ) -> PriceRecord? {
        let candidates = card.priceLookupKeys.compactMap { recordsByKey[$0] }
        // Prefer a real observation over an empty canonical placeholder. The
        // legacy value is for the same exact object and remains better evidence
        // until the new key receives its own price.
        return candidates.first(where: { $0.unitMarketPriceUSD != nil }) ?? candidates.first
    }

    func importedCardsByProviderID() -> [String: [CollectedCard]] {
        let cards = (try? context.fetch(FetchDescriptor<CollectedCard>())) ?? []
        return Dictionary(
            grouping: cards.filter { $0.providerID.hasPrefix("csv:") },
            by: \.providerID
        )
    }

    /// Records what a provider said about one variant, creating the record if
    /// this is the first time the app has asked.
    func store(
        _ lookup: PriceLookup,
        game: CardGame,
        printingID: String,
        variantID: String?,
        at date: Date = .now
    ) {
        let key = PriceRecord.key(game: game, printingID: printingID, variantID: variantID)
        let record = self.record(forKey: key) ?? {
            let created = PriceRecord(key: key, game: game, printingID: printingID, variantID: variantID)
            context.insert(created)
            return created
        }()

        switch lookup {
        case let .price(price):
            record.apply(price)
        case let .unavailable(source):
            record.applyUnavailable(source: source, at: date)
        }
    }

    func storeImported(
        amount: Double,
        sourceUpdatedAt: Date?,
        game: CardGame,
        printingID: String,
        variantID: String?
    ) {
        let key = PriceRecord.key(game: game, printingID: printingID, variantID: variantID)
        let record = self.record(forKey: key) ?? {
            let created = PriceRecord(key: key, game: game, printingID: printingID, variantID: variantID)
            context.insert(created)
            return created
        }()
        guard record.unitMarketPriceUSD == nil else { return }
        record.applyImported(amount: amount, sourceUpdatedAt: sourceUpdatedAt)
    }

    /// A refresh attempt that never reached an answer. The previous price stays
    /// exactly where it was — an offline phone should show yesterday's price
    /// labelled as yesterday's, not nothing at all.
    func recordFailure(
        game: CardGame,
        printingID: String,
        variantID: String?,
        at date: Date = .now
    ) {
        let key = PriceRecord.key(game: game, printingID: printingID, variantID: variantID)
        let record = self.record(forKey: key) ?? {
            let created = PriceRecord(key: key, game: game, printingID: printingID, variantID: variantID)
            context.insert(created)
            return created
        }()
        record.recordFailure(at: date)
    }

    func save() {
        try? context.save()
    }
}
