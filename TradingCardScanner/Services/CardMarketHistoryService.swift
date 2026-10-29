import Foundation

/// Market history is independent of ownership, local check days and portfolio
/// accounting. Each request identifies one physical listing, never a card name
/// alone. The provider currently exposes at most a trailing year of points.
struct CardMarketHistoryRequest: Hashable, Sendable {
    let game: CardGame
    let printingID: String
    let variantID: String?
    let itemKind: CollectionItemKind
    var marketVariantID: String?
    var lookups: [JustTCGBatchLookup]
    let name: String
    let setName: String
    let number: String
    let catalogID: String?
    let printRun: PokemonPrintRun?
    let treatments: [String]
    var exactProductID: String?
    var providerPrinting: String? = nil
    var authorityRevision: String? = nil

    var requiresCatalogMapping: Bool {
        itemKind == .rawCard && (game == .onePiece || game == .lorcana)
    }

    var historyIdentity: [String] {
        ["history-v2", game.rawValue, printingID, variantID ?? "", itemKind.rawValue,
         itemKind == .gradedCard ? (marketVariantID ?? "") : "",
         printRun?.rawValue ?? "", treatments.sorted().joined(separator: "|"),
         exactProductID ?? "", providerPrinting ?? ""]
    }

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

    /// Newer game modules own their reviewed raw-card marketplace mappings. Resolve
    /// those from the active catalog, preserving physical UUID/finish identity.
    func resolvingMarketMapping(in runtimes: CardGameRuntimeContainer?) async -> Self {
        var result = self
        guard requiresCatalogMapping else { return result }
        // Raw printings require current catalog authority. Sealed and graded
        // products retain the exact vendor listing selected by their pickers.
        result.exactProductID = nil
        result.providerPrinting = nil
        result.marketVariantID = nil
        result.lookups = []
        result.authorityRevision = nil
        guard let runtime = runtimes?.runtime(for: game),
              let id = UUID(uuidString: catalogID ?? printingID) else { return result }
        let catalog: (any GameCatalogAdapter)?
        if let source = runtime.activationSource {
            guard let snapshot = await source.currentSnapshot() else { return result }
            catalog = snapshot.catalog
            result.authorityRevision = "\(snapshot.revision):\(snapshot.catalog.generation)"
        } else {
            catalog = runtime.catalog
            result.authorityRevision = catalog?.generation
        }
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
        /// The marketplace product the provider actually returned for this
        /// series. Nil for legacy entries and responses without a product id.
        var sourceProductID: String? = nil
        /// When the provider last answered without the requested listing, and
        /// the lookup inputs that answer applies to.
        var noListingAt: Date? = nil
        var noListingInputs: [String]? = nil
    }

    /// Detail history spends the same daily vendor allowance as price refresh.
    /// A listing the provider lacks is asked about again only after this.
    private static let noListingRetryInterval: TimeInterval = 24 * 60 * 60

    private static func noListingInputs(_ request: CardMarketHistoryRequest) -> [String] {
        [request.marketVariantID ?? ""] + request.lookups.map { "\($0.wireKey)=\($0.value)" }
    }

    private let transport: JustTCGTransport
    private let root: URL
    private struct PendingHistory {
        let id: UUID
        let task: Task<[JustTCGHistoryPoint], Error>
        var waiterIDs: Set<UUID>
    }
    private var pending: [CardMarketHistoryRequest: PendingHistory] = [:]

    init(transport: JustTCGTransport = .shared, root: URL? = nil) {
        self.transport = transport
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CardMarketHistory", isDirectory: true)
    }

    /// The identity is encoded rather than relying on Swift's process-random hash.
    private func identityData(_ request: CardMarketHistoryRequest) -> Data {
        (try? JSONEncoder().encode(request.historyIdentity)) ?? Data()
    }

    private func cacheURL(_ data: Data) -> URL {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return root.appendingPathComponent(String(hash, radix: 16) + ".json")
    }

