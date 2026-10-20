import Foundation

/// Market history is independent of ownership, local check days and portfolio
/// accounting. Each request identifies one physical listing, never a card name
/// alone. The provider currently exposes at most a trailing year of points.
struct CardMarketHistoryRequest: Hashable, Sendable {
    let game: CardGame
    let printingID: String
    let variantID: String?
    let itemKind: CollectionItemKind
    let marketVariantID: String?
    var lookups: [JustTCGBatchLookup]
    let name: String
    let setName: String
    let number: String
    let catalogID: String?
    let printRun: PokemonPrintRun?
    let treatments: [String]
    var exactProductID: String?
    var providerPrinting: String? = nil

    @MainActor
    init(card: CollectedCard) {
        let input = PriceFallbackCardInput(card: card, variant: card.variant, pokemonPrintRun: card.pokemonPrintRun)
        game = input.game
        printingID = input.printingID
        variantID = input.variant?.id
        itemKind = card.itemKind
        marketVariantID = card.justTCGVariantID
        lookups = input.lookupCandidates
        name = input.name
        setName = input.setName
        number = input.cardNumber
        catalogID = input.catalogID
        printRun = input.pokemonPrintRun
        treatments = input.treatmentIDs
        exactProductID = card.tcgplayerProductID
    }

    init(card: IdentifiedCard, variant: PhysicalVariant?, printRun: PokemonPrintRun?) {
        game = card.game
        printingID = PriceFallbackQuoteResolver.printingID(for: card, pokemonPrintRun: printRun)
        variantID = variant?.id
        itemKind = .rawCard
        marketVariantID = nil
        lookups = PriceFallbackQuoteResolver.directLookups(card: card, variant: variant, pokemonPrintRun: printRun)
        name = card.name
        setName = card.setName
        number = card.cardNumber
        catalogID = card.providerID
        self.printRun = printRun
        treatments = MagicTreatmentKeyCodec.storedIDs(from: card.magicTreatments(for: variant))
        exactProductID = CardPricing.tcgplayerProductID(for: card, variant: variant, printRun: printRun).map(String.init)
    }

    /// Newer game modules own their reviewed marketplace mappings. Resolve
    /// those from the active catalog, preserving physical UUID/finish identity.
    func resolvingMarketMapping(in runtimes: CardGameRuntimeContainer?) async -> Self {
        guard (game == .onePiece || game == .lorcana), marketVariantID == nil,
              let runtime = runtimes?.runtime(for: game),
              let id = UUID(uuidString: catalogID ?? printingID) else { return self }
        let snapshot = await runtime.activationSource?.currentSnapshot()
        let catalog = snapshot?.catalog ?? runtime.catalog
        var result = self
        if let catalog = catalog as? OnePieceCatalogAdapter,
           let printing = catalog.registry.printingByID[id], printing.status == .verified {
            let mappings = printing.marketMappings.filter {
                $0.status == .exact && $0.provider == "tcgplayer" && $0.market == "us"
                    && $0.currency == "USD" && $0.variantID == variantID
            }
            if mappings.count == 1 {
                result.exactProductID = mappings[0].productID
                result.providerPrinting = mappings[0].providerVariantID
            }
        } else if let catalog = catalog as? LorcanaCatalogAdapter,
                  (try? catalog.resolution(forPrintingID: id)) != nil {
            let mappings = (catalog.registry.physicalCatalog?.printingByID[id]?.marketMappings ?? []).filter {
                $0.hasValidMarketLane && $0.finish.rawValue == variantID
            }
            if mappings.count == 1 {
                result.exactProductID = String(mappings[0].productID)
                result.providerPrinting = mappings[0].providerVariantID
            }
        }
        if let productID = result.exactProductID { result.lookups = [.tcgplayerID(productID)] }
        return result
    }
}

