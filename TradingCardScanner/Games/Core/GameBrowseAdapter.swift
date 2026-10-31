import Foundation

protocol GameBrowseAdapter: Sendable {
    var game: CardGame { get }
    var generation: String { get }
    func sets() async throws -> [CatalogSet]
    func cards(in set: CatalogSet, cursor: String?) async throws -> CatalogPage<CatalogCardSummary>
    func search(query: String, setIDs: Set<CatalogSetID>, cursor: String?) async throws -> CatalogPage<CatalogCardSummary>
    func details(for summary: CatalogCardSummary) async throws -> CatalogCardDetails
}

struct GameBrowseAdapterRegistry: Sendable {
    enum RegistrationError: Error { case duplicateGame(CardGame) }
    private let adapters: [CardGame: any GameBrowseAdapter]
    init(adapters: [any GameBrowseAdapter]) throws {
        var values: [CardGame: any GameBrowseAdapter] = [:]
        for adapter in adapters {
            guard values[adapter.game] == nil else { throw RegistrationError.duplicateGame(adapter.game) }
            values[adapter.game] = adapter
        }
        self.adapters = values
    }
    func adapter(for game: CardGame) -> (any GameBrowseAdapter)? { adapters[game] }
    func replacing(_ adapter: any GameBrowseAdapter) -> Self {
        try! Self(adapters: adapters.values.filter { $0.game != adapter.game } + [adapter])
    }
}