    func cached(_ request: CardMarketHistoryRequest, runtimes: CardGameRuntimeContainer? = nil) async -> [JustTCGHistoryPoint] {
        let resolved = await request.resolvingMarketMapping(in: runtimes)
        guard !resolved.requiresCatalogMapping || resolved.exactProductID != nil else { return [] }
        let points = readCache(resolved)?.points ?? []
        guard await resolved.resolvingMarketMapping(in: runtimes) == resolved else { return [] }
        return points
    }

    private func readCache(_ request: CardMarketHistoryRequest) -> Cached? {
        if let cached = readExactCache(request) { return cached }
        // A raw printing can acquire its marketplace binding after its first
        // history visit. Reuse that unbound series only when the provider
        // proved it came from the bound product; unproven or different
        // products stay under their own identity and the binding fetches anew.
        guard request.itemKind == .rawCard,
              request.game == .pokemon || request.game == .magic,
              let productID = request.exactProductID else { return nil }
        var unbound = request
        unbound.exactProductID = nil
        guard let cached = readExactCache(unbound), cached.sourceProductID == productID else { return nil }
        return cached
    }

    private func readExactCache(_ request: CardMarketHistoryRequest) -> Cached? {
        let identity = identityData(request)
        guard let data = try? Data(contentsOf: cacheURL(identity)),
              let cached = try? JSONDecoder().decode(Cached.self, from: data),
              cached.requestData == identity else { return nil }
        return cached
    }

    func history(for input: CardMarketHistoryRequest, now: Date = .now,
                 runtimes: CardGameRuntimeContainer? = nil) async throws -> [JustTCGHistoryPoint] {
        let request = await input.resolvingMarketMapping(in: runtimes)
        try Task.checkCancellation()
        guard !request.requiresCatalogMapping || request.exactProductID != nil else { throw HistoryError.noListing }
        let old = readCache(request)
        if let old, let missAt = old.noListingAt, now.timeIntervalSince(missAt) < Self.noListingRetryInterval,
           old.noListingInputs == Self.noListingInputs(request) {
            throw HistoryError.noListing
        }
        if let old, now.timeIntervalSince(old.fetchedAt) < 6 * 60 * 60 {
            return try await currentResult(old.points, for: request, runtimes: runtimes)
        }
        let waiterID = UUID()
        let state: PendingHistory
        if var existing = pending[request] {
            existing.waiterIDs.insert(waiterID)
            pending[request] = existing
            state = existing
        } else {
            state = PendingHistory(id: UUID(), task: Task {
                try Task.checkCancellation()
                return try await self.fetchAndCache(request, old: old, now: now, runtimes: runtimes)
            }, waiterIDs: [waiterID])
            pending[request] = state
        }
        defer { releaseWaiter(waiterID, request: request, taskID: state.id) }
        return try await withTaskCancellationHandler {
            try await currentResult(state.task.value, for: request, runtimes: runtimes)
        } onCancel: {
            Task { await self.releaseWaiter(waiterID, request: request, taskID: state.id) }
        }
    }

    private func releaseWaiter(_ waiterID: UUID, request: CardMarketHistoryRequest, taskID: UUID) {
        guard var state = pending[request], state.id == taskID,
              state.waiterIDs.remove(waiterID) != nil else { return }
        if state.waiterIDs.isEmpty {
            pending[request] = nil
            state.task.cancel()
        } else {
            pending[request] = state
        }
    }

    private func currentResult(_ points: [JustTCGHistoryPoint], for request: CardMarketHistoryRequest,
                               runtimes: CardGameRuntimeContainer?) async throws -> [JustTCGHistoryPoint] {
        guard await request.resolvingMarketMapping(in: runtimes) == request else { throw CancellationError() }
        try Task.checkCancellation()
        return points
    }

