import CryptoKit
import Foundation

protocol LorcanaMarketPriceSource: Sendable {
    func quote(mapping: LorcanaMarketMapping, generation: String, minimumFetchedAt: Date?) async throws -> PriceLookup
}

struct LorcanaTCGCSVPriceSource: LorcanaMarketPriceSource {
    var transport: TCGCSVProductPriceSource = .shared
    func quote(mapping: LorcanaMarketMapping, generation: String, minimumFetchedAt: Date?) async throws -> PriceLookup {
        guard mapping.hasValidMarketLane else {
            throw PriceQuoteError.identityMismatch
        }
        return try await transport.quote(category: 71, group: mapping.groupID, productID: mapping.productID,
            name: mapping.productName, number: mapping.productNumber, lane: mapping.providerVariantID,
            generation: generation, minimumFetchedAt: minimumFetchedAt)
    }
}

/// Quotes require an exact reviewed physical UUID and an explicitly selected finish.
struct LorcanaPriceAdapter: GamePriceAdapter {
    let game = CardGame.lorcana
    let registry: LorcanaCatalogRegistry
    var coordinator: LorcanaCatalogCoordinator? = nil
    var source: any LorcanaMarketPriceSource = LorcanaTCGCSVPriceSource()
    var allowsProviderFallback: Bool { false }
    var supportsStoredPrintingRefresh: Bool { true }

    static func mappingIdentity(_ mapping: LorcanaMarketMapping) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return SHA256.hash(data: try! encoder.encode(mapping.normalized)).map { String(format: "%02x", $0) }.joined()
    }

    static func priceAuthority(_ registry: LorcanaCatalogRegistry) -> GameCatalogPriceAuthority {
        var identities: [String: String] = [:]
        for printing in registry.physicalCatalog.map({ Array($0.printingByID.values) }) ?? [] {
            guard (try? LorcanaCatalogAdapter(registry: registry).resolution(forPrintingID: printing.id)) != nil else { continue }
            for mapping in printing.marketMappings ?? [] {
                identities[PriceRecord.key(game: .lorcana, printingID: printing.id.uuidString.lowercased(),
                    variantID: mapping.finish.rawValue)] = mappingIdentity(mapping)
            }
        }
        return .init(game: .lorcana, managedSources: [.tcgCSV], identityByPriceKey: identities)
    }

    private func currentRegistry() async throws -> LorcanaCatalogRegistry {
        guard let coordinator else { return registry }
        guard let snapshot = await coordinator.currentSnapshot(),
              let catalog = snapshot.catalog as? LorcanaCatalogAdapter else { throw PriceQuoteError.providerUnavailable }
        return catalog.registry
    }

    func refreshStoredPrinting(_ printingID: String, variant: PhysicalVariant?) async throws -> PriceLookup {
        try await refreshStoredPrinting(printingID, variant: variant, minimumFetchedAt: nil)
    }

    func refreshStoredPrinting(_ printingID: String, variant: PhysicalVariant?, minimumFetchedAt: Date?) async throws -> PriceLookup {
        let current = try await currentRegistry()
        let card = try exactCard(printingID, registry: current)
        return try await refresh(.init(identity: .legacy(card), variant: variant,
            pokemonPrintRun: nil, catalogRefreshOverride: nil, minimumFetchedAt: minimumFetchedAt))
    }

    private func exactCard(_ printingID: String, registry: LorcanaCatalogRegistry) throws -> ResolvedCatalogCard {
        guard let id = UUID(uuidString: printingID), id.uuidString.lowercased() == printingID,
              let card = try? LorcanaCatalogAdapter(registry: registry).resolution(forPrintingID: id).card else {
            throw PriceQuoteError.identityMismatch
        }
        return card
    }

    func refresh(_ request: GamePriceRequest) async throws -> PriceLookup {
        guard request.identity.game == game, request.pokemonPrintRun == nil else { throw PriceQuoteError.identityMismatch }
        let current = try await currentRegistry()
        let card = try exactCard(request.identity.printingID, registry: current)
        guard request.identity.matches(.legacy(card)), let variant = request.variant,
              card.variantEvidence.catalogVariants.contains(where: { $0.id == variant.id }),
              let id = UUID(uuidString: card.physicalPrintingID) else { throw PriceQuoteError.identityMismatch }
        let mappings = current.physicalCatalog?.printingByID[id]?.marketMappings ?? []
        guard let mapping = mappings.first(where: { $0.finish.rawValue == variant.id }) else { return .unavailable(nil) }
        let quote = try await source.quote(mapping: mapping, generation: current.generation,
            minimumFetchedAt: request.minimumFetchedAt)
        try Task.checkCancellation()
        // Validate the entire current physical resolution as well as the lane:
        // a family may have become incomplete/conflicted while HTTP was in flight.
        let latest = try await currentRegistry()
        let latestCard = try exactCard(card.physicalPrintingID, registry: latest)
        guard request.identity.matches(.legacy(latestCard)),
              latest.physicalCatalog?.printingByID[id]?.marketMappings?.contains(mapping) == true else {
            throw PriceQuoteError.identityMismatch
        }
        if case var .price(price) = quote {
            guard price.source == .tcgCSV, price.currencyCode == "USD",
                  price.unitMarketPriceUSD.isFinite, price.unitMarketPriceUSD >= 0,
                  request.minimumFetchedAt.map({ price.fetchedAt > $0 }) ?? true else { throw PriceQuoteError.providerUnavailable }
            price.catalogIdentity = Self.mappingIdentity(mapping)
            return .price(price)
        }
        return quote
    }
}
