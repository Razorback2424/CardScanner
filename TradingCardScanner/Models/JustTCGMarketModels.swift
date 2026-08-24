import Foundation

// MARK: - Batch lookup

/// One item inside a `POST /v1/cards` batch.
///
/// Modelled as an enum because the vendor requires **exactly one** identifier per
/// item and states a precedence between them. A struct with six optionals would
/// let a caller send two, or none, and find out at runtime; this cannot express
/// either mistake.
///
/// Precedence, vendor's own order, fastest first:
///
///     variantId > tcgplayerSkuId > tcgplayerId > mtgjsonId > scryfallId > cardId
///
/// Once a `variantId` is known it is always the right choice — it identifies the
/// exact printing *and* finish, which is the same granularity the app prices at.
enum JustTCGBatchLookup: Hashable, Sendable {
    case variantID(String)
    case tcgplayerSKUID(String)
    case tcgplayerID(String)
    case mtgjsonID(String)
    case scryfallID(String)
    case cardID(String)

    /// Lower sorts first. Used to pick the best available identifier for a card
    /// rather than whichever one happened to be checked first.
    var precedence: Int {
        switch self {
        case .variantID: return 0
        case .tcgplayerSKUID: return 1
        case .tcgplayerID: return 2
        case .mtgjsonID: return 3
        case .scryfallID: return 4
        case .cardID: return 5
        }
    }

    var wireKey: String {
        switch self {
        case .variantID: return "variantId"
        case .tcgplayerSKUID: return "tcgplayerSkuId"
        case .tcgplayerID: return "tcgplayerId"
        case .mtgjsonID: return "mtgjsonId"
        case .scryfallID: return "scryfallId"
        case .cardID: return "cardId"
        }
    }

    var value: String {
        switch self {
        case let .variantID(v), let .tcgplayerSKUID(v), let .tcgplayerID(v),
             let .mtgjsonID(v), let .scryfallID(v), let .cardID(v):
            return v
        }
    }

    /// The best identifier available, by the vendor's precedence.
    static func best(from candidates: [JustTCGBatchLookup]) -> JustTCGBatchLookup? {
        candidates.min { $0.precedence < $1.precedence }
    }
}

extension JustTCGBatchLookup: Encodable {
    private struct DynamicKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        guard let key = DynamicKey(stringValue: wireKey) else { return }
        try container.encode(value, forKey: key)
    }
}

/// The body of a batch price request.
struct JustTCGBatchRequest: Encodable, Sendable {
    let items: [JustTCGBatchLookup]
    /// Routine collection pricing never asks for history. History is an order of
    /// magnitude more data for a number the collection does not display, and it
    /// is fetched lazily from an item's detail screen instead.
    let includePriceHistory: Bool
    /// Only variants the vendor has repriced since this moment. A delta.
    let updatedAfter: Date?

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for item in items { try container.encode(item) }
    }

    /// The query parameters that accompany the POST body.
    var queryItems: [(String, String)] {
        var query: [(String, String)] = [
            ("include_price_history", includePriceHistory ? "true" : "false")
        ]
        if let updatedAfter {
            query.append(("updated_after", String(Int(updatedAfter.timeIntervalSince1970))))
        }
        return query
    }
}

// MARK: - Responses

struct JustTCGBatchResponse: Decodable, Sendable {
    let data: [JustTCGCard]
    /// Present on every response; the vendor's own view of the allowance.
    let metadata: JustTCGQuotaMetadata?

    enum CodingKeys: String, CodingKey {
        case data
        case metadata = "_metadata"
    }

    /// Every returned variant, flattened and keyed by its stable variant id, so
    /// the coordinator can correlate results back to what it asked for without
    /// relying on array order.
    var variantsByID: [String: (card: JustTCGCard, variant: JustTCGVariant)] {
        var result: [String: (JustTCGCard, JustTCGVariant)] = [:]
        for card in data {
            for variant in card.variants ?? [] {
                guard let id = variant.variantId else { continue }
                result[id] = (card, variant)
            }
        }
        return result
    }
}