    private func fetchAndCache(_ request: CardMarketHistoryRequest, old: Cached?, now: Date,
                               runtimes: CardGameRuntimeContainer?) async throws -> [JustTCGHistoryPoint] {
        let received: (points: [JustTCGHistoryPoint], sourceProductID: String?)
        do {
            received = try await fetch(request)
        } catch HistoryError.noListing {
            guard await request.resolvingMarketMapping(in: runtimes) == request else { throw CancellationError() }
            try Task.checkCancellation()
            // Keep any saved series; remember only that this exact lookup missed.
            try? writeCache(Cached(requestData: identityData(request), fetchedAt: old?.fetchedAt ?? .distantPast,
                                   points: old?.points ?? [], sourceProductID: old?.sourceProductID,
                                   noListingAt: now, noListingInputs: Self.noListingInputs(request)))
            throw HistoryError.noListing
        }
        guard await request.resolvingMarketMapping(in: runtimes) == request else { throw CancellationError() }
        try Task.checkCancellation()
        // A miss-only record carries no history to retain.
        let old = old.flatMap { $0.points.isEmpty ? nil : $0 }
        // Retain previously retrieved provider history as the API's rolling
        // window advances. Never trim this series to collection membership.
        // One series holds one product: a proven different product replaces
        // it, while unproven legacy history is kept but stays unproven.
        var oldPoints: [JustTCGHistoryPoint] = []
        var sourceProductID = received.sourceProductID
        if let old, old.sourceProductID == received.sourceProductID {
            oldPoints = old.points
        } else if let old, old.sourceProductID == nil {
            oldPoints = old.points
            sourceProductID = nil
        }
        var byTime: [Double: JustTCGHistoryPoint] = [:]
        for point in oldPoints + received.points
            where point.p.isFinite && point.p >= 0 && point.t.isFinite && point.t > 0
                && point.t <= now.timeIntervalSince1970 {
            byTime[point.t] = point
        }
        let points = byTime.values.sorted { $0.t < $1.t }
        try writeCache(Cached(requestData: identityData(request), fetchedAt: now, points: points,
                              sourceProductID: sourceProductID))
        return points
    }

    private func writeCache(_ cached: Cached) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = root
        try? directory.setResourceValues(values)
        try JSONEncoder().encode(cached).write(to: cacheURL(cached.requestData), options: .atomic)
    }

    /// Points plus the marketplace product the provider returned them for.
    private func fetch(_ request: CardMarketHistoryRequest) async throws
        -> (points: [JustTCGHistoryPoint], sourceProductID: String?) {
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
            return (Self.points(from: variant), nil)
        }

        var lookups = request.lookups
        if !request.requiresCatalogMapping, let catalogID = request.catalogID {
            lookups.insert(contentsOf: PriceFallbackQuoteResolver.verifiedLookups(
                catalogID: catalogID, variant: request.variantID.map(PhysicalVariant.resolving)
            ), at: 0)
        }
        var variantID = request.marketVariantID
        if variantID == nil, request.game == .magic, lookups.isEmpty, let id = request.catalogID,
               !id.hasPrefix("csv:"), let card = try? await ScryfallService().fetchCard(id: id),
               let productID = card.tcgplayerProductID(for: request.variantID.map(PhysicalVariant.resolving)) {
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
        if case let .tcgplayerID(productID) = lookup, let printing = request.providerPrinting {
            guard let card = response.data.first(where: { $0.tcgplayerId == productID }),
                  let variant = card.variants?.first(where: {
               $0.condition?.caseInsensitiveCompare(ProductFinish.condition) == .orderedSame
                   && $0.printing?.caseInsensitiveCompare(printing) == .orderedSame
                  }) else { throw HistoryError.noListing }
            return (Self.points(from: variant), Self.productID(of: card))
        }
        guard case let .matched(card, variant) = JustTCGRefreshCoordinator.exactListing(
            lookup: lookup, owners: [target], response: response
        ) else { throw HistoryError.noListing }
        return (Self.points(from: variant), Self.productID(of: card))
    }

    private static func productID(of card: JustTCGCard) -> String? {
        guard let id = card.tcgplayerId, !id.isEmpty else { return nil }
        return id
    }

    private static func points(from variant: JustTCGVariant) -> [JustTCGHistoryPoint] {
        var points = variant.historyUSD
        if let amount = variant.marketPriceUSD, let updatedAt = variant.updatedAt {
            points.append(.init(p: amount, t: updatedAt.timeIntervalSince1970))
        }
        return points
    }
}
