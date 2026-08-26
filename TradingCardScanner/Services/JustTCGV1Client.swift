import Foundation

/// What the app asks a market provider for, independent of which API version
/// answers. Sealed and graded work can move between endpoints later without the
/// collection layer noticing.
protocol JustTCGProviding: Sendable {
    func batchCards(
        _ lookups: [JustTCGBatchLookup],
        updatedAfter: Date?,
        includePriceHistory: Bool,
        lane: JustTCGRequestLane
    ) async throws -> JustTCGBatchResponse

    func searchSealedProducts(
        game: CardGame,
        setID: String?,
        query: String?,
        offset: Int
    ) async throws -> MarketCatalogPage<SealedProductSummary>

    func sealedSets(game: CardGame) async throws -> [SealedSetSummary]

    func gradedVariants(
        cardID: String,
        game: CardGame,
        companies: Set<GradingCompany>,
        grades: Set<String>
    ) async throws -> [GradedVariant]
}

/// The stable v1 API: raw singles, sealed products, and batch pricing.
///
/// Sealed products are not a separate endpoint. They live in the same `/cards`
/// dataset with `condition: "Sealed"`, which is why one batch path serves both
/// and why a booster box refreshes through exactly the machinery a single does.
struct JustTCGV1Client: Sendable {
    static let apiVersion = "v1"

    private let transport: JustTCGTransport

    init(transport: JustTCGTransport) {
        self.transport = transport
    }

    // MARK: - Batch pricing

    /// Price many variants with one HTTP request.
    ///
    /// This is the whole point of the refactor: a batch of twenty costs one
    /// request against the daily allowance, not twenty. Callers must chunk to
    /// `JustTCGQuota.batchSize` — this asserts rather than silently truncating,
    /// because a silently dropped tail becomes prices that never refresh.
    func batchCards(
        _ lookups: [JustTCGBatchLookup],
        updatedAfter: Date? = nil,
        includePriceHistory: Bool = false,
        lane: JustTCGRequestLane = .background
    ) async throws -> JustTCGBatchResponse {
        precondition(
            lookups.count <= JustTCGQuota.batchSize,
            "Batch of \(lookups.count) exceeds the plan's \(JustTCGQuota.batchSize)-item limit"
        )
        guard !lookups.isEmpty else { return JustTCGBatchResponse(data: [], metadata: nil) }

        let request = JustTCGBatchRequest(
            items: lookups,
            includePriceHistory: includePriceHistory,
            updatedAfter: updatedAfter
        )
        return try await transport.post(
            "v1/cards",
            query: request.queryItems,
            body: request,
            lane: lane,
            as: JustTCGBatchResponse.self
        )
    }

    // MARK: - Sealed discovery

    /// Sets that actually contain sealed inventory.
    ///
    /// Filtered on the vendor's own `sealed_count`, and grouped the vendor's own
    /// way. Mapping their set groupings onto TCGdex or Scryfall set identities
    /// is unreliable, and a wrong mapping shows the user the wrong products —
    /// so sealed browse deliberately uses their directory as published.
    func sealedSets(game: CardGame) async throws -> [SealedSetSummary] {
        let response: SetsResponse = try await transport.get(
            "v1/sets",
            query: [("game", Self.gameSlug(for: game))],
            lane: .interactive
        )
        return response.data.compactMap { set in
            guard let id = set.id, let count = set.sealedCount, count > 0 else { return nil }
            return SealedSetSummary(
                id: id,
                name: set.name ?? id,
                sealedCount: count,
                game: game
            )
        }
    }

