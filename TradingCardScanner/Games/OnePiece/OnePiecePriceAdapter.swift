import Foundation
import OnePieceCatalogCore

protocol OnePieceMarketPriceSource: Sendable {
    func quote(mapping: OnePieceMarketMapping, number: String, generation: String?, minimumFetchedAt: Date?) async throws -> PriceLookup
}

/// Product-level USD market observations. No condition-specific SKU is claimed.
actor OnePieceTCGCSVPriceSource: OnePieceMarketPriceSource {
    static let shared = OnePieceTCGCSVPriceSource()
    private struct Response<Row: Decodable>: Decodable {
        let success: Bool
        let errors: [String]
        let results: [Row]
        let totalItems: Int?
    }
    private struct Product: Codable, Sendable {
        struct Field: Codable, Sendable { let name: String; let value: String }
        let productId: Int; let categoryId: Int; let groupId: Int
        let name: String; let extendedData: [Field]
    }
    private struct Price: Codable, Sendable {
        let productId: Int; let subTypeName: String; let marketPrice: Double?
    }
    private struct Snapshot: Codable, Sendable {
        let products: [Product]; let prices: [Price]; let fetchedAt: Date
        var catalogGeneration: String? = nil
    }
    private let session: URLSession
    private let cacheDirectory: URL
    private struct CacheKey: Hashable {
        let group: Int
        let generation: String?
        let minimumFetchedAt: Date?
    }
    private var snapshots: [Int: Snapshot] = [:]
    private var pending: [CacheKey: Task<Snapshot, Error>] = [:]
    private var failures: [CacheKey: Date] = [:]
    private var nextRequestAt = Date.distantPast
    init(session: URLSession = .shared,
         cacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OnePieceTCGCSV-v2")) {
        self.session = session; self.cacheDirectory = cacheDirectory
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
        let snapshot = try await snapshot(group: group, generation: generation, minimumFetchedAt: minimumFetchedAt)
        try Task.checkCancellation()
        let products = snapshot.products.filter { $0.productId == productID }
        guard products.count == 1, let product = products.first,
              product.categoryId == 68, product.groupId == group, product.name == name,
              product.extendedData.filter({ $0.name == "Number" }).map(\.value) == [number] else {
            throw PriceQuoteError.identityMismatch
        }
        let rows = snapshot.prices.filter { $0.productId == productID && $0.subTypeName == lane }
        guard rows.count <= 1 else { throw PriceQuoteError.identityMismatch }
        guard let amount = rows.first?.marketPrice else { return .unavailable(.tcgCSV) }
        guard amount.isFinite, amount >= 0 else { throw PriceQuoteError.providerUnavailable }
        return .price(.init(unitMarketPriceUSD: amount, currencyCode: "USD", source: .tcgCSV,
            sourceVariantID: "tcgplayer:\(productID):\(lane)", sourceUpdatedAt: nil, fetchedAt: snapshot.fetchedAt))
    }

    private func snapshot(group: Int, generation: String?, minimumFetchedAt: Date?) async throws -> Snapshot {
        // A withdrawal starts a new request cohort. It must not join a fetch
        // that began before its watermark, even within the same generation.
        let key = CacheKey(group: group, generation: generation, minimumFetchedAt: minimumFetchedAt)
        let file = cacheDirectory.appendingPathComponent("\(group).json")
        if snapshots[group]?.catalogGeneration != generation || snapshots[group] == nil,
           let bytes = try? Data(contentsOf: file), bytes.count <= 16 * 1_024 * 1_024,
           let value = try? JSONDecoder().decode(Snapshot.self, from: bytes), value.catalogGeneration == generation {
            snapshots[group] = value
        }
        if let cached = snapshots[group], cached.catalogGeneration == generation,
           minimumFetchedAt.map({ cached.fetchedAt > $0 }) ?? true,
           Date.now.timeIntervalSince(cached.fetchedAt) >= 0,
           Date.now.timeIntervalSince(cached.fetchedAt) < 86_400 { return cached }
        if let task = pending[key] {
            let result = try await task.value
            if minimumFetchedAt.map({ result.fetchedAt > $0 }) ?? true { return result }
            throw PriceQuoteError.providerUnavailable
        }
        if let failure = failures[key], Date.now.timeIntervalSince(failure) < 900 {
            throw PriceQuoteError.providerUnavailable
        }
        let task = Task {
            let fetchedAt = Date.now
            let products = try JSONDecoder().decode(Response<Product>.self,
                from: await self.fetch(group: group, resource: "products"))
            let prices = try JSONDecoder().decode(Response<Price>.self,
                from: await self.fetch(group: group, resource: "prices"))
            guard products.success, products.errors.isEmpty, prices.success, prices.errors.isEmpty,
                  products.totalItems.map({ $0 == products.results.count }) ?? true,
                  prices.totalItems.map({ $0 == prices.results.count }) ?? true else {
                throw PriceQuoteError.providerUnavailable
            }
            return Snapshot(products: products.results, prices: prices.results, fetchedAt: fetchedAt,
                catalogGeneration: generation)
        }
        pending[key] = task
        defer { pending[key] = nil }
        let value: Snapshot
        do { value = try await task.value; failures[key] = nil }
        catch { if !(error is CancellationError) { failures[key] = .now }; throw error }
        guard minimumFetchedAt.map({ value.fetchedAt > $0 }) ?? true else {
            throw PriceQuoteError.providerUnavailable
        }
        // A slower, older request must not replace a newer cached observation.
        if snapshots[group].map({ value.fetchedAt >= $0.fetchedAt }) ?? true {
            snapshots[group] = value
        }
        if snapshots[group]?.fetchedAt == value.fetchedAt, let bytes = try? JSONEncoder().encode(value) {
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try? bytes.write(to: file, options: .atomic)
        }
        return value
    }

    private func fetch(group: Int, resource: String) async throws -> Data {
        let start = max(nextRequestAt, .now)
        nextRequestAt = start.addingTimeInterval(0.1)
        if start.timeIntervalSinceNow > 0 { try await Task.sleep(for: .seconds(start.timeIntervalSinceNow)) }
        var request = URLRequest(url: URL(string: "https://tcgcsv.com/tcgplayer/68/\(group)/\(resource)")!)
        request.timeoutInterval = 15
        request.setValue("ScanStash/1.0 (iOS; daily One Piece market pricing)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 8 * 1_024 * 1_024 else { throw PriceQuoteError.providerUnavailable }
        return data
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
