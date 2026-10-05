import Foundation

struct PokemonPriceAdapter: GamePriceAdapter {
    var game: CardGame { .pokemon }
    private let tcgdex = TCGdexService()
    private let circuit = TCGdexCircuitBreaker.shared
    private let marketPrices: PokemonMarketPriceResolver

    init(tcgCSVSource: any PokemonTCGCSVPriceSource = PokemonTCGCSVPriceService.shared) {
        marketPrices = PokemonMarketPriceResolver(source: tcgCSVSource)
    }

    func refresh(_ request: GamePriceRequest) async throws -> PriceLookup {
        guard request.identity.game == game else { throw PriceQuoteError.identityMismatch }
        let catalog: PriceLookup
        do {
            if let override = request.catalogRefreshOverride {
                catalog = try await override()
            } else {
                catalog = try await refreshCatalog(request)
            }
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if case PriceQuoteError.identityMismatch = error { throw error }
            if let fallback = try await fallback(request) { return fallback }
            throw error
        }
        if case let .price(price) = catalog, price.currencyCode == "USD" { return catalog }
        return try await fallback(request) ?? catalog
    }

    private func fallback(_ request: GamePriceRequest) async throws -> PriceLookup? {
        try await marketPrices.fallback(cardID: request.identity.printingID, game: game,
            variant: request.variant, printRun: request.pokemonPrintRun, retry: true)
    }

    private func refreshCatalog(_ request: GamePriceRequest) async throws -> PriceLookup {
        guard await circuit.permitsRequest() else { throw PriceQuoteError.providerUnavailable }
        let returned: TCGdexCard
        do {
            returned = try await tcgdex.fetchCard(id: request.identity.printingID,
                locale: CatalogIdentityNormalization.locale(forCatalogCardID: request.identity.printingID),
                ignoringCache: true)
            // Transport health is independent of identity validation.
            await circuit.recordSuccess()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as TCGdexError {
            switch error {
            case .cardNotFound, .identityMismatch, .invalidURL: throw error
            case .badResponse:
                await circuit.recordFailure(.serverError)
                throw error
            }
        } catch {
            guard Self.shouldRecordCircuitFailure(for: error) else { throw error }
            await circuit.recordFailure(Self.failureKind(for: error))
            throw error
        }
        let card = IdentifiedCard.pokemon(returned, setCode: request.identity.displaySetCode)
        guard request.identity.matches(.legacy(card)) else { throw PriceQuoteError.identityMismatch }
        return CardPricing.price(for: card, variant: request.variant,
            magicTreatments: card.magicTreatments(for: request.variant),
            pokemonPrintRun: request.pokemonPrintRun, at: .now)
    }

    static func failureKind(for error: Error) -> TCGdexCircuitBreaker.Failure {
        if case TCGdexError.badResponse = error { return .serverError }
        return .unreachable
    }

    static func shouldRecordCircuitFailure(for error: Error) -> Bool {
        if error is CancellationError { return false }
        if let urlError = error as? URLError, urlError.code == .cancelled { return false }
        if let error = error as? TCGdexError {
            switch error {
            case .cardNotFound, .identityMismatch, .invalidURL: return false
            case .badResponse: return true
            }
        }
        return true
    }
}
