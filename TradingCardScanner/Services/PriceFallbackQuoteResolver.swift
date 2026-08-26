import Foundation
import SwiftData

/// A single-card answer from the collection's USD fallback path.
///
/// A failed request is intentionally not represented as `.unavailable`: only
/// the vendor confirming that the exact product lacks the requested listing is
/// evidence that a price is unavailable.
enum PriceFallbackQuoteResolution: Equatable {
    case lookup(PriceLookup)
    case failed(Failure)

    enum Failure: Equatable {
        case disabled
        case missingCredentials
        case budgetReached(resetAt: Date)
        case rateLimited(retryAt: Date)
        case requestFailed
        case cancelled
    }
}

/// Reuses collection fallback matching for an individual quote without giving
/// Price Check ownership of collection valuation records.
///
/// The priority is deliberately fixed: a resolved marketplace variant is
/// exact by definition, then a verified stamped-product mapping, then the
/// identity-validated product search. This is the same order collection
/// refresh uses, expressed here without its batching and portfolio writes.
@MainActor
final class PriceFallbackQuoteResolver {
    private let context: ModelContext
    private let productService: ProductPriceService
    private let transport: JustTCGTransport

    init(
        context: ModelContext,
        productService: ProductPriceService = ProductPriceService.shared,
        transport: JustTCGTransport = JustTCGTransport.shared
    ) {
        self.context = context
        self.productService = productService
        self.transport = transport
    }

    /// Whether a catalog answer leaves work for the USD fallback. A non-USD
    /// catalog result remains displayable, but cannot finish a USD quote.
    nonisolated static func needsFallback(_ lookup: PriceLookup) -> Bool {
        switch lookup {
        case .unavailable:
            return true
        case let .price(price):
            return price.currencyCode.caseInsensitiveCompare("USD") != .orderedSame
        }
    }

    func resolve(
        card: IdentifiedCard,
        variant: PhysicalVariant?,
        pokemonPrintRun: PokemonPrintRun?
    ) async -> PriceFallbackQuoteResolution {
        guard UserDefaults.standard.bool(forKey: "usesPriceFallback") else {
            return .failed(.disabled)
        }
        guard PriceVendorCredentials.hasKey else {
            return .failed(.missingCredentials)
        }
        guard !Task.isCancelled else { return .failed(.cancelled) }
        await productService.beginRun()

        let printingID = Self.printingID(for: card, pokemonPrintRun: pokemonPrintRun)
        let key = ProductIdentity.key(game: card.game, printingID: printingID, variantID: variant?.id)
        let identities = ProductIdentityStore(context: context)
        let recordedVariantID = PriceStore(context: context)
            .record(forKey: PriceRecord.key(game: card.game, printingID: printingID, variantID: variant?.id))?
            .marketVariantID
        let target = MarketPriceTarget(
            priceKey: key,
            game: card.game,
            printingID: printingID,
            variantID: variant?.id,
            itemKind: .rawCard,
            // A collection record's resolved variant is the same exact
            // printing-and-finish identity as ProductIdentity's cache. Either
            // one takes precedence over a stamped mapping or a text search.
            marketVariantID: recordedVariantID ?? identities.cachedVariantID(forKey: key),
            lookupCandidates: Self.verifiedLookups(card: card, variant: variant),
            currentAmount: nil,
            lastCheckedAt: nil
        )

        if let lookup = target.lookup {
            // An unresolved cached vendor id is not evidence that this exact
            // listing is absent. `directQuote` returns a failure in that case,
            // so Price Check preserves a prior quote.
            return await directQuote(for: target, lookup: lookup)
        }

        // A previous definitive product mismatch is collection evidence, not a
        // reason for Price Check to silently retry a broad search.
        guard identities.needsResolution(forKey: key) else {
            return .failed(.requestFailed)
        }
        guard let subject = Self.subject(
            for: card,
            pokemonPrintRun: pokemonPrintRun,
            vendorCardID: identities.cachedCardID(forKey: key)
        ) else {
            return .failed(.requestFailed)
        }

        let outcome = await productService.quote(for: subject, variant: variant)
        guard !Task.isCancelled else { return .failed(.cancelled) }
        switch outcome {
        case let .price(price, _, _):
            return .lookup(.price(price))
        case .noListingForVariant:
            return .lookup(.unavailable(.justTCG))
        case .noProductMatch, .requestFailed:
            return .failed(.requestFailed)
        case let .budgetReached(resetAt):
            return .failed(.budgetReached(resetAt: resetAt))
        case let .rateLimited(retryAt):
            return .failed(.rateLimited(retryAt: retryAt))
        }
    }

