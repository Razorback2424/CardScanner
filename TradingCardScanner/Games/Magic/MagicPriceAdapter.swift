import Foundation

struct MagicPriceAdapter: GamePriceAdapter {
    let game = CardGame.magic
    private let scryfall = ScryfallService()

    func refresh(_ request: GamePriceRequest) async throws -> PriceLookup {
        guard request.identity.game == game else { throw PriceQuoteError.identityMismatch }
        if let override = request.catalogRefreshOverride { return try await override() }
        let returned = try await scryfall.fetchCard(id: request.identity.printingID, ignoringCache: true)
        let refreshed = IdentifiedCard.magic(returned)
        guard request.identity.matches(.legacy(refreshed)) else { throw PriceQuoteError.identityMismatch }
        return CardPricing.price(for: refreshed, variant: request.variant,
                                 magicTreatments: refreshed.magicTreatments(for: request.variant),
                                 pokemonPrintRun: nil, at: .now)
    }
}