struct JustTCGCard: Decodable, Sendable {
    /// Human-readable slug, e.g. `pokemon-arceus-charizard-holo-rare`.
    let id: String?
    /// The stable UUID. This is what the vendor recommends as a primary key and
    /// what survives their slug changes, so it is what the app persists.
    let uuid: String?
    let name: String?
    let game: String?
    /// The set's slug, e.g. `arceus-pokemon`.
    let set: String?
    /// The set's display name, e.g. `Arceus`.
    let setName: String?
    /// Printed number, e.g. `1/99`. Sealed products carry the literal `N/A`.
    let number: String?
    let rarity: String?
    let tcgplayerId: String?
    let mtgjsonId: String?
    let scryfallId: String?
    let variants: [JustTCGVariant]?

    /// `N/A` is the vendor's way of saying a product has no collector number —
    /// treating it as one would make every sealed product look identically
    /// numbered.
    var printedNumber: String? {
        guard let number, number.caseInsensitiveCompare("N/A") != .orderedSame else { return nil }
        return number
    }

    /// Identifiers this card can be batched by, best-first.
    var lookupCandidates: [JustTCGBatchLookup] {
        var candidates: [JustTCGBatchLookup] = []
        if let tcgplayerId { candidates.append(.tcgplayerID(tcgplayerId)) }
        if let mtgjsonId { candidates.append(.mtgjsonID(mtgjsonId)) }
        if let scryfallId { candidates.append(.scryfallID(scryfallId)) }
        if let uuid { candidates.append(.cardID(uuid)) }
        return candidates
    }

    enum CodingKeys: String, CodingKey {
        case id, uuid, name, game, set, number, rarity, variants
        case tcgplayerId, mtgjsonId, scryfallId
        case setName = "set_name"
    }
}

struct JustTCGVariant: Decodable, Sendable {
    /// Human-readable slug, e.g. `..._near-mint_holofoil`.
    let id: String?
    /// The stable UUID. **This is the identifier batches are built from** — the
    /// field is `uuid`, not `variantId`, which is worth stating because the
    /// documentation's parameter name is `variantId` and the response's field
    /// name is not.
    let uuid: String?
    let condition: String?
    let printing: String?
    let language: String?
    /// Second in the vendor's lookup precedence, and it lives on the variant
    /// rather than the card because a SKU is condition- and finish-specific.
    let tcgplayerSkuId: String?
    /// `null` is a real answer meaning "no reliable market price", and is
    /// distinct from the field being absent.
    let price: Double?
    let currency: String?
    let lastUpdated: Double?
    /// Present only on `/v2/cards` results for graded slabs.
    let grading: JustTCGGrading?

    // Rolling statistics, returned alongside the price. Populated on every
    // response, so they cost nothing extra and can back a "limited market
    // history" indicator without a second request.
    let priceChange24hr: Double?
    let priceChange7d: Double?
    let minPrice7d: Double?
    let maxPrice7d: Double?
    let covPrice7d: Double?
    let priceChangesCount7d: Int?

    /// What the app sends to identify this exact object.
    var variantId: String? { uuid ?? id }

    var updatedAt: Date? { lastUpdated.map { Date(timeIntervalSince1970: $0) } }

    /// Sealed products are priced through the same variant infrastructure as
    /// singles, distinguished by this condition value.
    var isSealed: Bool {
        condition?.caseInsensitiveCompare("Sealed") == .orderedSame
            || condition?.caseInsensitiveCompare("S") == .orderedSame
    }

    enum CodingKeys: String, CodingKey {
        case id, uuid, condition, printing, language, tcgplayerSkuId
        case price, currency, lastUpdated, grading
        case priceChange24hr, priceChange7d, minPrice7d, maxPrice7d
        case covPrice7d, priceChangesCount7d
    }
}

/// The grading block on a v2 variant.
struct JustTCGGrading: Decodable, Sendable {
    let company: String?
    /// Numeric for most slabs; `null` for Authentic, which the vendor models
    /// deliberately rather than inventing a number.
    let grade: Double?
    let label: String?
    let qualifier: String?

    var gradingCompany: GradingCompany? {
        company.flatMap(GradingCompany.named)
    }

    /// Formatted without a trailing `.0`, so a 10 reads as `10` and a 9.5 as
    /// `9.5`.
    var gradeText: String? {
        guard let grade else { return nil }
        return grade == grade.rounded()
            ? String(Int(grade))
            : String(grade)
    }

    var cardGrade: CardGrade {
        CardGrade(value: gradeText, label: label, qualifier: qualifier)
    }
}

// MARK: - Discovery

