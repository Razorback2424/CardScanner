import Foundation
import SwiftData

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
    var minimumFetchedAt: Date? = nil
}

protocol GamePriceAdapter: Sendable {
    var game: CardGame { get }
    var allowsProviderFallback: Bool { get }
    var supportsStoredPrintingRefresh: Bool { get }
    func refresh(_ request: GamePriceRequest) async throws -> PriceLookup
    func refreshStoredPrinting(_ printingID: String, variant: PhysicalVariant?) async throws -> PriceLookup
    func refreshStoredPrinting(_ printingID: String, variant: PhysicalVariant?, minimumFetchedAt: Date?) async throws -> PriceLookup
}

extension GamePriceAdapter {
    var allowsProviderFallback: Bool { true }
    var supportsStoredPrintingRefresh: Bool { false }
    func refreshStoredPrinting(_ printingID: String, variant: PhysicalVariant?) async throws -> PriceLookup {
        throw PriceQuoteError.pricingUnsupported
    }
    func refreshStoredPrinting(_ printingID: String, variant: PhysicalVariant?, minimumFetchedAt: Date?) async throws -> PriceLookup {
        try await refreshStoredPrinting(printingID, variant: variant)
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
    let source: (any GameCatalogActivationSource)?
    let container: ModelContainer
    var game: CardGame { adapter.game }
    var allowsProviderFallback: Bool { adapter.allowsProviderFallback }
    var supportsStoredPrintingRefresh: Bool { adapter.supportsStoredPrintingRefresh }
    private func validate(_ quote: PriceLookup, printingID: String, variant: PhysicalVariant?) async throws {
        guard let source else { return }
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
        if let source, await source.currentSnapshot() == nil { throw PriceQuoteError.providerUnavailable }
        var request = request
        let minimum = try await minimumFetchedAt(printingID: request.identity.printingID, variant: request.variant)
        request.minimumFetchedAt = [minimum, request.minimumFetchedAt].compactMap { $0 }.max()
        let quote = try await adapter.refresh(request)
        try await validate(quote, printingID: request.identity.printingID, variant: request.variant)
        return quote
    }
    func refreshStoredPrinting(_ printingID: String, variant: PhysicalVariant?) async throws -> PriceLookup {
        if let source, await source.currentSnapshot() == nil { throw PriceQuoteError.providerUnavailable }
        let minimum = try await minimumFetchedAt(printingID: printingID, variant: variant)
        let quote = try await adapter.refreshStoredPrinting(printingID, variant: variant, minimumFetchedAt: minimum)
        try await validate(quote, printingID: printingID, variant: variant)
        return quote
    }

    private func minimumFetchedAt(printingID: String, variant: PhysicalVariant?) async throws -> Date? {
        let key = PriceRecord.key(game: game, printingID: printingID, variantID: variant?.id)
        // A fresh context observes withdrawals made after binding. Only the
        // scalar watermark crosses executors; collection refresh never fetches
        // SwiftData models on the UI thread for each quote.
        let value = try await Task.detached(priority: .utility) { [container] in
            let context = ModelContext(container)
            let records = try context.fetch(FetchDescriptor<PriceRecord>(predicate: #Predicate { $0.key == key }))
            return records.compactMap(\.invalidatedAt).max()
        }.value
        try Task.checkCancellation()
        return value
    }
}