    /// Sealed products, by set or by free text.
    ///
    /// Interactive lane: this only ever runs because someone opened a set or
    /// pressed Search, and it should not be blocked by a background refresh
    /// having spent the day's allowance.
    func searchSealedProducts(
        game: CardGame,
        setID: String? = nil,
        query: String? = nil,
        offset: Int = 0,
        limit: Int = JustTCGQuota.maximumPageSize
    ) async throws -> MarketCatalogPage<SealedProductSummary> {
        var parameters: [(String, String)] = [
            ("game", Self.gameSlug(for: game)),
            // Verified against the live API: this genuinely filters, and the
            // returned variants carry condition "Sealed" and nothing else.
            ("condition", "Sealed"),
            ("limit", String(limit)),
            ("offset", String(offset))
        ]
        if let setID { parameters.append(("set", setID)) }
        if let query, !query.isEmpty { parameters.append(("q", query)) }

        let response: CardsResponse = try await transport.get(
            "v1/cards",
            query: parameters,
            lane: .interactive
        )

        let items = response.data.compactMap { card -> SealedProductSummary? in
            guard let id = card.uuid ?? card.id else { return nil }
            let sealed = (card.variants ?? []).first { $0.isSealed } ?? card.variants?.first
            return SealedProductSummary(
                id: id,
                name: card.name ?? id,
                // The display name, not the slug — `Legendary Treasures`
                // rather than `legendary-treasures-pokemon`.
                setName: card.setName ?? card.set,
                variantID: sealed?.variantId,
                // Dollars. Verified: fractional sealed prices exist, so these
                // are not cents.
                marketPriceUSD: sealed?.price,
                updatedAt: sealed?.updatedAt,
                // JustTCG already supplies the canonical TCGplayer product ID.
                // Keep the CDN convention isolated here so a provider-supplied
                // image URL can replace it without touching models or views.
                imageURL: Self.productImageURL(tcgplayerID: card.tcgplayerId),
                tcgplayerProductID: card.tcgplayerId
            )
        }
        return MarketCatalogPage(
            items: items,
            total: response.meta?.total ?? items.count,
            offset: response.meta?.offset ?? offset,
            limit: response.meta?.limit ?? limit,
            hasMore: response.meta?.hasMore ?? false
        )
    }

    static func productImageURL(tcgplayerID: String?) -> URL? {
        guard let id = tcgplayerID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty,
              id.allSatisfy({ $0.isNumber }) else { return nil }
        // TCGplayer's canonical product CDN. The 400-point asset is large enough
        // for the collection/detail surfaces without making a scrolling grid
        // decode many 1000px gateway responses at once.
        return URL(string: "https://tcgplayer-cdn.tcgplayer.com/product/\(id)_400w.jpg")
    }

    /// Rewrites the gateway URL used by older app builds to the direct CDN.
    /// This is intentionally local: an existing sealed collection should not
    /// spend a metered API request merely to repair a URL whose product id it
    /// already contains.
    static func migratedProductImageURL(from storedURL: String?) -> URL? {
        guard let storedURL,
              let legacy = URL(string: storedURL),
              legacy.host?.lowercased() == "product-images.tcgplayer.com" else {
            return nil
        }
        let filename = legacy.deletingPathExtension().lastPathComponent
        return productImageURL(tcgplayerID: filename)
    }

    // MARK: - Games

    /// The vendor's game slugs, verified against their live `/games` listing.
    static func gameSlug(for game: CardGame) -> String {
        switch game {
        case .pokemon: return "pokemon"
        case .magic: return "magic-the-gathering"
        }
    }

    /// Japanese printings are a separate product line rather than a locale.
    static func gameSlug(for game: CardGame, isJapanese: Bool) -> String {
        if game == .pokemon, isJapanese { return "pokemon-japan" }
        return gameSlug(for: game)
    }

    // MARK: - Wire format

    private struct SetsResponse: Decodable {
        let data: [SetPayload]
        let metadata: JustTCGQuotaMetadata?

        enum CodingKeys: String, CodingKey {
            case data
            case metadata = "_metadata"
        }
    }

    private struct SetPayload: Decodable {
        let id: String?
        let name: String?
        let sealedCount: Int?

        enum CodingKeys: String, CodingKey {
            case id, name
            case sealedCount = "sealed_count"
        }
    }

    private struct CardsResponse: Decodable {
        let data: [JustTCGCard]
        let meta: JustTCGListMeta?
        let metadata: JustTCGQuotaMetadata?

        enum CodingKeys: String, CodingKey {
            case data, meta
            case metadata = "_metadata"
        }
    }
}
