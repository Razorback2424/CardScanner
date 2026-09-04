import Foundation
import SwiftData

/// A refresh can fail for several user-visible reasons. Keeping these separate
/// prevents a disabled fallback or an exhausted vendor budget from masquerading
/// as proof that the card has no price.
enum PriceCheckRefreshIssue: Equatable, Sendable {
    /// The provider matched the product but has no listing for its exact
    /// finish. This is the only terminal absence claim about the price.
    case noExactPrice
    /// The app could not match this card to a vendor product.
    case notMatched
    /// The app has no safe vendor mapping for this finish, so it did not ask.
    case unsupportedFinish
    /// The fallback provider has no treatment-specific identity, so it did not
    /// ask and the result is not evidence that the card is absent.
    case unsupportedTreatment
    case providerUnavailable
    case fallbackDisabled
    case fallbackUnconfigured
    case rateLimited(retryAt: Date)
    case budgetLimited(resetAt: Date)
}

/// The transient state of the Price Check sheet. `lastKnown` deliberately keeps
/// its issue so a cached amount remains useful without being presented as current.
enum PriceCheckQuoteState: Equatable, Sendable {
    case checking
    case current
    case lastKnown(PriceCheckRefreshIssue)
    case noExactPrice
    case notMatched
    case unsupportedFinish
    case unsupportedTreatment
    case providerUnavailable
    case fallbackDisabled
    case fallbackUnconfigured
    case rateLimited(retryAt: Date)
    case budgetLimited(resetAt: Date)
}

enum PriceCheckRefreshOutcome: Equatable, Sendable {
    case quote(PriceLookup)
    case failed(PriceCheckRefreshIssue)
    /// Cancellation is an internal lifecycle result and is never presented as
    /// provider failure. The view model ignores it when the request is stale.
    case cancelled
}

/// Small seam around the network portion of Price Check. The live implementation
/// preserves the provider order, while tests can exercise immediate/cached and
/// cancellation behavior without a real network request.
@MainActor
protocol PriceCheckRefreshProvider {
    func refresh(
        card: IdentifiedCard,
        variant: PhysicalVariant?,
        pokemonPrintRun: PokemonPrintRun?
    ) async -> PriceCheckRefreshOutcome
}

@MainActor
private final class LivePriceCheckRefreshProvider: PriceCheckRefreshProvider {
    private let quoteService: PriceQuoteService
    private let fallbackResolver: PriceFallbackQuoteResolver

    init(
        quoteService: PriceQuoteService = PriceQuoteService(),
        fallbackResolver: PriceFallbackQuoteResolver
    ) {
        self.quoteService = quoteService
        self.fallbackResolver = fallbackResolver
    }

    func refresh(
        card: IdentifiedCard,
        variant: PhysicalVariant?,
        pokemonPrintRun: PokemonPrintRun?
    ) async -> PriceCheckRefreshOutcome {
        do {
            let catalogQuote = try await quoteService.refresh(
                card: card,
                variant: variant,
                pokemonPrintRun: pokemonPrintRun
            )
            if case .price = catalogQuote,
               PriceCheckCoordinator.isUsableUSD(catalogQuote) {
                return .quote(catalogQuote)
            }
            return await fallback(
                card: card,
                variant: variant,
                pokemonPrintRun: pokemonPrintRun
            )
        } catch is CancellationError {
            return .cancelled
        } catch let error as URLError where error.code == .cancelled {
            return .cancelled
        } catch {
            // JustTCG is deliberately sequential: it is consulted only after
            // TCGdex fails or cannot provide a usable USD quote.
            return await fallback(
                card: card,
                variant: variant,
                pokemonPrintRun: pokemonPrintRun
            )
        }
    }

    private func fallback(
        card: IdentifiedCard,
        variant: PhysicalVariant?,
        pokemonPrintRun: PokemonPrintRun?
    ) async -> PriceCheckRefreshOutcome {
        switch await fallbackResolver.resolve(
            card: card,
            variant: variant,
            pokemonPrintRun: pokemonPrintRun
        ) {
        case let .lookup(.price(price)):
            return .quote(.price(price))
        case .lookup(.unavailable):
            return .failed(.noExactPrice)
        case .failed(.noExactPrice):
            return .failed(.noExactPrice)
        case .failed(.notMatched):
            return .failed(.notMatched)
        case .failed(.unsupportedFinish):
            return .failed(.unsupportedFinish)
        case .failed(.unsupportedTreatment):
            return .failed(.unsupportedTreatment)
        case .failed(.disabled):
            return .failed(.fallbackDisabled)
        case .failed(.missingCredentials):
            return .failed(.fallbackUnconfigured)
        case let .failed(.budgetReached(resetAt)):
            return .failed(.budgetLimited(resetAt: resetAt))
        case let .failed(.rateLimited(retryAt)):
            return .failed(.rateLimited(retryAt: retryAt))
        case .failed(.requestFailed):
            return .failed(.providerUnavailable)
        case .failed(.cancelled):
            return .cancelled
        }
    }
}

/// The non-collection destination for a resolved scan. It owns only reference
/// quote caching and direct quote refresh, never collection valuation records.
@MainActor
final class PriceCheckCoordinator {
    private let cache: QuoteCache
    private let collectionPrices: PriceStore
    private let refreshProvider: PriceCheckRefreshProvider

