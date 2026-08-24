import Foundation

/// What the fallback was able to say about one physical variant.
///
/// The outcomes are kept apart because they mean different things to
/// the person reading the collection: a card the vendor has never heard of is a
/// matching problem, a card it carries but does not list in this finish is
/// genuinely unpriced, and a failed request is nothing at all.
enum ProductPriceOutcome: Equatable, Sendable {
    /// The handle travels with the answer so the caller can cache it without
    /// paying for the search a second time.
    case price(NormalizedPrice, vendorCardID: String?)
    /// The product was found; it has no listing for this finish.
    case noListingForVariant(vendorCardID: String?)
    /// Nothing came back that passed identity checking.
    case noProductMatch
    /// No request was made because this run or today's persisted allowance was
    /// exhausted. This is scheduling state, not evidence about the card.
    case budgetReached(resetAt: Date)
    /// The vendor asked the app to stop. No identity or price failure is cached.
    case rateLimited(retryAt: Date)
    case requestFailed

    var vendorCardID: String? {
        switch self {
        case let .price(_, id), let .noListingForVariant(id): return id
        case .noProductMatch, .budgetReached, .rateLimited, .requestFailed: return nil
        }
    }
}

/// Everything the vendor needs to look one card up, and everything needed to
/// check that what came back is the same card.
struct ProductPriceSubject: Sendable {
    let game: CardGame
    /// The catalog id, where one was resolved. Used to tell a Japanese printing
    /// from an English one.
    let catalogID: String?
    let name: String
    let setName: String
    let cardNumber: String
    /// The TCGdex `ja` set id, for Japanese-exclusive printings.
    let japaneseSetID: String?
    /// A previously resolved vendor handle. Present means the search has already
    /// been paid for once and this refresh is a cheap keyed lookup.
    let vendorCardID: String?
}

