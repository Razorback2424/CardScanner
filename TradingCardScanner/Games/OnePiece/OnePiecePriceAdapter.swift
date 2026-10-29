import Foundation
import OnePieceCatalogCore

protocol OnePieceMarketPriceSource: Sendable {
    func quote(mapping: OnePieceMarketMapping, number: String, generation: String?, minimumFetchedAt: Date?) async throws -> PriceLookup
}

/// One Piece owns mapping validation; the bounded feed transport is shared.
actor OnePieceTCGCSVPriceSource: OnePieceMarketPriceSource {
    static let shared = OnePieceTCGCSVPriceSource(transport: .shared)
    private let transport: TCGCSVProductPriceSource
    private init(transport: TCGCSVProductPriceSource) { self.transport = transport }
    init(baseURL: URL? = TCGCSVPriceMirror.baseURL,
         session: URLSession = TCGCSVPriceMirror.session,
         cacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OnePieceTCGCSV-v2")) {
        transport = TCGCSVProductPriceSource(baseURL: baseURL, session: session, cacheDirectory: cacheDirectory)
    }
    func quote(mapping: OnePieceMarketMapping, number: String, generation: String? = nil,
               minimumFetchedAt: Date? = nil) async throws -> PriceLookup {
        guard mapping.provider == "tcgplayer", mapping.market == "us", mapping.currency == "USD",
              mapping.condition == "aggregate", mapping.status == .exact,
              let group = mapping.qualifiers["groupID"].flatMap(Int.init), group > 0,
              let productID = Int(mapping.productID), productID > 0,
              let name = mapping.qualifiers["productName"],
              let lane = mapping.providerVariantID, ["Normal", "Foil"].contains(lane),
              ["normal": "Normal", "foil": "Foil"][mapping.variantID] == lane,
              mapping.qualifiers["finish"] == lane else { throw PriceQuoteError.identityMismatch }
        return try await transport.quote(category: 68, group: group, productID: productID,
            name: name, number: number, lane: lane, generation: generation, minimumFetchedAt: minimumFetchedAt)
    }
}

struct OnePiecePriceAdapter: GamePriceAdapter {
    let game = CardGame.onePiece
    let registry: OnePieceCatalogRegistry
    var coordinator: OnePieceCatalogCoordinator? = nil
    var source: any OnePieceMarketPriceSource = OnePieceTCGCSVPriceSource.shared
    var allowsProviderFallback: Bool { false }
    var supportsStoredPrintingRefresh: Bool { true }

    static func mappingIdentity(_ mapping: OnePieceMarketMapping) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return OnePieceSourceObservation.sha256(try! encoder.encode(mapping))
    }

    static func priceAuthority(_ registry: OnePieceCatalogRegistry) -> GameCatalogPriceAuthority {
        var identities: [String: String] = [:]
        for printing in registry.printingByID.values where printing.status == .verified && printing.language == "en" {
            let mappings = printing.marketMappings.filter {
                $0.status == .exact && $0.provider == "tcgplayer" && $0.market == "us"
                    && $0.currency == "USD" && $0.condition == "aggregate"
            }
            for (variant, rows) in Dictionary(grouping: mappings, by: \.variantID) where rows.count == 1 {
                identities[PriceRecord.key(game: .onePiece, printingID: printing.id.uuidString.lowercased(), variantID: variant)]
                    = mappingIdentity(rows[0])
            }
        }
        return .init(game: .onePiece, managedSources: [.tcgCSV], identityByPriceKey: identities)
    }

    private func currentRegistry() async -> OnePieceCatalogRegistry {
        guard let coordinator else { return registry }
        await coordinator.loadPersistedOrBundled()
        return await coordinator.registry ?? registry
    }

    func refreshStoredPrinting(_ printingID: String, variant: PhysicalVariant?) async throws -> PriceLookup {
        try await refreshStoredPrinting(printingID, variant: variant, minimumFetchedAt: nil)
    }

    func refreshStoredPrinting(_ printingID: String, variant: PhysicalVariant?, minimumFetchedAt: Date?) async throws -> PriceLookup {
        let current = await currentRegistry()
        guard let id = UUID(uuidString: printingID), printingID == id.uuidString.lowercased() else {
            throw PriceQuoteError.identityMismatch
        }
        let card = try OnePieceCatalogAdapter(registry: current).resolution(forPrintingID: id).card
        return try await refresh(.init(identity: .legacy(card), variant: variant,
            pokemonPrintRun: nil, catalogRefreshOverride: nil, minimumFetchedAt: minimumFetchedAt))
    }

    func refresh(_ request: GamePriceRequest) async throws -> PriceLookup {
        let current = await currentRegistry()
        guard request.identity.game == game, request.pokemonPrintRun == nil,
              let id = UUID(uuidString: request.identity.printingID),
              request.identity.printingID == id.uuidString.lowercased(),
              let printing = current.printingByID[id], printing.status == .verified,
              let canonical = current.canonicalByID[printing.canonicalCardID] else {
            throw PriceQuoteError.identityMismatch
        }
        let card = try OnePieceCatalogAdapter(registry: current).resolution(forPrintingID: id).card
        guard request.identity.matches(.legacy(card)), let variant = request.variant,
              printing.supportedVariantIDs.contains(variant.id) else { throw PriceQuoteError.identityMismatch }
        let mappings = printing.marketMappings.filter {
            $0.status == .exact && $0.provider == "tcgplayer" && $0.variantID == variant.id
                && $0.market == "us" && $0.currency == "USD" && $0.condition == "aggregate"
        }
        guard mappings.count <= 1 else { throw PriceQuoteError.identityMismatch }
        guard let mapping = mappings.first else { return .unavailable(nil) }
        let quote = try await source.quote(mapping: mapping, number: canonical.printedNumber,
            generation: current.generation, minimumFetchedAt: request.minimumFetchedAt)
        // A mapping withdrawn while HTTP was in flight must not publish an old quote.
        let latest = await currentRegistry()
        guard latest.printingByID[id]?.status == .verified,
              latest.printingByID[id]?.marketMappings.contains(mapping) == true else {
            throw PriceQuoteError.identityMismatch
        }
        if case var .price(price) = quote {
            price.catalogIdentity = Self.mappingIdentity(mapping)
            return .price(price)
        }
        return quote
    }
}
