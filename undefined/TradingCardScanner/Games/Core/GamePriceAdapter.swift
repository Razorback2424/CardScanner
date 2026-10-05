import Foundation

/// Exact physical catalog identity, never OCR evidence. For app-owned printing
/// IDs, a game's adapter must use its reviewed registry mappings.
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

    /// Legacy catalog projection only. New catalog adapters construct the
    /// generic identity directly after physical resolution.
    static func legacy(_ card: IdentifiedCard) -> Self {
        let language: String
        if case let .magic(magic) = card { language = magic.language }
        else { language = CatalogIdentityNormalization.locale(forCatalogCardID: card.providerID).rawValue }
        return .init(game: card.game, printingID: card.providerID,
                     setID: card.variantEvidence.setID, displaySetCode: card.setCode,
                     cardNumber: card.cardNumber, language: language)
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
    func refresh(_ request: GamePriceRequest) async throws -> PriceLookup
}

struct GamePriceAdapterRegistry: Sendable {
    enum RegistrationError: Error, Equatable { case duplicateGame(CardGame) }
    private let adapters: [CardGame: any GamePriceAdapter]

    init(adapters: [any GamePriceAdapter]) throws {
        var values: [CardGame: any GamePriceAdapter] = [:]
        for adapter in adapters {
            guard values[adapter.game] == nil else { throw RegistrationError.duplicateGame(adapter.game) }
            values[adapter.game] = adapter
        }
        self.adapters = values
    }

    func adapter(for game: CardGame) -> (any GamePriceAdapter)? { adapters[game] }
}