    /// The verified marketplace product used for stamped Pokémon releases.
    /// These mappings are intentionally consulted before name/set matching.
    nonisolated static func verifiedLookups(
        card: IdentifiedCard,
        variant: PhysicalVariant?
    ) -> [JustTCGBatchLookup] {
        verifiedLookups(catalogID: card.providerID, variant: variant)
    }

    nonisolated static func verifiedLookups(
        catalogID: String,
        variant: PhysicalVariant?
    ) -> [JustTCGBatchLookup] {
        guard let variant,
              let stamped = PokemonStampedReleaseCatalog.entries(providerID: catalogID)
                .first(where: { $0.variant.id == variant.id }) else {
            return []
        }
        return [.tcgplayerID(stamped.tcgplayerProductID)]
    }

    nonisolated static func subject(
        for card: IdentifiedCard,
        pokemonPrintRun: PokemonPrintRun?,
        vendorCardID: String?
    ) -> ProductPriceSubject? {
        guard !card.name.isEmpty, !card.cardNumber.isEmpty else { return nil }
        return ProductPriceSubject(
            game: card.game,
            catalogID: card.providerID,
            name: card.name,
            setName: card.setName,
            cardNumber: card.cardNumber,
            japaneseSetID: japaneseSetID(forCatalogCardID: card.providerID),
            pokemonPrintRun: pokemonPrintRun,
            vendorCardID: vendorCardID
        )
    }

    nonisolated static func printingID(
        for card: IdentifiedCard,
        pokemonPrintRun: PokemonPrintRun?
    ) -> String {
        pokemonPrintRun.map { "\(card.providerID)@\($0.rawValue)" } ?? card.providerID
    }

    /// The `ja` set id embedded in a Japanese catalog card id — `M2-001` is
    /// set `M2`. This keeps Japanese matching aligned with collection refresh.
    nonisolated static func japaneseSetID(forCatalogCardID id: String) -> String? {
        guard CatalogIdentityNormalization.locale(forCatalogCardID: id) == .ja,
              let separator = id.lastIndex(of: "-") else { return nil }
        return String(id[id.startIndex..<separator])
    }

    private func directQuote(
        for target: MarketPriceTarget,
        lookup: JustTCGBatchLookup
    ) async -> PriceFallbackQuoteResolution {
        do {
            let client = JustTCGV1Client(transport: transport)
            let response = try await client.batchCards(
                [lookup],
                updatedAfter: nil,
                includePriceHistory: false,
                lane: .interactive
            )
            guard !Task.isCancelled else { return .failed(.cancelled) }

            switch JustTCGRefreshCoordinator.exactListing(
                lookup: lookup,
                owners: [target],
                response: response
            ) {
            case let .matched(_, variant):
                // A returned exact listing without a usable amount is not an
                // exact-listing miss. Match collection refresh by preserving a
                // prior quote instead of converting missing market data into a
                // definitive unavailable answer.
                guard let amount = variant.marketPriceUSD, Money(rounding: amount) != nil else {
                    return .failed(.requestFailed)
                }
                return .lookup(
                    .price(
                        NormalizedPrice(
                            unitMarketPriceUSD: amount,
                            currencyCode: "USD",
                            source: .justTCG,
                            sourceVariantID: variant.variantId ?? lookup.value,
                            sourceUpdatedAt: variant.updatedAt,
                            fetchedAt: .now
                        )
                    )
                )
            case .noExactListing:
                return .lookup(.unavailable(.justTCG))
            case .unresolved:
                return .failed(.requestFailed)
            }
        } catch is CancellationError {
            return .failed(.cancelled)
        } catch let error as JustTCGTransport.TransportError {
            switch error {
            case let .budgetReached(resetAt), let .monthlyBudgetReached(resetAt):
                return .failed(.budgetReached(resetAt: resetAt))
            case let .rateLimited(retryAt):
                return .failed(.rateLimited(retryAt: retryAt))
            case .missingCredentials:
                return .failed(.missingCredentials)
            case .invalidURL, .badResponse:
                return .failed(.requestFailed)
            }
        } catch {
            return .failed(.requestFailed)
        }
    }
}