actor CardMarketHistoryService {
    static let shared = CardMarketHistoryService()

    enum HistoryError: LocalizedError {
        case noListing
        case requestFailed
        var errorDescription: String? {
            switch self {
            case .noListing: return "JustTCG has no matching price history for this printing yet."
            case .requestFailed: return "JustTCG history could not be loaded. Try again."
            }
        }
    }

    private struct Cached: Codable {
        let requestData: Data
        let fetchedAt: Date
        let points: [JustTCGHistoryPoint]
    }

    private let transport: JustTCGTransport
    private let root: URL
    private var pending: [CardMarketHistoryRequest: Task<[JustTCGHistoryPoint], Error>] = [:]

    init(transport: JustTCGTransport = .shared, root: URL? = nil) {
        self.transport = transport
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CardMarketHistory", isDirectory: true)
    }

    /// The identity is encoded rather than relying on Swift's process-random hash.
    private func identityData(_ request: CardMarketHistoryRequest) -> Data {
        (try? JSONEncoder().encode([
            request.game.rawValue, request.printingID, request.variantID ?? "", request.itemKind.rawValue,
            request.itemKind == .gradedCard ? (request.marketVariantID ?? "") : "",
            request.printRun?.rawValue ?? "", request.treatments.sorted().joined(separator: "|")
        ])) ?? Data()
    }

    private func cacheURL(_ data: Data) -> URL {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return root.appendingPathComponent(String(hash, radix: 16) + ".json")
    }

    func cached(_ request: CardMarketHistoryRequest) -> [JustTCGHistoryPoint] {
        readCache(request)?.points ?? []
    }

    private func readCache(_ request: CardMarketHistoryRequest) -> Cached? {
        let identity = identityData(request)
        guard let data = try? Data(contentsOf: cacheURL(identity)),
              let cached = try? JSONDecoder().decode(Cached.self, from: data),
              cached.requestData == identity else { return nil }
        return cached
    }

    func history(for request: CardMarketHistoryRequest, now: Date = .now) async throws -> [JustTCGHistoryPoint] {
        let old = readCache(request)
        if let old, now.timeIntervalSince(old.fetchedAt) < 6 * 60 * 60 { return old.points }
        if let task = pending[request] { return try await task.value }
        let task = Task { try await self.fetchAndCache(request, oldPoints: old?.points ?? [], now: now) }
        pending[request] = task
        defer { pending[request] = nil }
        return try await task.value
    }

    private func fetchAndCache(_ request: CardMarketHistoryRequest, oldPoints: [JustTCGHistoryPoint], now: Date) async throws -> [JustTCGHistoryPoint] {
        let received = try await fetch(request)
        // Retain previously retrieved provider history as the API's rolling
        // window advances. Never trim this series to collection membership.
        var byTime: [Double: JustTCGHistoryPoint] = [:]
        for point in oldPoints + received
            where point.p.isFinite && point.p >= 0 && point.t.isFinite && point.t > 0
                && point.t <= now.timeIntervalSince1970 {
            byTime[point.t] = point
        }
        let points = byTime.values.sorted { $0.t < $1.t }
        let identity = identityData(request)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = root
        try? directory.setResourceValues(values)
        let cached = Cached(requestData: identity, fetchedAt: now, points: points)
        try JSONEncoder().encode(cached).write(to: cacheURL(identity), options: .atomic)
        return points
    }

    private func fetch(_ request: CardMarketHistoryRequest) async throws -> [JustTCGHistoryPoint] {
        if request.itemKind == .gradedCard {
            // Graded cards already carry an exact vendor variant selected by
            // the graded picker. Never substitute a raw-card history.
            guard let id = request.marketVariantID else { throw HistoryError.noListing }
            let response: JustTCGV2CardsResponse = try await transport.get("v2/cards", query: [
                ("variant_id", id), ("graded", "only"), ("regions", "NA"),
                ("include", "price_history.1y")
            ], lane: .interactive)
            guard let variant = response.data.flatMap({ $0.variants ?? [] }).first(where: {
                $0.variantId == id && $0.type?.lowercased() == "graded"
            }) else { throw HistoryError.noListing }
            return Self.points(from: variant)
        }

        var lookups = request.lookups
        if let catalogID = request.catalogID {
            lookups.insert(contentsOf: PriceFallbackQuoteResolver.verifiedLookups(
                catalogID: catalogID, variant: request.variantID.map(PhysicalVariant.resolving)
            ), at: 0)
        }
        var variantID = request.marketVariantID
        if variantID == nil, request.game == .magic, lookups.isEmpty, let id = request.catalogID,
               !id.hasPrefix("csv:"), let card = try? await ScryfallService().fetchCard(id: id),
               let productID = card.tcgplayerID {
            lookups = [.tcgplayerID(String(productID))]
        }
        // Older Pokémon print runs also alter vendor sets/printing names.
        // Resolve the edition before asking for an exact variant's history.
        if variantID == nil && (lookups.isEmpty || request.printRun != nil) {
            guard request.game == .pokemon || request.game == .magic else { throw HistoryError.noListing }
            guard PriceVendorCredentials.hasKey else { throw JustTCGTransport.TransportError.missingCredentials }
            var vendorCardID: String?
            if case let .cardID(id)? = lookups.first { vendorCardID = id }
            let subject = ProductPriceSubject(
                game: request.game, catalogID: request.catalogID, name: request.name,
                setName: request.setName, cardNumber: request.number,
                japaneseSetID: request.catalogID.flatMap(PriceFallbackQuoteResolver.japaneseSetID(forCatalogCardID:)),
                pokemonPrintRun: request.printRun, vendorCardID: vendorCardID,
                magicTreatmentIDsRaw: request.treatments
            )
            let outcome = await ProductPriceService.shared.quote(
                for: subject, variant: request.variantID.map(PhysicalVariant.resolving), lane: .interactive
            )
            variantID = outcome.vendorVariantID
            switch outcome {
            case let .budgetReached(resetAt): throw JustTCGTransport.TransportError.budgetReached(resetAt: resetAt)
            case let .rateLimited(retryAt): throw JustTCGTransport.TransportError.rateLimited(retryAt: retryAt)
            case .requestFailed: throw HistoryError.requestFailed
            default: break
            }
        }
        let target = MarketPriceTarget(
            priceKey: request.printingID, game: request.game, printingID: request.printingID,
            variantID: request.variantID, itemKind: request.itemKind, marketVariantID: variantID,
            lookupCandidates: lookups, currentAmount: nil, lastCheckedAt: nil,
            magicTreatmentIDsRaw: request.treatments, exactPhysicalProductID: request.exactProductID,
            pokemonPrintRun: request.printRun
        )
        guard let lookup = target.lookup else { throw HistoryError.noListing }
        // GET explicitly supports the longest history duration. Routine batch
        // refreshes remain lean and do not consume history requests.
        let response: JustTCGBatchResponse = try await transport.get("v1/cards", query: [
            (lookup.wireKey, lookup.value), ("include_price_history", "true"),
            ("priceHistoryDuration", "1y")
        ], lane: .interactive)
        if case let .tcgplayerID(productID) = lookup, let printing = request.providerPrinting,
           let card = response.data.first(where: { $0.tcgplayerId == productID }),
           let variant = card.variants?.first(where: {
               $0.condition?.caseInsensitiveCompare(ProductFinish.condition) == .orderedSame
                   && $0.printing?.caseInsensitiveCompare(printing) == .orderedSame
           }) {
            return Self.points(from: variant)
        }
        guard case let .matched(_, variant) = JustTCGRefreshCoordinator.exactListing(
            lookup: lookup, owners: [target], response: response
        ) else { throw HistoryError.noListing }
        return Self.points(from: variant)
    }

    private static func points(from variant: JustTCGVariant) -> [JustTCGHistoryPoint] {
        var points = variant.historyUSD
        if let amount = variant.marketPriceUSD, let updatedAt = variant.updatedAt {
            points.append(.init(p: amount, t: updatedAt.timeIntervalSince1970))
        }
        return points
    }
}
