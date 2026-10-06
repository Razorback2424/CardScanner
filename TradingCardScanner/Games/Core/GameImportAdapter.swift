import Foundation

struct GameImportRequest: Hashable, Sendable {
    let sourceProviderID: String
    let catalogProviderID: String?
    let game: CardGame
    let name: String
    let setName: String
    let cardNumber: String
    let itemKind: CollectionItemKind

    var identityKey: String {
        Self.identityKey(game: game, providerID: sourceProviderID, catalogProviderID: catalogProviderID, itemKind: itemKind)
    }
    static func identityKey(game: CardGame, providerID: String, catalogProviderID: String?, itemKind: CollectionItemKind) -> String {
        [game.rawValue, itemKind.rawValue, providerID, catalogProviderID ?? ""]
            .map { "\($0.utf8.count):\($0)" }.joined()
    }
}

enum GameImportValidationError: LocalizedError {
    case unsupportedItemKind, invalidPrinting, contradictoryIdentity, missingFinish, unsupportedFinish, invalidOwnershipKey
    case missingAdapter
    var errorDescription: String? {
        switch self {
        case .missingAdapter: return "Importing this game requires an installed catalog adapter that validates its exact printing."
        case .unsupportedItemKind: return "This game currently supports importing raw cards only."
        case .invalidPrinting: return "This row does not identify an exact verified catalog printing."
        case .contradictoryIdentity: return "This row contains conflicting printing or card-number evidence."
        case .missingFinish: return "This row needs an explicit finish supported by its exact catalog printing."
        case .unsupportedFinish: return "This finish is not supported by the exact catalog printing."
        case .invalidOwnershipKey: return "This row's collection identity does not match its printing and finish."
        }
    }
}

protocol GameImportAdapter: Sendable {
    var game: CardGame { get }
    var generation: String? { get }
    func validate(_ entry: CollectionCSVEntry) throws
    func metadata(for requests: [GameImportRequest]) async -> [String: ImportedCatalogMetadata]
}

extension GameImportAdapter {
    var generation: String? { nil }
}

struct GameImportAdapterRegistry: Sendable {
    enum RegistrationError: Error { case duplicateGame(CardGame) }
    private let adapters: [CardGame: any GameImportAdapter]
    init(adapters: [any GameImportAdapter]) throws {
        var values: [CardGame: any GameImportAdapter] = [:]
        for adapter in adapters {
            guard values[adapter.game] == nil else { throw RegistrationError.duplicateGame(adapter.game) }
            values[adapter.game] = adapter
        }
        self.adapters = values
    }
    func adapter(for game: CardGame) -> (any GameImportAdapter)? { adapters[game] }
    func validate(_ entry: CollectionCSVEntry) throws {
        if let adapter = adapters[entry.game] {
            try adapter.validate(entry)
            return
        }
        // Only the two original modules retain the legacy CSV validation path.
        // A writable descriptor for a newer game does not prove printing identity.
        let legacyGames: Set<CardGame> = [PokemonGameRuntime.descriptor.game, MagicGameRuntime.descriptor.game]
        guard legacyGames.contains(entry.game) else { throw GameImportValidationError.missingAdapter }
    }
    func replacing(_ adapter: any GameImportAdapter) -> Self {
        try! Self(adapters: adapters.values.filter { $0.game != adapter.game } + [adapter])
    }
}