/// One page of market-catalogue results.
///
/// Named apart from Browse's `CatalogPage`, which is cursor-based and belongs to
/// the TCGdex/Scryfall directory. This one is the vendor's, and offset-based.
///
/// Offset-based, because that is what the vendor publishes: `meta` carries
/// `{ total, limit, offset, hasMore }`. There is no cursor.
struct MarketCatalogPage<Element: Sendable>: Sendable {
    let items: [Element]
    let total: Int
    let offset: Int
    let limit: Int
    let hasMore: Bool

    var nextOffset: Int? { hasMore ? offset + limit : nil }
}

/// The `meta` block on a list response.
struct JustTCGListMeta: Decodable, Sendable {
    let total: Int?
    let limit: Int?
    let offset: Int?
    let hasMore: Bool?
}

/// The `_metadata` block, present on every response.
///
/// The vendor reports the live state of the plan's allowance with each reply.
/// That is authoritative in a way a local counter never is — it survives
/// reinstalls, it accounts for requests made from anywhere else, and it cannot
/// drift. The local ledger becomes a pre-flight guard that stops a request we
/// already know would fail; this is the truth it corrects itself against.
struct JustTCGQuotaMetadata: Decodable, Sendable, Equatable {
    let apiPlan: String?
    let apiDailyLimit: Int?
    let apiDailyRequestsUsed: Int?
    let apiDailyRequestsRemaining: Int?
    let apiRequestLimit: Int?
    let apiRequestsUsed: Int?
    let apiRequestsRemaining: Int?

    /// The batch size this plan allows. Free is 20; paid tiers are 100.
    var batchSize: Int {
        guard let limit = apiDailyLimit else { return JustTCGQuota.batchSize }
        return limit <= 100 ? 20 : 100
    }
}

/// A sealed product as it appears in a browse grid.
///
/// Deliberately narrow. The vendor does not document UPC, MSRP, pack counts or
/// product taxonomy, so this type does not carry fields the UI would then be
/// tempted to display as fact.
struct SealedProductSummary: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let setName: String?
    let variantID: String?
    let marketPriceUSD: Double?
    let updatedAt: Date?
    /// Only when the provider actually returned one; otherwise the UI uses a
    /// set or game placeholder rather than an image from somewhere else.
    let imageURL: URL?
}

/// A set as the vendor groups it, with its sealed inventory count.
///
/// Sealed browse uses the vendor's own set directory rather than TCGdex's or
/// Scryfall's, because mapping between the two groupings is unreliable and a
/// wrong mapping would show the wrong products.
struct SealedSetSummary: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let sealedCount: Int
    let game: CardGame
}

/// One purchasable graded variant of a card.
struct GradedVariant: Identifiable, Hashable, Sendable {
    let id: String
    let company: GradingCompany
    let grade: CardGrade
    let marketPriceUSD: Double?
    let updatedAt: Date?

    var displayName: String { grade.display(company: company) }
}

// MARK: - Sync checkpoints

/// Where synchronisation with the vendor stands, per game and API version.
///
/// `updated_after` is only safe once a *complete* pass has succeeded. Using it
/// before that would silently skip variants the app has never fetched, and their
/// absence from a delta response is indistinguishable from "unchanged".
struct JustTCGSyncCheckpoint: Codable, Hashable, Sendable {
    let game: String
    let apiVersion: String
    /// The vendor's own "this game was repriced at" clock.
    var providerLastUpdated: Date?
    /// Only set after every batch in a pass succeeded.
    var lastCompleteSyncAt: Date?

    /// Whether a delta request is safe.
    var supportsDeltaSync: Bool { lastCompleteSyncAt != nil }
}

/// How current a stored price is considered.
enum MarketFreshness: Sendable {
    /// The vendor reprices roughly every six to seven hours per game, so asking
    /// more often than that returns the same number and spends quota to do it.
    static let threshold: TimeInterval = 6 * 60 * 60

    /// Whether a price needs refetching.
    ///
    /// A missing price is always eligible: it is the case the fallback exists
    /// for, and no provider clock should hold it back.
    static func needsRefresh(
        amount: Double?,
        checkedAt: Date?,
        providerUpdatedAt: Date?,
        now: Date = .now
    ) -> Bool {
        guard amount != nil, let checkedAt else { return true }
        guard now.timeIntervalSince(checkedAt) >= threshold else { return false }
        // Past the threshold, defer to the provider's clock when it publishes
        // one: if the game has not been repriced since the last check, another
        // request buys the same number.
        guard let providerUpdatedAt else { return true }
        return providerUpdatedAt > checkedAt
    }
}
