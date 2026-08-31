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
        await resolve(
            game: card.game,
            printingID: Self.printingID(for: card, pokemonPrintRun: pokemonPrintRun),
            catalogID: card.providerID,
            name: card.name,
            setName: card.setName,
            cardNumber: card.cardNumber,
            variant: variant,
            pokemonPrintRun: pokemonPrintRun,
            lookupCandidates: Self.directLookups(card: card, variant: variant)
        )
    }

    /// Resolves a stored collection identity without requiring a live catalog
    /// object. This is used by history corrections, where the collection row is
    /// the only identity available after the correction transaction completes.
    func resolve(
        card: CollectedCard,
        variant: PhysicalVariant?,
        pokemonPrintRun: PokemonPrintRun?
    ) async -> PriceFallbackQuoteResolution {
        let knownVariantID: String?
        if let variant, card.variantID == variant.id {
            knownVariantID = card.justTCGVariantID
        } else {
            knownVariantID = nil
        }
        var lookupCandidates: [JustTCGBatchLookup] = []
        if let tcgplayerProductID = card.tcgplayerProductID,
           !tcgplayerProductID.isEmpty {
            lookupCandidates.append(.tcgplayerID(tcgplayerProductID))
        }
        if let justTCGCardID = card.justTCGCardID,
           !justTCGCardID.isEmpty {
            lookupCandidates.append(.cardID(justTCGCardID))
        }
        return await resolve(
            game: card.cardGame,
            printingID: card.priceStorageID,
            catalogID: card.catalogProviderID ?? (card.providerID.hasPrefix("csv:") ? nil : card.providerID),
            name: card.name,
            setName: card.setName,
            cardNumber: card.cardNumber,
            variant: variant,
            pokemonPrintRun: pokemonPrintRun,
            marketVariantID: knownVariantID,
            lookupCandidates: lookupCandidates
        )
    }

    private func resolve(
        game: CardGame,
        printingID: String,
        catalogID: String?,
        name: String,
        setName: String,
        cardNumber: String,
        variant: PhysicalVariant?,
        pokemonPrintRun: PokemonPrintRun?,
        marketVariantID: String? = nil,
        lookupCandidates: [JustTCGBatchLookup] = []
    ) async -> PriceFallbackQuoteResolution {
        guard UserDefaults.standard.bool(forKey: "usesPriceFallback") else {
            return .failed(.disabled)
        }
        guard PriceVendorCredentials.hasKey else {
            return .failed(.missingCredentials)
        }
        guard !Task.isCancelled else { return .failed(.cancelled) }
        let key = ProductIdentity.key(game: game, printingID: printingID, variantID: variant?.id)
        let identities = ProductIdentityStore(context: context)
        let recordedVariantID = PriceStore(context: context)
            .record(forKey: PriceRecord.key(game: game, printingID: printingID, variantID: variant?.id))?
            .marketVariantID
        let target = MarketPriceTarget(
            priceKey: key,
            game: game,
            printingID: printingID,
            variantID: variant?.id,
            itemKind: .rawCard,
            // A collection record's resolved variant is the same exact
            // printing-and-finish identity as ProductIdentity's cache. Either
            // one takes precedence over a stamped mapping or a text search.
            marketVariantID: marketVariantID
                ?? recordedVariantID
                ?? identities.cachedVariantID(forKey: key),
            lookupCandidates: lookupCandidates,
            currentAmount: nil,
            lastCheckedAt: nil
        )

        if let lookup = target.lookup {
            // An unresolved cached vendor id is not evidence that this exact
            // listing is absent. `directQuote` returns a failure in that case,
            // so Price Check preserves a prior quote.
            return await directQuote(
                for: target,
                lookup: lookup,
                identities: identities,
                identityKey: key
            )
        }

        // A previous definitive product mismatch is collection evidence, not a
        // reason for Price Check to silently retry a broad search.
        guard identities.needsResolution(forKey: key) else {
            return .failed(.requestFailed)
        }
        guard let subject = Self.subject(
            game: game,
            catalogID: catalogID,
            name: name,
            setName: setName,
            cardNumber: cardNumber,
            pokemonPrintRun: pokemonPrintRun,
            vendorCardID: identities.cachedCardID(forKey: key)
        ) else {
            return .failed(.requestFailed)
        }

        let outcome = await productService.quote(
            for: subject,
            variant: variant,
            lane: .interactive
        )
        guard !Task.isCancelled else { return .failed(.cancelled) }
        // The expensive search is also the mapping resolution. Persist it
        // before returning the quote so the next Price Check or collection
        // refresh can use a keyed batch request instead of searching again.
        identities.record(outcome, forKey: key)
        identities.save()
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

    /// Direct provider identifiers avoid a paid name/set search. Stamped
    /// Pokémon releases have an app-maintained mapping; Magic cards can carry
    /// the same TCGplayer product id in Scryfall's purchase metadata.
    nonisolated static func directLookups(
        card: IdentifiedCard,
        variant: PhysicalVariant?
    ) -> [JustTCGBatchLookup] {
        var lookups = verifiedLookups(card: card, variant: variant)
        if case let .magic(magic) = card,
           let tcgplayerID = magic.tcgplayerID {
            lookups.append(.tcgplayerID(String(tcgplayerID)))
        }
        return lookups
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
        subject(
            game: card.game,
            catalogID: card.providerID,
            name: card.name,
            setName: card.setName,
            cardNumber: card.cardNumber,
            pokemonPrintRun: pokemonPrintRun,
            vendorCardID: vendorCardID
        )
    }

    nonisolated static func subject(
        game: CardGame,
        catalogID: String?,
        name: String,
        setName: String,
        cardNumber: String,
        pokemonPrintRun: PokemonPrintRun?,
        vendorCardID: String?
    ) -> ProductPriceSubject? {
        guard !name.isEmpty, !cardNumber.isEmpty else { return nil }
        return ProductPriceSubject(
            game: game,
            catalogID: catalogID,
            name: name,
            setName: setName,
            cardNumber: cardNumber,
            japaneseSetID: catalogID.flatMap(japaneseSetID(forCatalogCardID:)),
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
        lookup: JustTCGBatchLookup,
        identities: ProductIdentityStore,
        identityKey: String
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
            case let .matched(card, variant):
                identities.recordBatchResolution(
                    forKey: identityKey,
                    cardID: card.uuid ?? card.id,
                    variantID: variant.variantId,
                    at: .now
                )
                identities.save()
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
                if let card = Self.card(for: lookup, in: response) {
                    identities.record(
                        .noListingForVariant(vendorCardID: card.uuid ?? card.id),
                        forKey: identityKey
                    )
                    identities.save()
                }
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

    private static func card(
        for lookup: JustTCGBatchLookup,
        in response: JustTCGBatchResponse
    ) -> JustTCGCard? {
        switch lookup {
        case let .cardID(id):
            return response.data.first { $0.uuid == id || $0.id == id }
        case let .tcgplayerID(id):
            return response.data.first { $0.tcgplayerId == id }
        case let .tcgplayerSKUID(id):
            return response.data.first { card in
                card.variants?.contains { $0.tcgplayerSkuId == id } == true
            }
        case let .scryfallID(id):
            return response.data.first { $0.scryfallId == id }
        case let .mtgjsonID(id):
            return response.data.first { $0.mtgjsonId == id }
        case .variantID:
            return nil
        }
    }
}
