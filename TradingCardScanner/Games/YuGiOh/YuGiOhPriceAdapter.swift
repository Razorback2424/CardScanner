import Foundation

protocol YuGiOhMarketPriceSource: Sendable {
    func quote(printing: YuGiOhCatalog.Printing, edition: YuGiOhEdition, generation: String, minimumFetchedAt: Date?) async throws -> PriceLookup
}
struct YuGiOhTCGCSVPriceSource: YuGiOhMarketPriceSource {
    var transport: TCGCSVProductPriceSource = .shared
    func quote(printing p: YuGiOhCatalog.Printing, edition: YuGiOhEdition, generation: String, minimumFetchedAt: Date?) async throws -> PriceLookup {
        try await transport.quote(category: 2, group: p.set.groupID, productID: p.productID, name: p.productName,
            number: p.code, lane: edition.tcgplayerSubtype, generation: generation, minimumFetchedAt: minimumFetchedAt)
    }
}
struct YuGiOhPriceAdapter: GamePriceAdapter {
    let catalog: YuGiOhCatalog
    var source: any YuGiOhMarketPriceSource = YuGiOhTCGCSVPriceSource()
    var game: CardGame { .yuGiOh }
    var allowsProviderFallback: Bool { false }
    var supportsStoredPrintingRefresh: Bool { true }
    static func mappingIdentity(_ p: YuGiOhCatalog.Printing, _ edition: YuGiOhEdition) -> String {
        "tcgcsv:2:\(p.set.groupID):\(p.productID):\(edition.tcgplayerSubtype)"
    }
    static func priceAuthority(_ catalog: YuGiOhCatalog) -> GameCatalogPriceAuthority {
        var identities: [String: String] = [:]
        let adapter = YuGiOhCatalogAdapter(catalog: catalog)
        for p in catalog.printingByID.values where (try? adapter.resolution(forPrintingID: p.id)) != nil {
            for edition in p.editions {
                identities[PriceRecord.key(game: .yuGiOh, printingID: p.idString, variantID: edition.rawValue)] = mappingIdentity(p, edition)
            }
        }
        return .init(game: .yuGiOh, managedSources: [.tcgCSV], identityByPriceKey: identities)
    }
    func refreshStoredPrinting(_ printingID: String, variant: PhysicalVariant?) async throws -> PriceLookup {
        try await refreshStoredPrinting(printingID, variant: variant, minimumFetchedAt: nil)
    }
    func refreshStoredPrinting(_ printingID: String, variant: PhysicalVariant?, minimumFetchedAt: Date?) async throws -> PriceLookup {
        let card = try exactCard(printingID)
        return try await refresh(.init(identity: .legacy(card), variant: variant, pokemonPrintRun: nil,
            catalogRefreshOverride: nil, minimumFetchedAt: minimumFetchedAt))
    }
    private func exactCard(_ id: String) throws -> ResolvedCatalogCard {
        guard let uuid = UUID(uuidString: id), uuid.uuidString.lowercased() == id,
              let card = try? YuGiOhCatalogAdapter(catalog: catalog).resolution(forPrintingID: uuid).card else { throw PriceQuoteError.identityMismatch }
        return card
    }
    func refresh(_ request: GamePriceRequest) async throws -> PriceLookup {
        guard request.identity.game == game, request.pokemonPrintRun == nil else { throw PriceQuoteError.identityMismatch }
        let card = try exactCard(request.identity.printingID)
        guard request.identity.matches(.legacy(card)), let variant = request.variant,
              let edition = YuGiOhEdition(rawValue: variant.id), let id = UUID(uuidString: card.physicalPrintingID),
              let p = catalog.printingByID[id], p.editions.contains(edition) else { throw PriceQuoteError.identityMismatch }
        // pe is build evidence only. Valid physical mappings always reach the
        // existing transport, so a newly available quote is discoverable.
        let quote = try await source.quote(printing: p, edition: edition, generation: catalog.generation, minimumFetchedAt: request.minimumFetchedAt)
        try Task.checkCancellation()
        if case var .price(price) = quote {
            guard price.source == .tcgCSV, price.currencyCode == "USD", price.unitMarketPriceUSD.isFinite,
                  price.unitMarketPriceUSD >= 0, request.minimumFetchedAt.map({ price.fetchedAt > $0 }) ?? true else { throw PriceQuoteError.providerUnavailable }
            price.catalogIdentity = Self.mappingIdentity(p, edition)
            return .price(price)
        }
        return quote
    }
}