/// The product-level price fallback.
///
/// An actor because the free tier allows ten requests a minute and the pacing
/// has to be enforced in one place — a per-call delay scattered across the
/// refresh loop would be defeated by concurrency.
///
/// Card identity and price persistence remain the caller's job. This actor only
/// persists its small request-count/backoff ledger in UserDefaults, keeping
/// SwiftData and card conclusions out of the transport layer.
actor ProductPriceService {
    struct Configuration: Sendable {
        var baseURL = URL(string: "https://api.justtcg.com/v1")!
        /// Free tier: 10 requests/minute. Paid tiers raise this, but a client
        /// that paces itself politely is correct on all of them.
        var minimumRequestInterval: TimeInterval = 6.5
        var timeout: TimeInterval = 20
        var resultLimit = 10
    }

    private let configuration: Configuration
    private let session: URLSession
    private var lastRequestAt: Date?
    /// Set slugs the vendor publishes, per game. Fetched once per refresh and
    /// used to verify a derived slug actually exists before it is sent.
    private var knownSlugs: [ProductCatalogIdentity.Game: [String]] = [:]

    init(configuration: Configuration = Configuration(), session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func beginRun() async {
        await ProductFallbackBudget.shared.beginRun()
    }

    func budgetSnapshot() async -> ProductFallbackBudget.Snapshot {
        await ProductFallbackBudget.shared.snapshot()
    }

    // MARK: - Quoting

    func quote(
        for subject: ProductPriceSubject,
        variant: PhysicalVariant?,
        at fetchedAt: Date = .now
    ) async -> ProductPriceOutcome {
        // An unmapped finish is refused before any request is made. Asking the
        // vendor about a Master Ball copy and taking whatever it returns is the
        // borrowing this whole layer exists to prevent.
        guard let printing = ProductFinish.printing(for: variant) else {
            return .noListingForVariant(vendorCardID: subject.vendorCardID)
        }
        guard PriceVendorCredentials.hasKey else { return .requestFailed }

        let game = ProductCatalogIdentity.game(for: subject.game, catalogID: subject.catalogID)

        do {
            let candidates: [ProductCard]
            var resolvedSlug: String?

            if let cardID = subject.vendorCardID {
                // Already resolved once. No search, no slug needed.
                candidates = try await fetchCards(query: [("cardId", cardID)])
                resolvedSlug = candidates.first?.set
            } else {
                let slugs = try await setSlugs(for: game)
                guard let slug = ProductCatalogIdentity.setSlug(
                    setName: subject.setName,
                    japaneseSetID: subject.japaneseSetID,
                    game: game,
                    knownSlugs: slugs
                ) else {
                    // No derivable set. Searching without one is exactly how a
                    // 1996 printing gets returned for a 2025 card.
                    return .noProductMatch
                }
                resolvedSlug = slug
                candidates = try await fetchCards(query: [
                    ("q", subject.name),
                    ("game", game.rawValue),
                    ("set", slug),
                    ("limit", String(configuration.resultLimit))
                ])
            }

            guard let slug = resolvedSlug else { return .noProductMatch }
            guard let card = candidates.first(where: {
                ProductCatalogIdentity.isSameCard(
                    requestedName: subject.name,
                    requestedNumber: subject.cardNumber,
                    requestedSetSlug: slug,
                    candidateName: $0.name,
                    candidateNumber: $0.printedNumber ?? "",
                    candidateSetSlug: $0.set ?? slug
                )
            }) else {
                return .noProductMatch
            }

            return price(from: card, printing: printing, at: fetchedAt)
        } catch is CancellationError {
            return .requestFailed
        } catch let error as ProductPriceError {
            switch error {
            case let .budgetReached(resetAt): return .budgetReached(resetAt: resetAt)
            case let .rateLimited(retryAt): return .rateLimited(retryAt: retryAt)
            case .invalidURL, .missingCredentials, .badResponse: return .requestFailed
            }
        } catch {
            return .requestFailed
        }
    }

    // MARK: - Price selection

    private func price(
        from card: ProductCard,
        printing: String,
        at fetchedAt: Date
    ) -> ProductPriceOutcome {
        // Near Mint explicitly, never the first entry. The variants array is not
        // ordered and not monotonic in condition — a live sample had Heavily
        // Played at $0.35 above Near Mint at $0.16 on the same card. Taking
        // whatever came first would quietly publish the wrong number.
        guard let match = ProductFinish.nearMintVariant(in: card.variants ?? [], printing: printing),
              let amount = match.price else {
            return .noListingForVariant(vendorCardID: card.id)
        }

        // The vendor omits a currency field on variants. Its prices are
        // TCGplayer-derived and quoted in dollars, so absence is read as USD —
        // but an explicit non-USD currency is refused rather than relabelled,
        // because mislabelling a currency is the failure this layer replaced.
        if let currency = match.currency,
           currency.caseInsensitiveCompare("USD") != .orderedSame {
            return .noListingForVariant(vendorCardID: card.id)
        }

        return .price(
            NormalizedPrice(
                unitMarketPriceUSD: amount,
                currencyCode: "USD",
                source: .justTCG,
                // Provenance carries the finish and the condition the number was
                // read at, so a mapping that later proves wrong can be found.
                sourceVariantID: match.variantId ?? "\(printing)#\(ProductFinish.condition)",
                sourceUpdatedAt: match.updatedAt,
                fetchedAt: fetchedAt
            ),
            vendorCardID: card.id
        )
    }

    // MARK: - Networking

    private func setSlugs(for game: ProductCatalogIdentity.Game) async throws -> [String] {
        if let cached = knownSlugs[game] { return cached }
        let response: ProductSetsResponse = try await get(
            path: "sets",
            query: [("game", game.rawValue)]
        )
        let slugs = response.data.compactMap(\.id)
        knownSlugs[game] = slugs
        return slugs
    }

    private func fetchCards(query: [(String, String)]) async throws -> [ProductCard] {
        let response: ProductCardsResponse = try await get(path: "cards", query: query)
        return response.data
    }

    private func get<T: Decodable>(path: String, query: [(String, String)]) async throws -> T {
        try await pace()

        guard var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw ProductPriceError.invalidURL
        }
        components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url else { throw ProductPriceError.invalidURL }

        guard let key = PriceVendorCredentials.key else { throw ProductPriceError.missingCredentials }

        var request = URLRequest(url: url)
        request.timeoutInterval = configuration.timeout
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        // Cloudflare fronts this API and rejects a default client User-Agent
        // with error 1010 — a 403 that reads exactly like an authentication
        // failure. `TCGdexService` sets one for the same reason.
        request.setValue("TradingCardScanner/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        switch await ProductFallbackBudget.shared.reserveRequest() {
        case .allowed:
            break
        case let .budgetReached(resetAt):
            throw ProductPriceError.budgetReached(resetAt)
        case let .rateLimited(retryAt):
            throw ProductPriceError.rateLimited(retryAt)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProductPriceError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 429 {
                let headerRetryAt = Self.retryDate(
                    from: http.value(forHTTPHeaderField: "Retry-After"),
                    now: .now
                )
                let retryAt: Date
                if let headerRetryAt {
                    retryAt = headerRetryAt
                } else {
                    retryAt = await ProductFallbackBudget.shared.nextResetDate()
                }
                await ProductFallbackBudget.shared.recordRateLimit(until: retryAt)
                throw ProductPriceError.rateLimited(retryAt)
            }
            throw ProductPriceError.badResponse
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    nonisolated static func retryDate(from value: String?, now: Date) -> Date? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = TimeInterval(trimmed), seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: trimmed)
    }

    /// Hold each request back far enough from the last that the tier's
    /// per-minute allowance is never the reason a refresh fails.
    private func pace() async throws {
        if let lastRequestAt {
            let elapsed = Date.now.timeIntervalSince(lastRequestAt)
            let remaining = configuration.minimumRequestInterval - elapsed
            if remaining > 0 {
                try await Task.sleep(for: .milliseconds(Int(remaining * 1000)))
            }
        }
        lastRequestAt = .now
    }
}

