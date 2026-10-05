import Foundation

struct MagicPriceAdapter: GamePriceAdapter {
    var game: CardGame { .magic }
    private let scryfall = ScryfallService()

    func refresh(_ request: GamePriceRequest) async throws -> PriceLookup {
        guard request.identity.game == game else { throw PriceQuoteError.identityMismatch }
        if let override = request.catalogRefreshOverride { return try await override() }
        let returned = try await scryfall.fetchCard(id: request.identity.printingID, ignoringCache: true)
        let card = IdentifiedCard.magic(returned)
        guard request.identity.matches(.legacy(card)) else { throw PriceQuoteError.identityMismatch }
        return CardPricing.price(for: card, variant: request.variant,
            magicTreatments: card.magicTreatments(for: request.variant),
            pokemonPrintRun: request.pokemonPrintRun, at: .now)
    }
}
