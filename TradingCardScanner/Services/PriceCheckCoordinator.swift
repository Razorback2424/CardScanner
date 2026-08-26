import Foundation
import SwiftData

enum PriceCheckRefreshOutcome {
    case quote(PriceLookup)
    case failed(PriceFallbackQuoteResolution.Failure)
}

/// The non-collection destination for a resolved scan. It owns only reference
/// quote caching and direct quote refresh, never collection valuation records.
@MainActor
final class PriceCheckCoordinator {
    private let cache: QuoteCache
    private let collectionPrices: PriceStore
    private let quoteService = PriceQuoteService()
    private let fallbackResolver: PriceFallbackQuoteResolver

    init(context: ModelContext) {
        cache = QuoteCache(context: context)
        collectionPrices = PriceStore(context: context)
        fallbackResolver = PriceFallbackQuoteResolver(context: context)
    }

    func present(_ resolvedScan: ResolvedScan) -> PriceCheckResult {
        let catalogQuote = CardPricing.price(
            for: resolvedScan.card,
            variant: resolvedScan.resolved.variant,
            pokemonPrintRun: resolvedScan.pokemonPrintRun
        )
        let key = quoteKey(for: resolvedScan)

        if Self.isUsableUSD(catalogQuote) {
            _ = cache.store(catalogQuote, game: key.game, printingID: key.printingID, variantID: key.variantID)
            return PriceCheckResult(resolvedScan: resolvedScan, quote: catalogQuote, checkedAt: .now)
        }

        // Initial presentation is read-only with respect to collection pricing:
        // it reuses only exact, successful evidence that already exists.
        if let local = newestLocalEvidence(for: key) {
            _ = cache.store(
                .price(local.price),
                game: key.game,
                printingID: key.printingID,
                variantID: key.variantID,
                at: local.retrievedAt
            )
            return PriceCheckResult(
                resolvedScan: resolvedScan,
                quote: .price(local.price),
                checkedAt: local.retrievedAt
            )
        }

        // A non-USD catalog amount is useful to the collection, but is not a
        // completed Price Check quote. Do not force a market call on present.
        let source: PriceSource?
        switch catalogQuote {
        case let .unavailable(provider): source = provider
        case let .price(price): source = price.source
        }
        return PriceCheckResult(
            resolvedScan: resolvedScan,
            quote: .unavailable(source),
            checkedAt: .now
        )
    }

    func refresh(_ result: PriceCheckResult) async -> PriceCheckRefreshOutcome {
        let resolvedScan = result.resolvedScan
        let key = quoteKey(for: resolvedScan)
        let catalogQuote: PriceLookup
        do {
            catalogQuote = try await quoteService.refresh(
                card: result.card,
                variant: result.resolved.variant,
                pokemonPrintRun: result.pokemonPrintRun
            )
        } catch is CancellationError {
            return .failed(.cancelled)
        } catch {
            return .failed(.requestFailed)
        }

        if Self.isUsableUSD(catalogQuote) {
            _ = cache.store(catalogQuote, game: key.game, printingID: key.printingID, variantID: key.variantID)
            return .quote(catalogQuote)
        }

        switch await fallbackResolver.resolve(
            card: result.card,
            variant: result.resolved.variant,
            pokemonPrintRun: result.pokemonPrintRun
        ) {
        case let .lookup(quote):
            _ = cache.store(quote, game: key.game, printingID: key.printingID, variantID: key.variantID)
            return .quote(quote)
        case let .failed(reason):
            return .failed(reason)
        }
    }

    func recordRefreshFailure(for result: PriceCheckResult) {
        let key = quoteKey(for: result.resolvedScan)
        _ = cache.recordFailure(game: key.game, printingID: key.printingID, variantID: key.variantID)
    }

    private struct QuoteKey {
        let game: CardGame
        let printingID: String
        let variantID: String?
    }

    private struct LocalEvidence {
        let price: NormalizedPrice
        let retrievedAt: Date
    }

    private func quoteKey(for resolvedScan: ResolvedScan) -> QuoteKey {
        QuoteKey(
            game: resolvedScan.card.game,
            printingID: PriceFallbackQuoteResolver.printingID(
                for: resolvedScan.card,
                pokemonPrintRun: resolvedScan.pokemonPrintRun
            ),
            variantID: resolvedScan.resolved.variant?.id
        )
    }

    /// Chooses by successful evidence time, not by last failed attempt. Ties
    /// consistently favor the quote cache Price Check already owns.
    private func newestLocalEvidence(for key: QuoteKey) -> LocalEvidence? {
        let record = collectionPrices.record(
            forKey: PriceRecord.key(game: key.game, printingID: key.printingID, variantID: key.variantID)
        ).flatMap(Self.evidence(from:))
        let reference = cache.quote(
            game: key.game,
            printingID: key.printingID,
            variantID: key.variantID
        ).flatMap(Self.evidence(from:))

        switch (record, reference) {
        case (nil, nil): return nil
        case let (evidence?, nil), let (nil, evidence?): return evidence
        case let (record?, reference?):
            return reference.retrievedAt >= record.retrievedAt ? reference : record
        }
    }

    private static func evidence(from record: PriceRecord) -> LocalEvidence? {
        guard let amount = record.unitMarketPriceUSD,
              Money(rounding: amount) != nil,
              let source = record.source,
              let sourceVariantID = record.sourceVariantID,
              !sourceVariantID.isEmpty,
              let fetchedAt = record.fetchedAt else {
            return nil
        }
        return LocalEvidence(
            price: NormalizedPrice(
                unitMarketPriceUSD: amount,
                currencyCode: record.currencyCode,
                source: source,
                sourceVariantID: sourceVariantID,
                sourceUpdatedAt: record.sourceUpdatedAt,
                fetchedAt: fetchedAt
            ),
            retrievedAt: fetchedAt
        )
    }

    private static func evidence(from quote: ReferenceQuote) -> LocalEvidence? {
        guard let amount = quote.amount,
              Money(rounding: amount) != nil,
              let source = quote.source,
              let sourceVariantID = quote.sourceVariantID,
              !sourceVariantID.isEmpty,
              let retrievedAt = quote.retrievedAt else {
            return nil
        }
        return LocalEvidence(
            price: NormalizedPrice(
                unitMarketPriceUSD: amount,
                currencyCode: quote.currencyCode,
                source: source,
                sourceVariantID: sourceVariantID,
                sourceUpdatedAt: quote.sourceUpdatedAt,
                fetchedAt: retrievedAt
            ),
            retrievedAt: retrievedAt
        )
    }

    private static func isUsableUSD(_ quote: PriceLookup) -> Bool {
        guard case let .price(price) = quote else { return false }
        return price.currencyCode.caseInsensitiveCompare("USD") == .orderedSame
            && Money(rounding: price.unitMarketPriceUSD) != nil
    }
}