enum ProductPriceError: Error {
    case invalidURL
    case missingCredentials
    case badResponse
    case budgetReached(Date)
    case rateLimited(Date)
}

/// A conservative, persisted allowance for the vendor's free tier. Reservations
/// happen immediately before each HTTP request, so searches that require a set
/// lookup plus a card lookup consume two requests rather than pretending to be
/// one. The small headroom below the advertised 100/day protects manual checks
/// and vendor-side accounting differences.
actor ProductFallbackBudget {
    static let shared = ProductFallbackBudget()
    static let dailyLimit = 90
    static let perRunLimit = 90

    struct Snapshot: Equatable, Sendable {
        let usedToday: Int
        let remainingToday: Int
        let resetAt: Date
        let retryAt: Date?
    }

    enum Reservation: Equatable, Sendable {
        case allowed
        case budgetReached(resetAt: Date)
        case rateLimited(retryAt: Date)
    }

    private let defaults: UserDefaults
    private var runRequests = 0
    private let usedKey = "priceFallbackRequestsUsed"
    private let dayKey = "priceFallbackBudgetDay"
    private let blockedUntilKey = "priceFallbackBlockedUntil"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func beginRun() {
        runRequests = 0
        rolloverIfNeeded(now: .now)
    }

    func reserveRequest(now: Date = .now) -> Reservation {
        rolloverIfNeeded(now: now)
        if let retryAt = defaults.object(forKey: blockedUntilKey) as? Date, retryAt > now {
            return .rateLimited(retryAt: retryAt)
        }
        let resetAt = nextResetDate(after: now)
        let used = defaults.integer(forKey: usedKey)
        guard used < Self.dailyLimit, runRequests < Self.perRunLimit else {
            return .budgetReached(resetAt: resetAt)
        }
        defaults.set(used + 1, forKey: usedKey)
        runRequests += 1
        return .allowed
    }

    func recordRateLimit(until date: Date) {
        defaults.set(date, forKey: blockedUntilKey)
    }

    func snapshot(now: Date = .now) -> Snapshot {
        rolloverIfNeeded(now: now)
        let used = defaults.integer(forKey: usedKey)
        let retryAt = (defaults.object(forKey: blockedUntilKey) as? Date).flatMap { $0 > now ? $0 : nil }
        return Snapshot(
            usedToday: used,
            remainingToday: max(Self.dailyLimit - used, 0),
            resetAt: nextResetDate(after: now),
            retryAt: retryAt
        )
    }

    func nextResetDate() -> Date {
        nextResetDate(after: .now)
    }

    private func rolloverIfNeeded(now: Date) {
        let today = utcCalendar.startOfDay(for: now)
        let storedDay = defaults.object(forKey: dayKey) as? Date
        guard storedDay != today else { return }
        defaults.set(today, forKey: dayKey)
        defaults.set(0, forKey: usedKey)
        defaults.removeObject(forKey: blockedUntilKey)
        runRequests = 0
    }

    private func nextResetDate(after date: Date) -> Date {
        utcCalendar.date(byAdding: .day, value: 1, to: utcCalendar.startOfDay(for: date))
            ?? date.addingTimeInterval(24 * 60 * 60)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

// MARK: - Finish mapping

/// The vendor's printing vocabulary, mapped explicitly.
///
/// A finish with no entry here is not priced. That is the same rule the catalog
/// path follows, and it is why a parallel this build cannot name never inherits
/// a nearby finish's number.
enum ProductFinish {
    /// TCGplayer market price is effectively a Near Mint figure, so pinning it
    /// keeps fallback prices comparable to the catalog prices beside them.
    static let condition = "Near Mint"

    /// The Near Mint listing for one printing, selected by name rather than by
    /// position.
    ///
    /// The variants array is neither ordered nor monotonic in condition: a live
    /// response had Heavily Played at $0.35 sitting above Near Mint at $0.16 on
    /// the same card, and another had Lightly Played above Near Mint. Taking the
    /// first entry, or the highest, or the lowest, all publish a number that is
    /// not the one being claimed.
    static func nearMintVariant(in variants: [ProductVariant], printing: String) -> ProductVariant? {
        variants.first {
            $0.printing?.caseInsensitiveCompare(printing) == .orderedSame
                && $0.condition?.caseInsensitiveCompare(condition) == .orderedSame
        }
    }

    static func printing(for variant: PhysicalVariant?) -> String? {
        switch variant?.id {
        case PhysicalVariant.normal.id: return "Normal"
        case PhysicalVariant.holo.id: return "Holofoil"
        case PhysicalVariant.reverse.id: return "Reverse Holofoil"
        case PhysicalVariant.nonfoil.id: return "Normal"
        case PhysicalVariant.foil.id: return "Foil"
        case PhysicalVariant.etched.id: return "Etched Foil"
        // Deliberately absent: firstEdition and every ball pattern. The ball
        // patterns are already priced from the catalog, and 1st Edition appears
        // under several vendor spellings ("1st Edition - Japanese" among them)
        // that have not been verified against a real card.
        default: return nil
        }
    }
}

// MARK: - Wire format

private struct ProductSetsResponse: Decodable {
    let data: [ProductSet]
}

private struct ProductSet: Decodable {
    let id: String?
}

private struct ProductCardsResponse: Decodable {
    let data: [ProductCard]
}

struct ProductCard: Decodable, Sendable {
    let id: String?
    let name: String
    let set: String?
    /// Published under either spelling depending on the endpoint.
    let number: String?
    let collectorNumber: String?
    let variants: [ProductVariant]?

    var printedNumber: String? { number ?? collectorNumber }

    enum CodingKeys: String, CodingKey {
        case id, name, set, number, variants
        case collectorNumber = "collector_number"
    }
}

struct ProductVariant: Decodable, Sendable {
    let condition: String?
    let printing: String?
    let price: Double?
    /// Absent in observed responses; decoded so an explicit non-USD value can be
    /// refused rather than silently trusted.
    let currency: String?
    let variantId: String?
    let lastUpdated: Double?

    /// Published as a Unix timestamp when present.
    var updatedAt: Date? {
        lastUpdated.map { Date(timeIntervalSince1970: $0) }
    }

    enum CodingKeys: String, CodingKey {
        case condition, printing, price, currency, variantId, lastUpdated
    }
}
