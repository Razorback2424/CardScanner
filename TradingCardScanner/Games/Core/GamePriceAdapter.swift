import Foundation

/// Exact catalog identity supplied after physical-printing resolution.
struct GamePriceIdentity: Equatable, Sendable {
    let game: CardGame
    let printingID: String
    let setID: String
    let displaySetCode: String
    let cardNumber: String
    let language: String

    func matches(_ other: Self) -> Bool {
        game == other.game && printingID == other.printingID
            && setID.caseInsensitiveCompare(other.setID) == .orderedSame
            && cardNumber.caseInsensitiveCompare(other.cardNumber) == .orderedSame
            && language.caseInsensitiveCompare(other.language) == .orderedSame
    }

    /// Temporary bridge while the legacy resolved-card model is extracted.
    static func legacy(_ card: IdentifiedCard) -> Self {
        return .init(game: card.game, printingID: card.providerID,
                     setID: card.variantEvidence.setID, displaySetCode: card.setCode,
                     cardNumber: card.cardNumber, language: card.language)
    }
}

struct GamePriceRequest: Sendable {
    let identity: GamePriceIdentity
    let variant: PhysicalVariant?
    let pokemonPrintRun: PokemonPrintRun?
    let catalogRefreshOverride: (@Sendable () async throws -> PriceLookup)?
}

protocol GamePriceAdapter: Sendable {
    var game: CardGame { get }
    var allowsProviderFallback: Bool { get }
    var supportsStoredPrintingRefresh: Bool { get }
    func refresh(_ request: GamePriceRequest) async throws -> PriceLookup
    func refreshStoredPrinting(_ printingID: String, variant: PhysicalVariant?) async throws -> PriceLookup
}

extension GamePriceAdapter {
    var allowsProviderFallback: Bool { true }
    var supportsStoredPrintingRefresh: Bool { false }
    func refreshStoredPrinting(_ printingID: String, variant: PhysicalVariant?) async throws -> PriceLookup {
        throw PriceQuoteError.pricingUnsupported
    }
}

struct GamePriceAdapterRegistry: Sendable {
    enum RegistrationError: Error, Equatable { case duplicateGame(CardGame) }
    private let adapters: [CardGame: any GamePriceAdapter]

    init(adapters: [any GamePriceAdapter]) throws {
        var values: [CardGame: any GamePriceAdapter] = [:]
        for adapter in adapters {
            guard values[adapter.game] == nil else {
                throw RegistrationError.duplicateGame(adapter.game)
            }
            values[adapter.game] = adapter
        }
        self.adapters = values
    }

    func adapter(for game: CardGame) -> (any GamePriceAdapter)? { adapters[game] }
}

/// Pricing also crosses the shared publication boundary before and after I/O.
struct ActivatedGamePriceAdapter: GamePriceAdapter {
    let adapter: any GamePriceAdapter
    let source: any GameCatalogActivationSource
    var game: CardGame { adapter.game }
    var allowsProviderFallback: Bool { adapter.allowsProviderFallback }
    var supportsStoredPrintingRefresh: Bool { adapter.supportsStoredPrintingRefresh }
    private func validate(_ quote: PriceLookup, printingID: String, variant: PhysicalVariant?) async throws {
        guard let snapshot = await source.currentSnapshot() else { throw PriceQuoteError.providerUnavailable }
        if case let .price(price) = quote, let authority = snapshot.priceAuthority,
           authority.managedSources.contains(price.source) {
            let key = PriceRecord.key(game: game, printingID: printingID, variantID: variant?.id)
            guard let expected = authority.identityByPriceKey[key], price.catalogIdentity == expected else {
                throw PriceQuoteError.identityMismatch
            }
        }
    }
    func refresh(_ request: GamePriceRequest) async throws -> PriceLookup {
        guard await source.currentSnapshot() != nil else { throw PriceQuoteError.providerUnavailable }
        let quote = try await adapter.refresh(request)
        try await validate(quote, printingID: request.identity.printingID, variant: request.variant)
        return quote
    }
    func refreshStoredPrinting(_ printingID: String, variant: PhysicalVariant?) async throws -> PriceLookup {
        guard await source.currentSnapshot() != nil else { throw PriceQuoteError.providerUnavailable }
        let quote = try await adapter.refreshStoredPrinting(printingID, variant: variant)
        try await validate(quote, printingID: printingID, variant: variant)
        return quote
    }
}