    init(
        context: ModelContext,
        refreshProvider: PriceCheckRefreshProvider? = nil
    ) {
        cache = QuoteCache(context: context)
        collectionPrices = PriceStore(context: context)
        let fallbackResolver = PriceFallbackQuoteResolver(context: context)
        self.refreshProvider = refreshProvider
            ?? LivePriceCheckRefreshProvider(fallbackResolver: fallbackResolver)
    }

    func present(_ resolvedScan: ResolvedScan) -> PriceCheckResult {
        let catalogQuote = CardPricing.price(
            for: resolvedScan.card,
            variant: resolvedScan.resolved.variant,
            magicTreatments: resolvedScan.card.magicTreatments(for: resolvedScan.resolved.variant),
            pokemonPrintRun: resolvedScan.pokemonPrintRun
        )
        let key = quoteKey(for: resolvedScan)

        if Self.isUsableUSD(catalogQuote) {
            _ = cache.store(
                catalogQuote,
                game: key.game,
                printingID: key.printingID,
                variantID: key.variantID,
                treatmentIDs: key.treatmentIDs
            )
            return PriceCheckResult(
                resolvedScan: resolvedScan,
                quote: catalogQuote,
                checkedAt: .now,
                quoteState: .current,
                // This quote came from the successful provider response that
                // resolved the scan. A second forced request would only add
                // latency and could turn a fresh quote into a false outage.
                shouldAutoRefresh: false
            )
        }

        // Initial presentation is read-only with respect to collection pricing:
        // it reuses only exact, successful evidence that already exists.
        if let local = newestLocalEvidence(for: key) {
            _ = cache.store(
                .price(local.price),
                game: key.game,
                printingID: key.printingID,
                variantID: key.variantID,
                at: local.retrievedAt,
                treatmentIDs: key.treatmentIDs
            )
            return PriceCheckResult(
                resolvedScan: resolvedScan,
                quote: .price(local.price),
                checkedAt: local.retrievedAt,
                quoteState: .current
            )
        }

        // A non-USD catalog amount is useful to the collection, but is not a
        // completed USD Price Check quote. The view model presents this state
        // immediately and schedules the one permitted background refresh.
        let source: PriceSource?
        switch catalogQuote {
        case let .unavailable(provider): source = provider
        case let .price(price): source = price.source
        }
        return PriceCheckResult(
            resolvedScan: resolvedScan,
            quote: .unavailable(source),
            checkedAt: .now,
            quoteState: .checking
        )
    }

    func refresh(_ result: PriceCheckResult) async -> PriceCheckRefreshOutcome {
        let outcome = await refreshProvider.refresh(
            card: result.card,
            variant: result.resolved.variant,
            pokemonPrintRun: result.pokemonPrintRun
        )
        if case let .quote(quote) = outcome,
           case .price = quote {
            let key = quoteKey(for: result.resolvedScan)
            _ = cache.store(
                quote,
                game: key.game,
                printingID: key.printingID,
                variantID: key.variantID,
                treatmentIDs: key.treatmentIDs
            )
        }
        if case .quote(.unavailable) = outcome {
            return .failed(.noExactPrice)
        }
        return outcome
    }

    func recordRefreshFailure(for result: PriceCheckResult) {
        let key = quoteKey(for: result.resolvedScan)
        _ = cache.recordFailure(
            game: key.game,
            printingID: key.printingID,
            variantID: key.variantID,
            treatmentIDs: key.treatmentIDs
        )
    }

    private struct QuoteKey {
        let game: CardGame
        let printingID: String
        let variantID: String?
        let treatmentIDs: [String]
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
            variantID: resolvedScan.resolved.variant?.id,
            treatmentIDs: MagicTreatmentKeyCodec.storedIDs(
                from: resolvedScan.card.magicTreatments(for: resolvedScan.resolved.variant)
            )
        )
    }

    /// Chooses by successful evidence time, not by last failed attempt. Ties
    /// consistently favor the quote cache Price Check already owns.
    private func newestLocalEvidence(for key: QuoteKey) -> LocalEvidence? {
        let record = collectionPrices.record(
            forKey: PriceRecord.key(
                game: key.game,
                printingID: key.printingID,
                variantID: key.variantID,
                treatmentIDs: key.treatmentIDs
            )
        ).flatMap(Self.evidence(from:))
        let reference = cache.quote(
            game: key.game,
            printingID: key.printingID,
            variantID: key.variantID,
            treatmentIDs: key.treatmentIDs
        ).flatMap(Self.evidence(from:))

        switch (record, reference) {
        case (nil, nil): return nil
        case let (evidence?, nil), let (nil, evidence?): return evidence
        case let (record?, reference?):
            return reference.retrievedAt >= record.retrievedAt ? reference : record
        }
    }

    private static func evidence(from record: PriceRecord) -> LocalEvidence? {
        guard let amount = record.effectiveUnitMarketPriceUSD,
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
        guard let amount = quote.effectiveAmount,
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

    static func isUsableUSD(_ quote: PriceLookup) -> Bool {
        guard case let .price(price) = quote else { return false }
        return price.currencyCode.caseInsensitiveCompare("USD") == .orderedSame
            && Money(rounding: price.unitMarketPriceUSD) != nil
    }
}
