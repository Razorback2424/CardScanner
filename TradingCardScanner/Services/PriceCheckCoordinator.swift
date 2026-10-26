import Foundation
import SwiftData

/// A refresh can fail for several user-visible reasons. Keeping these separate
/// prevents a disabled fallback or an exhausted vendor budget from masquerading
/// as proof that the card has no price.
enum PriceCheckRefreshIssue: Equatable, Sendable {
    case mappingUnavailable
    case unsupportedGame
    /// The provider matched the product but has no listing for its exact
    /// finish. This is the only terminal absence claim about the price.
    case noExactPrice
    /// The app could not match this card to a vendor product.
    case notMatched
    /// The app has no safe vendor mapping for this finish, so it did not ask.
    case unsupportedFinish
    /// No direct vendor identity was available for this treatment, so the
    /// resolver did not use a name/set search and the result is not evidence
    /// that the card is absent.
    case unsupportedTreatment
    /// The card matched, but the exact grader/grade has no published variant.
    case gradedGradeNotPriced
    /// The underlying card could not be matched to a graded vendor product.
    case gradedProductNotMatched
    case gradedCardNotTracked
    case gradedCardHasNoPrices
    case gradedGradeNotTracked
    case providerUnavailable
    case fallbackDisabled
    case fallbackUnconfigured
    case rateLimited(retryAt: Date)
    case budgetLimited(resetAt: Date)
}

/// The transient state of the Price Check sheet. `lastKnown` deliberately keeps
/// its issue so a cached amount remains useful without being presented as current.
enum PriceCheckQuoteState: Equatable, Sendable {
    case mappingUnavailable
    case unsupportedGame
    case checking
    case current
    /// A usable quote whose market-data date exceeds the freshness policy.
    case stale
    case lastKnown(PriceCheckRefreshIssue)
    case noExactPrice
    case notMatched
    case unsupportedFinish
    case unsupportedTreatment
    case gradedGradeNotPriced
    case gradedProductNotMatched
    case gradedCardNotTracked
    case gradedCardHasNoPrices
    case gradedGradeNotTracked
    case providerUnavailable
    case fallbackDisabled
    case fallbackUnconfigured
    case rateLimited(retryAt: Date)
    case budgetLimited(resetAt: Date)
}

enum PriceCheckRefreshOutcome: Equatable, Sendable {
    case quote(PriceLookup)
    case lastKnown(PriceLookup, PriceCheckRefreshIssue)
    case failed(PriceCheckRefreshIssue)
    /// Cancellation is an internal lifecycle result and is never presented as
    /// provider failure. The view model ignores it when the request is stale.
    case cancelled
}

typealias PriceCheckContinuationCheck = @MainActor @Sendable () -> Bool

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
final class LivePriceCheckRefreshProvider: PriceCheckRefreshProvider {
    private let quoteService: PriceQuoteService
    private let fallbackResolver: PriceFallbackQuoteResolver
    private let fallbackOverride: ((IdentifiedCard, PhysicalVariant?, PokemonPrintRun?) async -> PriceCheckRefreshOutcome)?

    init(
        quoteService: PriceQuoteService = PriceQuoteService(),
        fallbackResolver: PriceFallbackQuoteResolver,
        fallbackOverride: ((IdentifiedCard, PhysicalVariant?, PokemonPrintRun?) async -> PriceCheckRefreshOutcome)? = nil
    ) {
        self.quoteService = quoteService
        self.fallbackResolver = fallbackResolver
        self.fallbackOverride = fallbackOverride
    }

