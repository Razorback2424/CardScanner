import Foundation

enum PriceQuoteError: Error {
    case identityMismatch
}

/// Refreshes only a card that has already been resolved. It never receives OCR
/// evidence, so a refresh cannot silently re-identify the card in someone's hand.
struct PriceQuoteService {
    private let tcgdex = TCGdexService()
    private let scryfall = ScryfallService()

    func refresh(
        card: IdentifiedCard,
        variant: PhysicalVariant?,
        pokemonPrintRun: PokemonPrintRun?
    ) async throws -> PriceLookup {
        let refreshed: IdentifiedCard
        switch card {
        case .pokemon:
            let returned = try await tcgdex.fetchCard(id: card.providerID, ignoringCache: true)
            refreshed = .pokemon(returned, setCode: card.setCode)
        case .magic:
            let returned = try await scryfall.fetchCard(id: card.providerID, ignoringCache: true)
            refreshed = .magic(returned)
        }

        guard Self.matchesResolvedIdentity(returned: refreshed, resolved: card) else {
            throw PriceQuoteError.identityMismatch
        }
        return CardPricing.price(
            for: refreshed,
            variant: variant,
            pokemonPrintRun: pokemonPrintRun,
            at: .now
        )
    }

    /// A direct provider id is authoritative, but the redundant stable card
    /// fields make the contract explicit and protect against a malformed response.
    static func matchesResolvedIdentity(returned: IdentifiedCard, resolved: IdentifiedCard) -> Bool {
        guard returned.game == resolved.game,
              returned.providerID == resolved.providerID,
              returned.cardNumber.caseInsensitiveCompare(resolved.cardNumber) == .orderedSame else {
            return false
        }

        switch (returned, resolved) {
        case let (.pokemon(returned, _), .pokemon(resolved, _)):
            return returned.set.id.caseInsensitiveCompare(resolved.set.id) == .orderedSame
        case let (.magic(returned), .magic(resolved)):
            return returned.setCode.caseInsensitiveCompare(resolved.setCode) == .orderedSame
                && returned.language.caseInsensitiveCompare(resolved.language) == .orderedSame
        default:
            return false
        }
    }
}
