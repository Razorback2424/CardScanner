import Foundation

/// Refreshes only a card that has already been resolved. It never receives OCR
/// evidence, so a refresh cannot silently re-identify the card in someone's hand.
struct PokemonPriceAdapter: GamePriceAdapter {
    let game = CardGame.pokemon
    private let tcgdex = TCGdexService()
    /// The same breaker the catalog uses. TCGdex being down is one fact about
    /// one host; discovering it twice costs a second connect timeout per scan.
    private let tcgdexCircuit = TCGdexCircuitBreaker.shared
    private let marketPrices: PokemonMarketPriceResolver
    private let catalogCoordinator: PokemonCatalogCoordinator?

    init(
        tcgCSVSource: any PokemonTCGCSVPriceSource = PokemonTCGCSVPriceService.shared,
        productPriceSource: TCGCSVProductPriceSource = .shared,
        catalogCoordinator: PokemonCatalogCoordinator? = nil
    ) {
        marketPrices = PokemonMarketPriceResolver(source: tcgCSVSource, productSource: productPriceSource)
        self.catalogCoordinator = catalogCoordinator
    }

    func refresh(_ request: GamePriceRequest) async throws -> PriceLookup {
        let card = request.identity
        let variant = request.variant
        let pokemonPrintRun = request.pokemonPrintRun
        guard card.game == game else { throw PriceQuoteError.identityMismatch }
        if let product = PokemonReviewedMarketProduct.entry(cardID: card.printingID, variantID: variant?.id) {
            guard pokemonPrintRun == nil, card.language == "en", card.setID == product.setID,
                  ProductCatalogIdentity.numbersMatch(product.number, card.cardNumber) else {
                throw PriceQuoteError.identityMismatch
            }
            return try await marketPrices.quote(for: product, minimumFetchedAt: request.minimumFetchedAt)
        }
        if PokemonReviewedMarketProduct.usesReviewedVariantsOnly(cardID: card.printingID, setID: card.setID) {
            if let promo = PokemonDeltaReignCatalog.card(card.printingID), promo.isPromo, pokemonPrintRun == nil,
               card.language == "en", promo.setID == card.setID,
               ProductCatalogIdentity.numbersMatch(promo.number, card.cardNumber),
               promo.printings.contains(where: { $0.variant.id == variant?.id }) { return .unavailable(nil) }
            throw PriceQuoteError.identityMismatch
        }
        let catalog: PriceLookup
        do {
            if let catalogRefreshOverride = request.catalogRefreshOverride {
                catalog = try await catalogRefreshOverride()
            } else {
                catalog = try await refreshCatalog(card: card, variant: variant, pokemonPrintRun: pokemonPrintRun)
            }
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if case PriceQuoteError.identityMismatch = error { throw error }
            if let fallback = try await marketPrices.fallback(
                cardID: card.printingID, game: card.game, variant: variant,
                printRun: pokemonPrintRun, retry: true
            ) { return fallback }
            throw error
        }
        if case let .price(price) = catalog, price.currencyCode == "USD" { return catalog }
        return try await marketPrices.fallback(
            cardID: card.printingID, game: card.game, variant: variant,
            printRun: pokemonPrintRun, retry: true
        ) ?? catalog
    }

    private func refreshCatalog(
        card: GamePriceIdentity,
        variant: PhysicalVariant?,
        pokemonPrintRun: PokemonPrintRun?
    ) async throws -> PriceLookup {
        let refreshed: IdentifiedCard
        guard await tcgdexCircuit.permitsRequest() else {
            throw PriceQuoteError.providerUnavailable
        }
        let returned: TCGdexCard
        do {
            returned = try await tcgdex.fetchCard(
                id: card.printingID,
                locale: CatalogIdentityNormalization.locale(forCatalogCardID: card.printingID),
                ignoringCache: true,
                recoversArtwork: false
            )
            // A successfully decoded full-card response proves that the
            // host answered, even if its identity does not match the card
            // being refreshed. Record transport health before validating
            // identity so a bad redirect cannot leave the circuit open.
            await tcgdexCircuit.recordSuccess()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as TCGdexError {
            // A missing card, malformed identifier, or identity mismatch is
            // definitive card evidence, not a host outage. Do not open the
            // shared provider circuit for those results.
            switch error {
            case .cardNotFound, .identityMismatch, .invalidURL:
                throw error
            case .badResponse, .providerUnavailable:
                await tcgdexCircuit.recordFailure(.serverError)
                throw error
            }
        } catch {
            guard Self.shouldRecordCircuitFailure(for: error) else { throw error }
            await tcgdexCircuit.recordFailure(
                Self.failureKind(for: error)
            )
            throw error
        }
        let authorized: TCGdexCard
        if let catalogCoordinator {
            authorized = returned.applyingAdditionalVariants(from: await catalogCoordinator.registry)
        } else { authorized = returned }
        refreshed = .pokemon(authorized, setCode: card.displaySetCode)

        guard card.matches(.legacy(refreshed)) else {
            throw PriceQuoteError.identityMismatch
        }
        return CardPricing.price(
            for: refreshed,
            variant: variant,
            magicTreatments: refreshed.magicTreatments(for: variant),
            pokemonPrintRun: pokemonPrintRun,
            at: .now
        )
    }

    /// A `badResponse` means TCGdex answered; anything else means it did not.
    /// The distinction decides how long the breaker stays open.
    static func failureKind(for error: Error) -> TCGdexCircuitBreaker.Failure {
        if case TCGdexError.badResponse = error { return .serverError }
        return .unreachable
    }

    static func shouldRecordCircuitFailure(for error: Error) -> Bool {
        if error is CancellationError { return false }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return false
        }
        if let tcgdexError = error as? TCGdexError {
            switch tcgdexError {
            case .cardNotFound, .identityMismatch, .invalidURL:
                return false
            case .badResponse, .providerUnavailable:
                return true
            }
        }
        return true
    }

}