    func refresh(
        card: IdentifiedCard,
        variant: PhysicalVariant?,
        pokemonPrintRun: PokemonPrintRun?
    ) async -> PriceCheckRefreshOutcome {
        guard quoteService.supportsPricing(for: card.game) else {
            return .failed(.unsupportedGame)
        }
        do {
            let catalogQuote = try await quoteService.refresh(
                card: card,
                variant: variant,
                pokemonPrintRun: pokemonPrintRun
            )
            if case .price = catalogQuote,
               PriceCheckCoordinator.isUsableUSD(catalogQuote) {
                if card.game == .pokemon,
                   case let .price(price) = catalogQuote, price.isStale(),
                   quoteService.allowsProviderFallback(for: card.game) {
                    let alternate = await fallback(card: card, variant: variant, pokemonPrintRun: pokemonPrintRun)
                    if case .cancelled = alternate { return .cancelled }
                    if case let .quote(.price(newer)) = alternate,
                       newer.isUsableUSD, let sourceDate = newer.sourceUpdatedAt,
                       sourceDate > price.effectiveAsOf {
                        return alternate
                    }
                    if case let .failed(issue) = alternate {
                        return .lastKnown(catalogQuote, issue)
                    }
                }
                return .quote(catalogQuote)
            }
            guard quoteService.allowsProviderFallback(for: card.game) else { return .quote(catalogQuote) }
            return await fallback(
                card: card,
                variant: variant,
                pokemonPrintRun: pokemonPrintRun
            )
        } catch is CancellationError {
            return .cancelled
        } catch let error as URLError where error.code == .cancelled {
            return .cancelled
        } catch PriceQuoteError.pricingUnsupported {
            return .failed(.unsupportedGame)
        } catch PriceQuoteError.identityMismatch {
            return .failed(.notMatched)
        } catch PriceQuoteError.mappingUnavailable {
            return .failed(.mappingUnavailable)
        } catch {
            guard quoteService.allowsProviderFallback(for: card.game) else { return .failed(.providerUnavailable) }
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
        if let fallbackOverride {
            return await fallbackOverride(card, variant, pokemonPrintRun)
        }
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
        case .failed(.unsupportedGame):
            return .failed(.unsupportedGame)
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
    private let gradedResolver: ScannedGradedResolving
    private let quoteService: PriceQuoteService
    private let now: () -> Date

    init(
        context: ModelContext,
        refreshProvider: PriceCheckRefreshProvider? = nil,
        quoteService: PriceQuoteService = PriceQuoteService(),
        gradedResolver: ScannedGradedResolving = ScannedGradedResolver(),
        now: @escaping () -> Date = { .now }
    ) {
        cache = QuoteCache(context: context)
        collectionPrices = PriceStore(context: context)
        let fallbackResolver = PriceFallbackQuoteResolver(context: context)
        self.refreshProvider = refreshProvider
            ?? LivePriceCheckRefreshProvider(quoteService: quoteService, fallbackResolver: fallbackResolver)
        self.gradedResolver = gradedResolver
        self.quoteService = quoteService
        self.now = now
    }

    private func requiresPhysicalReview(_ scan: ResolvedScan) -> Bool {
        guard scan.card.game == .pokemon, let finish = scan.resolved.variant else { return false }
        return PokemonVariantRules.requiresPhysicalReview(cardID: scan.card.providerID, variant: finish)
    }

    func present(_ resolvedScan: ResolvedScan) -> PriceCheckResult {
        if requiresPhysicalReview(resolvedScan) {
            return PriceCheckResult(resolvedScan: resolvedScan, quote: .unavailable(nil),
                checkedAt: resolvedScan.catalogRetrievedAt, quoteState: .unsupportedFinish, shouldAutoRefresh: false)
        }
        if resolvedScan.request.subject.slab != nil {
            let quote: PriceLookup
            let state: PriceCheckQuoteState
            switch resolvedScan.gradedOutcome {
            case let .bound(variant):
                if let amount = variant.marketPriceUSD {
                    quote = .price(
                        NormalizedPrice(
                            unitMarketPriceUSD: amount,
                            currencyCode: "USD",
                            source: .justTCG,
                            sourceVariantID: variant.id,
                            sourceUpdatedAt: variant.updatedAt,
                            fetchedAt: .now
                        )
                    )
                    state = .current
                } else {
                    quote = .unavailable(.justTCG)
                    state = .gradedGradeNotPriced
                }
            case .cardNotTracked:
                quote = .unavailable(.justTCG)
                state = .gradedCardNotTracked
            case .noGradedListings:
                quote = .unavailable(.justTCG)
                state = .gradedCardHasNoPrices
            case .gradeNotTracked:
                quote = .unavailable(.justTCG)
                state = .gradedGradeNotTracked
            case .none:
                quote = .unavailable(PriceVendorCredentials.hasKey ? .justTCG : nil)
                state = .checking
            case .unavailable:
                quote = .unavailable(PriceVendorCredentials.hasKey ? .justTCG : nil)
                state = PriceVendorCredentials.hasKey ? .providerUnavailable : .fallbackUnconfigured
            }
            let shouldAutoRefresh = state == .checking
                || state == .providerUnavailable
                || state == .fallbackUnconfigured
            if case let .bound(variant)? = resolvedScan.gradedOutcome,
               case .price = quote {
                let key = QuoteKey(
                    game: resolvedScan.card.game,
                    printingID: "justtcg:v2:\(variant.id)",
                    variantID: nil,
                    treatmentIDs: []
                )
                _ = cache.store(
                    quote,
                    game: key.game,
                    printingID: key.printingID,
                    variantID: key.variantID,
                    treatmentIDs: key.treatmentIDs
                )
            }
            return PriceCheckResult(
                resolvedScan: resolvedScan,
                quote: quote,
                checkedAt: .now,
                quoteState: state,
                shouldAutoRefresh: shouldAutoRefresh
            )
        }

        let catalogQuote = CardPricing.price(
            for: resolvedScan.card,
            variant: resolvedScan.resolved.variant,
            magicTreatments: resolvedScan.card.magicTreatments(for: resolvedScan.resolved.variant),
            pokemonPrintRun: resolvedScan.pokemonPrintRun,
            at: resolvedScan.catalogRetrievedAt
        )
        let key = quoteKey(for: resolvedScan)
        let localEvidence = newestLocalEvidence(for: key)

        if Self.isUsableUSD(catalogQuote),
           let catalogEvidence = Self.evidence(from: catalogQuote),
           localEvidence.map({ Self.isNewer(catalogEvidence, than: $0, game: key.game) }) ?? true {
            _ = cache.store(
                catalogQuote,
                game: key.game,
                printingID: key.printingID,
                variantID: key.variantID,
                at: catalogEvidence.retrievedAt,
                treatmentIDs: key.treatmentIDs,
                isReplay: true
            )
            return presentEvidence(
                resolvedScan, key: key,
                quote: catalogQuote,
                retrievedAt: catalogEvidence.retrievedAt,
                quoteState: key.game == .pokemon && Self.isStale(catalogEvidence, game: key.game, now: now()) ? .stale : .current,
                // Identification stays fast, but an old session-cache payload
                // must not disable the newer-price check.
                shouldAutoRefresh: Self.isStale(catalogEvidence, game: key.game, now: now())
            )
        }

        // Initial presentation is read-only with respect to collection pricing:
        // it reuses only exact, successful evidence that already exists.
        if let local = localEvidence {
            _ = cache.store(
                .price(local.price),
                game: key.game,
                printingID: key.printingID,
                variantID: key.variantID,
                at: local.retrievedAt,
                treatmentIDs: key.treatmentIDs,
                isReplay: true
            )
            let localLookup = PriceLookup.price(local.price)
            guard Self.isUsableUSD(localLookup) else {
                // Keep the native-currency evidence visible, but do not call
                // it a completed USD Price Check. The default refresh flag
                // schedules the one permitted background attempt.
                return presentEvidence(
                    resolvedScan, key: key,
                    quote: localLookup,
                    retrievedAt: local.retrievedAt,
                    quoteState: .checking
                )
            }
            return presentEvidence(
                resolvedScan, key: key,
                quote: localLookup,
                retrievedAt: local.retrievedAt,
                quoteState: key.game == .pokemon && Self.isStale(local, game: key.game, now: now()) ? .stale : .current,
                shouldAutoRefresh: Self.isStale(local, game: key.game, now: now())
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

    func refresh(
        _ result: PriceCheckResult,
        shouldContinue: PriceCheckContinuationCheck? = nil
    ) async -> PriceCheckRefreshOutcome {
        guard shouldContinue?() ?? true else { return .cancelled }
        guard !requiresPhysicalReview(result.resolvedScan) else { return .failed(.unsupportedFinish) }
        if let slab = result.resolvedScan.request.subject.slab {
            guard quoteService.supportsGradedPricing(for: result.card.game) else {
                return .failed(.unsupportedGame)
            }
            let outcome = await gradedResolver.resolve(
                card: result.card,
                slab: GradedSlabEvidence(company: slab.company, grade: slab.grade,
                    certificationNumber: slab.certificationNumber, labelCardText: slab.labelCardText,
                    printedFinish: result.resolvedScan.resolved.variant ?? slab.printedFinish,
                    printedPrintRun: result.pokemonPrintRun ?? slab.printedPrintRun),
                pokemonPrintRun: result.pokemonPrintRun
            )
            guard shouldContinue?() ?? true else { return .cancelled }
            switch outcome {
            case let .bound(variant):
                guard let amount = variant.marketPriceUSD else {
                    return .failed(.gradedGradeNotPriced)
                }
                let quote: PriceLookup = .price(
                    NormalizedPrice(
                        unitMarketPriceUSD: amount,
                        currencyCode: "USD",
                        source: .justTCG,
                        sourceVariantID: variant.id,
                        sourceUpdatedAt: variant.updatedAt,
                        fetchedAt: .now
                    )
                )
                guard shouldContinue?() ?? true else { return .cancelled }
                let key = quoteKey(for: result.resolvedScan, gradedVariant: variant)
                _ = cache.store(
                    quote,
                    game: key.game,
                    printingID: key.printingID,
                    variantID: key.variantID,
                    treatmentIDs: key.treatmentIDs
                )
                return .quote(quote)
            case .cardNotTracked:
                return .failed(.gradedCardNotTracked)
            case .noGradedListings:
                return .failed(.gradedCardHasNoPrices)
            case .gradeNotTracked:
                return .failed(.gradedGradeNotTracked)
            case .unavailable:
                return PriceVendorCredentials.hasKey
                    ? .failed(.providerUnavailable)
                    : .failed(.fallbackUnconfigured)
            }
        }

        var outcome = await refreshProvider.refresh(
            card: result.card,
            variant: result.resolved.variant,
            pokemonPrintRun: result.pokemonPrintRun
        )
        guard !Task.isCancelled, shouldContinue?() ?? true else { return .cancelled }
        let lookup: PriceLookup?
        let issue: PriceCheckRefreshIssue?
        switch outcome {
        case let .quote(value): lookup = value; issue = nil
        case let .lastKnown(value, failure): lookup = value; issue = failure
        case .failed, .cancelled: return outcome
        }
        if case let .price(price)? = lookup, !price.isUsableUSD {
            return .failed(.providerUnavailable)
        }
        if case .unavailable(nil)? = lookup {
            return .failed(.providerUnavailable)
        }
        if result.card.game == .pokemon,
           case let .price(candidate)? = lookup,
           case let .price(previous) = result.quote, previous.isUsableUSD,
           (candidate.effectiveAsOf < previous.effectiveAsOf
            || (previous.sourceUpdatedAt != nil && candidate.sourceUpdatedAt == nil)) {
            // A successful check can still return older upstream data.
            // Preserve the better quote while the view records this new check.
            outcome = issue.map { .lastKnown(result.quote, $0) } ?? .quote(result.quote)
        }
        let successfulQuote: PriceLookup?
        switch outcome {
        case let .quote(value), let .lastKnown(value, _): successfulQuote = value
        default: successfulQuote = nil
        }
        if let quote = successfulQuote,
           case .price = quote {
            let key = quoteKey(for: result.resolvedScan)
            let completedAt = now()
            _ = cache.store(
                quote,
                game: key.game,
                printingID: key.printingID,
                variantID: key.variantID,
                at: completedAt,
                treatmentIDs: key.treatmentIDs,
                successfulCheckAt: completedAt
            )
            if issue != nil {
                _ = cache.recordFailure(game: key.game, printingID: key.printingID,
                    variantID: key.variantID, at: completedAt, treatmentIDs: key.treatmentIDs)
            }
        }
        if case .quote(.unavailable) = outcome {
            return .failed(.noExactPrice)
        }
        return outcome
    }

    func lastSuccessfulCheckAt(for result: PriceCheckResult) -> Date? {
        let key = quoteKey(for: result.resolvedScan)
        return cache.quote(game: key.game, printingID: key.printingID,
            variantID: key.variantID, treatmentIDs: key.treatmentIDs)?.lastSuccessfulCheckAt
    }

    @discardableResult
    func recordRefreshFailure(
        for result: PriceCheckResult,
        shouldContinue: PriceCheckContinuationCheck? = nil
    ) -> Date? {
        guard shouldContinue?() ?? true else { return nil }
        let key = quoteKey(for: result.resolvedScan)
        let attemptedAt = now()
        _ = cache.recordFailure(
            game: key.game,
            printingID: key.printingID,
            variantID: key.variantID,
            at: attemptedAt,
            treatmentIDs: key.treatmentIDs
        )
        return attemptedAt
    }

    private struct QuoteKey {
        let game: CardGame
        let printingID: String
        let variantID: String?
        let treatmentIDs: [String]
    }

    /// A cached quote's retrieval is not proof of when a later check succeeded.
    /// Replaying evidence must also leave a subsequent failed attempt visible.
    private func presentEvidence(
        _ scan: ResolvedScan, key: QuoteKey, quote: PriceLookup, retrievedAt: Date,
        quoteState: PriceCheckQuoteState, shouldAutoRefresh: Bool = true
    ) -> PriceCheckResult {
        let cached = cache.quote(game: key.game, printingID: key.printingID,
            variantID: key.variantID, treatmentIDs: key.treatmentIDs)
        var result = PriceCheckResult(resolvedScan: scan, quote: quote,
            checkedAt: cached?.lastCheckedAt ?? retrievedAt,
            quoteState: quoteState, shouldAutoRefresh: shouldAutoRefresh)
        result.lastSuccessfulCheckAt = cached?.lastSuccessfulCheckAt
        result.checkTimeIsRetrievalEvidence = result.lastSuccessfulCheckAt == nil
        result.refreshFailed = cached?.lastFailureAt != nil
        result.refreshFeedback = result.refreshFailed ? .failed : nil
        return result
    }

    private struct LocalEvidence {
        let price: NormalizedPrice
        let retrievedAt: Date
    }

    private func quoteKey(for resolvedScan: ResolvedScan) -> QuoteKey {
        if case let .bound(variant)? = resolvedScan.gradedOutcome {
            return quoteKey(for: resolvedScan, gradedVariant: variant)
        }
        return QuoteKey(
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

    private func quoteKey(
        for resolvedScan: ResolvedScan,
        gradedVariant: GradedVariant
    ) -> QuoteKey {
        QuoteKey(
            game: resolvedScan.card.game,
            printingID: "justtcg:v2:\(gradedVariant.id)",
            variantID: nil,
            treatmentIDs: []
        )
    }

    /// Chooses by market-data time, then successful retrieval, never a failed attempt. Ties
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

        let evidence = [record, reference].compactMap { $0 }
        guard !evidence.isEmpty else { return nil }
        let usdEvidence = evidence.filter {
            $0.price.currencyCode.caseInsensitiveCompare("USD") == .orderedSame
        }
        return (usdEvidence.isEmpty ? evidence : usdEvidence)
            .max(by: { Self.isNewer($1, than: $0, game: key.game) })
    }

    private static func isNewer(_ candidate: LocalEvidence, than previous: LocalEvidence, game: CardGame) -> Bool {
        guard game == .pokemon else { return candidate.retrievedAt > previous.retrievedAt }
        if previous.price.sourceUpdatedAt != nil, candidate.price.sourceUpdatedAt == nil { return false }
        if candidate.price.sourceUpdatedAt != nil, previous.price.sourceUpdatedAt == nil {
            return candidate.price.effectiveAsOf > previous.price.effectiveAsOf
        }
        if candidate.price.effectiveAsOf != previous.price.effectiveAsOf {
            return candidate.price.effectiveAsOf > previous.price.effectiveAsOf
        }
        return candidate.retrievedAt > previous.retrievedAt
    }

    private static func evidence(from record: PriceRecord) -> LocalEvidence? {
        // Price Check and collection valuation share the current USD contract;
        // historical native-currency observations remain in durable storage.
        guard let amount = record.display.amount,
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
                fetchedAt: fetchedAt, catalogIdentity: record.catalogPriceIdentity
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
                fetchedAt: retrievedAt, catalogIdentity: quote.catalogPriceIdentity
            ),
            retrievedAt: retrievedAt
        )
    }

    private static func evidence(from lookup: PriceLookup) -> LocalEvidence? {
        guard case let .price(price) = lookup,
              Money(rounding: price.unitMarketPriceUSD) != nil,
              !price.sourceVariantID.isEmpty else {
            return nil
        }
        return LocalEvidence(price: price, retrievedAt: price.fetchedAt)
    }

    private static func isStale(_ evidence: LocalEvidence, game: CardGame, now: Date = .now) -> Bool {
        game == .pokemon ? evidence.price.isStale(now: now)
            : now.timeIntervalSince(evidence.retrievedAt) > PriceDisplay.staleAfter
    }

    static func isUsableUSD(_ quote: PriceLookup) -> Bool {
        guard case let .price(price) = quote else { return false }
        return PortfolioPriceEligibility.participatesInPortfolioValue(
            amount: price.unitMarketPriceUSD,
            currencyCode: price.currencyCode
        )
    }
}
