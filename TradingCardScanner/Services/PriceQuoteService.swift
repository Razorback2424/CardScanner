import Foundation

enum PriceQuoteError: Error {
    case identityMismatch
    case providerUnavailable
}

/// Refreshes only a card that has already been resolved. It never receives OCR
/// evidence, so a refresh cannot silently re-identify the card in someone's hand.
struct PriceQuoteService {
    private let tcgdex = TCGdexService()
    /// The same breaker the catalog uses. TCGdex being down is one fact about
    /// one host; discovering it twice costs a second connect timeout per scan.
    private let tcgdexCircuit = TCGdexCircuitBreaker.shared
    private let scryfall = ScryfallService()

    func refresh(
        card: IdentifiedCard,
        variant: PhysicalVariant?,
        pokemonPrintRun: PokemonPrintRun?
    ) async throws -> PriceLookup {
        let refreshed: IdentifiedCard
        switch card {
        case .pokemon:
            guard await tcgdexCircuit.permitsRequest() else {
                throw PriceQuoteError.providerUnavailable
            }
            let returned: TCGdexCard
            do {
                returned = try await tcgdex.fetchCard(
                    id: card.providerID,
                    locale: CatalogIdentityNormalization.locale(forCatalogCardID: card.providerID),
                    ignoringCache: true
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
                case .badResponse:
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
            case .badResponse:
                return true
            }
        }
        return true
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
