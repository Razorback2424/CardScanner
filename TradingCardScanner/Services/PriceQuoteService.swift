import Foundation

enum PriceQuoteError: Error {
    case identityMismatch
    case providerUnavailable
    /// Capability absence is terminal: callers must not try another provider.
    case pricingUnsupported
}

/// Dispatches exact physical identity to a registered game pricing adapter.
struct PriceQuoteService: Sendable {
    private let registry: CardGameRegistry
    private let adapters: GamePriceAdapterRegistry
    private let catalogRefreshOverride: (@Sendable (IdentifiedCard, PhysicalVariant?, PokemonPrintRun?) async throws -> PriceLookup)?

    init(
        tcgCSVSource: any PokemonTCGCSVPriceSource = PokemonTCGCSVPriceService.shared,
        catalogRefreshOverride: (@Sendable (IdentifiedCard, PhysicalVariant?, PokemonPrintRun?) async throws -> PriceLookup)? = nil
    ) {
        registry = .standard
        adapters = try! GamePriceAdapterRegistry(adapters: [PokemonPriceAdapter(tcgCSVSource: tcgCSVSource), MagicPriceAdapter()])
        self.catalogRefreshOverride = catalogRefreshOverride
    }

    init(registry: CardGameRegistry, adapters: GamePriceAdapterRegistry) {
        self.registry = registry
        self.adapters = adapters
        catalogRefreshOverride = nil
    }

    func supportsPricing(for game: CardGame) -> Bool {
        registry.supports(game, .pricing) && adapters.adapter(for: game) != nil
    }

    func supportsGradedPricing(for game: CardGame) -> Bool {
        supportsPricing(for: game) && registry.supports(game, .gradedPricing)
    }

    func supportsSealedPricing(for game: CardGame) -> Bool {
        registry.supports(game, [.sealed, .pricing])
    }

    func allowsProviderFallback(for game: CardGame) -> Bool {
        adapters.adapter(for: game)?.allowsProviderFallback == true
    }

    func supportsStoredPrintingRefresh(for game: CardGame) -> Bool {
        supportsPricing(for: game) && adapters.adapter(for: game)?.supportsStoredPrintingRefresh == true
    }

    func refreshStoredPrinting(game: CardGame, printingID: String, variant: PhysicalVariant?) async throws -> PriceLookup {
        guard supportsStoredPrintingRefresh(for: game), let adapter = adapters.adapter(for: game) else {
            throw PriceQuoteError.pricingUnsupported
        }
        return try await adapter.refreshStoredPrinting(printingID, variant: variant)
    }

    func refresh(card: IdentifiedCard, variant: PhysicalVariant?,
                 pokemonPrintRun: PokemonPrintRun?) async throws -> PriceLookup {
        let override: (@Sendable () async throws -> PriceLookup)?
        if let catalogRefreshOverride {
            override = { try await catalogRefreshOverride(card, variant, pokemonPrintRun) }
        } else { override = nil }
        return try await refresh(.init(identity: .legacy(card), variant: variant,
                                       pokemonPrintRun: pokemonPrintRun,
                                       catalogRefreshOverride: override))
    }

    func refresh(_ request: GamePriceRequest) async throws -> PriceLookup {
        guard supportsPricing(for: request.identity.game),
              let adapter = adapters.adapter(for: request.identity.game) else {
            throw PriceQuoteError.pricingUnsupported
        }
        return try await adapter.refresh(request)
    }

    static func failureKind(for error: Error) -> TCGdexCircuitBreaker.Failure {
        PokemonPriceAdapter.failureKind(for: error)
    }

    static func shouldRecordCircuitFailure(for error: Error) -> Bool {
        PokemonPriceAdapter.shouldRecordCircuitFailure(for: error)
    }

    static func matchesResolvedIdentity(returned: IdentifiedCard, resolved: IdentifiedCard) -> Bool {
        GamePriceIdentity.legacy(resolved).matches(.legacy(returned))
    }
}
