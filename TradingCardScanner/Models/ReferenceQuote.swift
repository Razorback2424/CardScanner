import Foundation
import SwiftData

struct CatalogQuoteKey: Hashable, Sendable {
    let game: CardGame
    let printingID: String
    let variantID: String?
    let treatmentIDs: [String]

    var rawValue: String {
        ReferenceQuote.key(game: game, printingID: printingID, variantID: variantID, treatmentIDs: treatmentIDs)
    }

    static func make(game: CardGame, providerID: String, printRun: PokemonPrintRun?,
                     variantID: String?, treatmentIDs: [String]) -> Self {
        Self(game: game, printingID: PriceFallbackQuoteResolver.printingID(for: providerID, pokemonPrintRun: printRun),
             variantID: variantID, treatmentIDs: MagicTreatmentKeyCodec.storedIDs(from: treatmentIDs))
    }

    static func make(for summary: CatalogCardSummary, variant: PhysicalVariant?) -> Self {
        make(game: summary.game, providerID: summary.providerID, printRun: summary.pokemonPrintRun,
             variantID: variant?.id,
             treatmentIDs: summary.magicTreatmentEvidence.applicableTreatments(for: variant).map(\.id))
    }

    static func gridKeys(for summary: CatalogCardSummary) -> [Self] {
        if let variant = summary.masterSetVariant {
            return [make(for: summary, variant: variant)]
        }
        if summary.game == .pokemon,
           PokemonTCGCSVMapping.byCardID[summary.providerID]?.setID == summary.setID.providerID {
            return [make(for: summary, variant: .holo)]
        }
        let variants = summary.verifiedBrowseFinishes
            ?? summary.magicFinishIDs?.compactMap { PhysicalVariant.resolving($0) } ?? []
        return variants.map { make(for: summary, variant: $0) }
    }
}

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
    /// Explicit completed checks only. Nil for legacy rows and retrieval-only evidence.
    var lastSuccessfulCheckAt: Date?
    var lastFailureAt: Date?
    var catalogPriceIdentity: String?
    var invalidatedAt: Date?
    /// A later exact check by this quote's own source found no USD quote.
    /// The amount stays as dated last-known evidence, but must not be promoted
    /// to a current Browse price. Nil for legacy rows and unconfirmed misses.
    var lastConfirmedMissAt: Date?

    /// The stored amount was disproved by its own source after retrieval.
    var hasConfirmedMiss: Bool {
        guard let lastConfirmedMissAt else { return false }
        return lastConfirmedMissAt > (retrievedAt ?? .distantPast)
    }

    func hasConfirmedMiss(for price: NormalizedPrice) -> Bool {
        source == price.source && lastConfirmedMissAt.map { $0 > price.fetchedAt } == true
    }

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
        guard invalidatedAt == nil,
              PortfolioPriceEligibility.eligibleUnitPrice(amount: amount, currencyCode: currencyCode) != nil else { return nil }
        return amount
    }

    var display: PriceDisplay {
        PriceDisplay(
            amount: effectiveAmount,
            currencyCode: "USD",
            source: source,
            sourceUpdatedAt: sourceUpdatedAt,
            fetchedAt: retrievedAt,
            lastCheckedAt: lastCheckedAt,
            refreshFailed: lastFailureAt != nil
        )
    }

    var normalizedPrice: NormalizedPrice? {
        guard let amount = effectiveAmount, let source, let sourceVariantID, !sourceVariantID.isEmpty,
              let retrievedAt else { return nil }
        return NormalizedPrice(unitMarketPriceUSD: amount, currencyCode: currencyCode, source: source,
            sourceVariantID: sourceVariantID, sourceUpdatedAt: sourceUpdatedAt, fetchedAt: retrievedAt,
            catalogIdentity: catalogPriceIdentity)
    }

    func apply(_ lookup: PriceLookup, at date: Date, isReplay: Bool = false) {
        if case let .price(price) = lookup, let invalidatedAt, price.fetchedAt <= invalidatedAt { return }
        // Cached catalog responses can finish after a newer lookup. Their
        // arrival time must not replace the newer price or its freshness.
        if case let .price(price) = lookup, let retrievedAt, price.fetchedAt < retrievedAt {
            guard let previous = normalizedPrice,
                  QuoteEvidenceOrdering.isNewer(price, than: previous, game: CardGame(rawValue: game)) else { return }
        }

        switch lookup {
        case let .price(price):
            guard price.unitMarketPriceUSD >= 0,
                  Money(rounding: price.unitMarketPriceUSD) != nil else {
                if !isReplay { recordFailure(at: date) }
                return
            }
            // A confirmed miss belongs to the source that reported it. Newer
            // evidence, or evidence from another source, supersedes it.
            if let miss = lastConfirmedMissAt, price.source != source || price.fetchedAt > miss {
                lastConfirmedMissAt = nil
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

        // Presenting an existing quote replays its retrieval date; it is not
        // a new successful check that can clear a later failed refresh.
        guard !isReplay, lastCheckedAt.map({ date >= $0 }) ?? true else { return }
        lastCheckedAt = date
        lastFailureAt = nil
    }

    func recordFailure(at date: Date) {
        guard lastCheckedAt.map({ date >= $0 }) ?? true else { return }
        lastCheckedAt = date
        lastFailureAt = date
    }
}
