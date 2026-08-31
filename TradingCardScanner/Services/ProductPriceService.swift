import Foundation

/// What the fallback was able to say about one physical variant.
///
/// The outcomes are kept apart because they mean different things to
/// the person reading the collection: a card the vendor has never heard of is a
/// matching problem, a card it carries but does not list in this finish is
/// genuinely unpriced, and a failed request is nothing at all.
enum ProductPriceOutcome: Equatable, Sendable {
    /// Both handles travel with the answer so the caller can cache them without
    /// paying for the search a second time.
    ///
    /// The *variant* id is the one that matters most: it identifies the exact
    /// printing and finish, which is what a batch request is built from. Holding
    /// it is what turns every later refresh into twenty-per-request batching
    /// instead of one search per card.
    case price(NormalizedPrice, vendorCardID: String?, vendorVariantID: String?)
    /// The product was found; it has no listing for this finish.
    case noListingForVariant(vendorCardID: String?)
    /// Nothing came back that passed identity checking.
    case noProductMatch
    /// No request was made because today's persisted allowance was exhausted.
    /// This is scheduling state, not evidence about the card.
    case budgetReached(resetAt: Date)
    /// The vendor asked the app to stop. No identity or price failure is cached.
    case rateLimited(retryAt: Date)
    case requestFailed

    var vendorCardID: String? {
        switch self {
        case let .price(_, id, _), let .noListingForVariant(id): return id
        case .noProductMatch, .budgetReached, .rateLimited, .requestFailed: return nil
        }
    }

    var vendorVariantID: String? {
        guard case let .price(_, _, variantID) = self else { return nil }
        return variantID
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
    /// The WotC edition this row belongs to, which selects both the vendor set
    /// and the printing spelling.
    var pokemonPrintRun: PokemonPrintRun?
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
    /// One identity-search client for collection fallback and Price Check so
    /// their request pacing remains a single conversation with the vendor.
    static let shared = ProductPriceService()

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
    private let pacer: JustTCGPacer
    /// The vendor's set directory, per game. Fetched once per refresh and used
    /// to find the vendor's set for a catalog set name.
    private var knownSets: [ProductCatalogIdentity.Game: ProductSetDirectory] = [:]

    init(
        configuration: Configuration = Configuration(),
        session: URLSession = .shared,
        pacer: JustTCGPacer = .shared
    ) {
        self.configuration = configuration
        self.session = session
        self.pacer = pacer
    }

    func budgetSnapshot() async -> ProductFallbackBudget.Snapshot {
        await ProductFallbackBudget.shared.snapshot()
    }

    // MARK: - Quoting

    func quote(
        for subject: ProductPriceSubject,
        variant: PhysicalVariant?,
        lane: JustTCGRequestLane = .background,
        at fetchedAt: Date = .now
    ) async -> ProductPriceOutcome {
        // An unmapped finish is refused before any request is made. Asking the
        // vendor about a Master Ball copy and taking whatever it returns is the
        // borrowing this whole layer exists to prevent.
        //
        // A row whose finish was never recorded is a different case and is not
        // refused: a CSV import routinely carries no finish, and refusing those
        // outright left a large part of an imported collection permanently
        // unpriceable. It is answered only when the vendor's listing is
        // unambiguous — see `ProductFinish.Requirement.unknown`.
        let game = ProductCatalogIdentity.game(for: subject.game, catalogID: subject.catalogID)
        guard let requirement = ProductFinish.requirement(
            for: variant,
            printRun: subject.pokemonPrintRun,
            isJapanese: game == .pokemonJapan
        ) else {
            return .noListingForVariant(vendorCardID: subject.vendorCardID)
        }
        guard PriceVendorCredentials.hasKey else { return .requestFailed }

        do {
            let candidates: [ProductCard]
            var resolvedSlug: String?

            if let cardID = subject.vendorCardID {
                // Already resolved once. No search, no slug needed.
                candidates = try await fetchCards(query: [("cardId", cardID)], lane: lane)
                resolvedSlug = candidates.first?.set
            } else {
                let directory = try await setDirectory(for: game, lane: lane)
                guard let plainSlug = ProductCatalogIdentity.setSlug(
                    setName: subject.setName,
                    japaneseSetID: subject.japaneseSetID,
                    game: game,
                    directory: directory
                ) else {
                    // No resolvable set. Searching without one is exactly how a
                    // 1996 printing gets returned for a 2025 card.
                    return .noProductMatch
                }
                // Base Set 1st Edition and Shadowless live in a different vendor
                // set from Base Set Unlimited, so the edition picks the set
                // before it picks the printing.
                guard let slug = ProductEdition.from(subject.pokemonPrintRun).setSlug(
                    plain: plainSlug,
                    knownSlugs: directory.slugs
                ) else {
                    return .noProductMatch
                }
                resolvedSlug = slug
                candidates = try await fetchCards(query: [
                    ("q", subject.name),
                    ("game", game.rawValue),
                    ("set", slug),
                    ("limit", String(configuration.resultLimit))
                ], lane: lane)
            }

            guard let slug = resolvedSlug else { return .noProductMatch }
            let numbered = candidates.filter {
                ProductCatalogIdentity.isSameCard(
                    requestedName: subject.name,
                    requestedNumber: subject.cardNumber,
                    requestedSetSlug: slug,
                    candidateName: $0.name,
                    candidateNumber: $0.printedNumber ?? "",
                    candidateSetSlug: $0.set ?? slug
                )
            }
            // Japanese cards carry no collector number at all — the vendor
            // publishes the literal `N/A` for every one of them — so a matcher
            // that requires numbers to agree could never match a single
            // Japanese card. Where the vendor states no number, name and set
            // are all the evidence there is, and it is accepted only when it
            // picks out exactly one card. Two candidates means the name is not
            // unique in the set and guessing between them is the failure this
            // layer exists to avoid.
            let unnumbered = candidates.filter {
                $0.printedNumber == nil
                    && ($0.set ?? slug).caseInsensitiveCompare(slug) == .orderedSame
                    && CatalogIdentityNormalization.namesMatch(
                        imported: subject.name,
                        catalog: $0.name
                    )
            }
            guard let card = numbered.first ?? (unnumbered.count == 1 ? unnumbered[0] : nil) else {
                return .noProductMatch
            }

            return price(from: card, requirement: requirement, at: fetchedAt)
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
        requirement: ProductFinish.Requirement,
        at fetchedAt: Date
    ) -> ProductPriceOutcome {
        // Near Mint explicitly, never the first entry. The variants array is not
        // ordered and not monotonic in condition — a live sample had Heavily
        // Played at $0.35 above Near Mint at $0.16 on the same card. Taking
        // whatever came first would quietly publish the wrong number.
        guard let match = ProductFinish.nearMintVariant(
                in: card.variants ?? [],
                requirement: requirement
              ),
              let amount = match.price else {
            return .noListingForVariant(vendorCardID: card.vendorID)
        }

        // The vendor omits a currency field on variants. Its prices are
        // TCGplayer-derived and quoted in dollars, so absence is read as USD —
        // but an explicit non-USD currency is refused rather than relabelled,
        // because mislabelling a currency is the failure this layer replaced.
        if let currency = match.currency,
           currency.caseInsensitiveCompare("USD") != .orderedSame {
            return .noListingForVariant(vendorCardID: card.vendorID)
        }

        return .price(
            NormalizedPrice(
                unitMarketPriceUSD: amount,
                currencyCode: "USD",
                source: .justTCG,
                // Provenance carries the finish and the condition the number was
                // read at, so a mapping that later proves wrong can be found.
                sourceVariantID: match.variantId
                    ?? "\(requirement.provenance)#\(ProductFinish.condition)",
                sourceUpdatedAt: match.updatedAt,
                fetchedAt: fetchedAt
            ),
            vendorCardID: card.vendorID,
            vendorVariantID: match.variantId
        )
    }

    // MARK: - Networking

    private func setDirectory(
        for game: ProductCatalogIdentity.Game,
        lane: JustTCGRequestLane
    ) async throws -> ProductSetDirectory {
        if let cached = knownSets[game] { return cached }
        let response: ProductSetsResponse = try await get(
            path: "sets",
            query: [("game", game.rawValue)],
            lane: lane
        )
        if let metadata = response.metadata {
            await ProductFallbackBudget.shared.syncFromServer(metadata)
        }
        let directory = ProductSetDirectory(
            sets: response.data.compactMap { set in
                set.id.map { (id: $0, name: set.name) }
            }
        )
        knownSets[game] = directory
        return directory
    }

    private func fetchCards(
        query: [(String, String)],
        lane: JustTCGRequestLane
    ) async throws -> [ProductCard] {
        let response: ProductCardsResponse = try await get(path: "cards", query: query, lane: lane)
        if let metadata = response.metadata {
            await ProductFallbackBudget.shared.syncFromServer(metadata)
        }
        return response.data
    }

    private func get<T: Decodable>(
        path: String,
        query: [(String, String)],
        lane: JustTCGRequestLane
    ) async throws -> T {
        try await pace(lane: lane)

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

        switch await ProductFallbackBudget.shared.reserveRequest(lane: lane) {
        case .allowed:
            break
        case .cancelled:
            throw CancellationError()
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
    private func pace(lane: JustTCGRequestLane) async throws {
        try await pacer.wait(
            lane: lane,
            minimumInterval: configuration.minimumRequestInterval
        )
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
///
/// # One allowance, not two
///
/// This delegates to `JustTCGRequestLedger` rather than keeping its own count.
/// The two must agree, because a refresh spends from both: the batched pass goes
/// through `JustTCGTransport`, and the identity-resolution pass comes through
/// here. Two independent counters, each allowing 95 a day, would spend up to 190
/// against a real limit of 100 — and the user would meet that as a wall of 429s
/// rather than as an honest "budget reached".
actor ProductFallbackBudget {
    static let shared = ProductFallbackBudget()
    static var dailyLimit: Int { JustTCGQuota.dailyHardLimit }

    struct Snapshot: Equatable, Sendable {
        let usedToday: Int
        let remainingToday: Int
        let resetAt: Date
        let retryAt: Date?
    }

    enum Reservation: Equatable, Sendable {
        case allowed
        case cancelled
        case budgetReached(resetAt: Date)
        case rateLimited(retryAt: Date)
    }

    private let ledger: JustTCGRequestLedger

    init(defaults: UserDefaults = .standard) {
        self.ledger = JustTCGRequestLedger(defaults: defaults)
    }

    /// Identity resolution can be interactive (Price Check) or background (a
    /// scheduled refresh). The caller's lane must govern both pacing and quota,
    /// otherwise fallback work would consume the interactive reserve.
    func reserveRequest(
        now: Date = .now,
        lane: JustTCGRequestLane = .interactive
    ) -> Reservation {
        guard !Task.isCancelled else { return .cancelled }
        switch ledger.reserve(lane: lane, now: now) {
        case .allowed:
            return .allowed
        case let .dailyReached(resetAt), let .monthlyReached(resetAt):
            return .budgetReached(resetAt: resetAt)
        case let .rateLimited(retryAt):
            return .rateLimited(retryAt: retryAt)
        }
    }

    func recordRateLimit(until date: Date) {
        ledger.recordRateLimit(until: date)
    }

    func syncFromServer(_ metadata: JustTCGQuotaMetadata) {
        ledger.syncFromServer(metadata)
    }

    func snapshot(now: Date = .now) -> Snapshot {
        let snapshot = ledger.snapshot(now: now)
        return Snapshot(
            usedToday: snapshot.usedToday,
            remainingToday: snapshot.remainingToday,
            resetAt: snapshot.dailyResetAt,
            retryAt: snapshot.retryAt
        )
    }

    func nextResetDate() -> Date {
        ledger.snapshot(now: .now).dailyResetAt
    }
}

// MARK: - Finish mapping

/// The vendor's printing vocabulary, mapped explicitly.
///
/// A finish with no entry here is not priced. That is the same rule the catalog
/// path follows, and it is why a parallel this build cannot name never inherits
/// a nearby finish's number.
/// How the vendor names WotC-era editions.
///
/// Verified against the live API rather than assumed, because this is the
/// mapping whose absence kept every 1st Edition, Shadowless and Unlimited card
/// out of the fallback entirely.
///
/// Two different shapes, and both are real:
///
/// - **Split sets** — Jungle, Fossil, Team Rocket, the Gym pair, the four Neo
///   sets — keep both runs in one set and qualify the *printing*:
///   `1st Edition Holofoil` and `Unlimited Holofoil`, or bare `1st Edition` and
///   `Unlimited` for a card with no foil treatment.
/// - **Base Set** is split by *set* instead. `base-set-pokemon` is the shadowed
///   Unlimited run and prints plain `Holofoil`; `base-set-shadowless-pokemon`
///   holds both 1st Edition and Shadowless Unlimited, qualified by printing.
///
/// The e-card sets — Expedition, Aquapolis, Skyridge — publish no edition
/// qualifier at all: Skyridge carries only `Holofoil`, `Reverse Holofoil` and
/// `Normal`. Browse still splits those into virtual runs, so a 1st Edition
/// e-card card asks for a printing the vendor does not publish and stays
/// unpriced. That is the correct outcome: the vendor has no edition-specific
/// number for it, and the premium a 1st Edition commands is exactly what would
/// be lost by borrowing the undifferentiated one.
enum ProductEdition: Equatable, Sendable {
    /// No WotC print run on the row.
    case unspecified
    case firstEdition
    /// The ordinary run. Accepts an unqualified printing as well as an
    /// explicitly `Unlimited`-qualified one, because the vendor uses the first
    /// form for sets it does not split and the second for sets it does.
    case unlimited
    /// Shadowless, which the vendor models as the Unlimited run *inside* the
    /// Base Set (Shadowless) set.
    case shadowlessUnlimited

    static func from(_ run: PokemonPrintRun?) -> ProductEdition {
        switch run {
        case .firstEdition: return .firstEdition
        case .shadowless: return .shadowlessUnlimited
        case .unlimited: return .unlimited
        case nil: return .unspecified
        }
    }

    private static let firstEditionPrefix = "1st Edition"
    private static let unlimitedPrefix = "Unlimited"

    /// The vendor printings that may be read for a known finish, best-first.
    ///
    /// - Parameter isJapanese: Japanese printings carry a ` - Japanese` suffix —
    ///   `Holofoil - Japanese`, `Normal - Japanese`. Without it every Japanese
    ///   card in the collection asked for a printing the vendor does not
    ///   publish and came back unpriced, which was the entire Japanese
    ///   catalogue rather than an edge case.
    ///
    ///   Japanese has no edition qualifier at all: the vendor separates early
    ///   Japanese prints by *set* — "Expansion Pack (No Rarity)" beside
    ///   "Expansion Pack" — not by printing. So a Japanese row carrying a 1st
    ///   Edition run asks for `1st Edition Holofoil - Japanese`, finds nothing,
    ///   and stays unpriced. That is the honest answer: there is no Japanese
    ///   1st Edition price to read, and the ordinary Japanese number is not it.
    func printings(finish: String, isJapanese: Bool = false) -> [String] {
        localized(printings(finish: finish), isJapanese: isJapanese)
    }

    private func localized(_ printings: [String], isJapanese: Bool) -> [String] {
        isJapanese ? printings.map { "\($0) - Japanese" } : printings
    }

    private func printings(finish: String) -> [String] {
        // A card with no foil treatment carries the bare edition word rather
        // than `1st Edition Normal`. Both spellings are accepted; only one of
        // them will exist.
        func qualified(_ prefix: String) -> [String] {
            finish == "Normal"
                ? ["\(prefix) \(finish)", prefix]
                : ["\(prefix) \(finish)"]
        }

        switch self {
        case .unspecified:
            return [finish]
        case .firstEdition:
            return qualified(Self.firstEditionPrefix)
        case .shadowlessUnlimited:
            return qualified(Self.unlimitedPrefix)
        case .unlimited:
            return [finish] + qualified(Self.unlimitedPrefix)
        }
    }

    /// Whether a printing belongs to this edition, for a row whose finish was
    /// never recorded.
    func admits(printing: String) -> Bool {
        let isFirstEdition = printing.localizedCaseInsensitiveContains(Self.firstEditionPrefix)
        switch self {
        case .unspecified: return true
        case .firstEdition: return isFirstEdition
        case .shadowlessUnlimited:
            return !isFirstEdition
                && printing.localizedCaseInsensitiveContains(Self.unlimitedPrefix)
        case .unlimited:
            // Plain and `Unlimited`-qualified both qualify; 1st Edition never
            // does, and that is the only distinction that must not be crossed.
            return !isFirstEdition
        }
    }

    /// The vendor set to search, given the slug derived from the card's set name.
    ///
    /// Returns nil when this edition cannot exist for the set — asking for a
    /// Shadowless printing of a set the vendor never split would otherwise land
    /// on the ordinary run's price.
    func setSlug(plain: String, knownSlugs: [String]) -> String? {
        switch self {
        case .unspecified, .unlimited:
            return plain
        case .firstEdition:
            // Base Set's 1st Edition lives in the shadowless set; every other
            // set keeps both runs together.
            return Self.shadowlessSlug(for: plain, in: knownSlugs) ?? plain
        case .shadowlessUnlimited:
            return Self.shadowlessSlug(for: plain, in: knownSlugs)
        }
    }

    private static func shadowlessSlug(for plain: String, in knownSlugs: [String]) -> String? {
        let suffix = "-\(ProductCatalogIdentity.Game.pokemon.rawValue)"
        guard plain.hasSuffix(suffix) else { return nil }
        let candidate = plain.dropLast(suffix.count) + "-shadowless" + suffix
        return knownSlugs.contains(String(candidate)) ? String(candidate) : nil
    }
}

enum ProductFinish {
    /// TCGplayer market price is effectively a Near Mint figure, so pinning it
    /// keeps fallback prices comparable to the catalog prices beside them.
    static let condition = "Near Mint"

    /// Which listing on a returned card the app is entitled to read.
    enum Requirement: Equatable, Sendable {
        /// The row's finish is known. Any of these vendor printings names it;
        /// which spelling exists depends on whether the vendor splits the set.
        case printings([String])
        /// The row's finish was never recorded — a CSV import, or a scan the
        /// resolver could not settle. Answerable only when the edition's own
        /// listings leave exactly one candidate.
        case unknownFinish(ProductEdition)

        /// What goes in the stored price's provenance.
        var provenance: String {
            switch self {
            case let .printings(values): return values.first ?? "unknown"
            case .unknownFinish: return "unspecified-finish"
            }
        }
    }

    /// What may be read for a given finish and print run, or nil when the finish
    /// is one this build refuses to price.
    static func requirement(
        for variant: PhysicalVariant?,
        printRun: PokemonPrintRun? = nil,
        isJapanese: Bool = false
    ) -> Requirement? {
        let edition = ProductEdition.from(printRun)
        guard let variant else { return .unknownFinish(edition) }
        return printing(for: variant).map {
            Requirement.printings(edition.printings(finish: $0, isJapanese: isJapanese))
        }
    }

    /// The Near Mint listing to read, selected by name rather than by position.
    ///
    /// The variants array is neither ordered nor monotonic in condition: a live
    /// response had Heavily Played at $0.35 sitting above Near Mint at $0.16 on
    /// the same card, and another had Lightly Played above Near Mint. Taking the
    /// first entry, or the highest, or the lowest, all publish a number that is
    /// not the one being claimed.
    static func nearMintVariant(
        in variants: [ProductVariant],
        requirement: Requirement
    ) -> ProductVariant? {
        let nearMint = variants.filter {
            $0.condition?.caseInsensitiveCompare(condition) == .orderedSame
        }
        switch requirement {
        case let .printings(printings):
            // Best-first: the exact spelling the vendor uses for this set wins,
            // and an edition-qualified name is never satisfied by a plain one.
            for printing in printings {
                if let match = nearMint.first(where: {
                    $0.printing?.caseInsensitiveCompare(printing) == .orderedSame
                }) {
                    return match
                }
            }
            return nil
        case let .unknownFinish(edition):
            // One Near Mint listing within the edition is this card's price
            // whatever it is called. Several means the finish genuinely
            // matters, and picking between them is how a foil's price lands on
            // a plain copy.
            let eligible = nearMint.filter { edition.admits(printing: $0.printing ?? "") }
            return eligible.count == 1 ? eligible[0] : nil
        }
    }

    static func printing(for variant: PhysicalVariant?) -> String? {
        if let id = variant?.id,
           let stamped = PokemonStampedReleaseCatalog.entry(variantID: id) {
            return stamped.printing
        }
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
    let metadata: JustTCGQuotaMetadata?

    enum CodingKeys: String, CodingKey {
        case data
        case metadata = "_metadata"
    }
}

private struct ProductSet: Decodable {
    let id: String?
    /// The published display name — `SV: Prismatic Evolutions`, `EX Dragon`.
    /// This is what a catalog set name is matched against; discarding it was
    /// what left two thirds of the catalogue unresolvable.
    let name: String?
}

private struct ProductCardsResponse: Decodable {
    let data: [ProductCard]
    let metadata: JustTCGQuotaMetadata?

    enum CodingKeys: String, CodingKey {
        case data
        case metadata = "_metadata"
    }
}

struct ProductCard: Decodable, Sendable {
    /// The human-readable slug, e.g. `pokemon-arceus-charizard-holo-rare`.
    let id: String?
    /// The stable UUID. Decoded because the vendor recommends it as the primary
    /// key, but the handle below stays on the slug: `cardId=<slug>` is verified
    /// to return the card, and the uuid form is not yet verified.
    let uuid: String?
    let name: String
    let set: String?
    /// Published under either spelling depending on the endpoint.
    let number: String?
    let collectorNumber: String?
    let variants: [ProductVariant]?

    /// The vendor uses the literal `N/A` for cards without a collector number.
    /// Normalize that sentinel at the model boundary so matching can use the
    /// same unnumbered-card path as catalog responses.
    var printedNumber: String? {
        guard let raw = number ?? collectorNumber else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.caseInsensitiveCompare("N/A") != .orderedSame else {
            return nil
        }
        return value
    }

    /// The handle to persist and to send back as `cardId`.
    var vendorID: String? { id ?? uuid }

    enum CodingKeys: String, CodingKey {
        case id, uuid, name, set, number, variants
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

    init(
        condition: String?,
        printing: String?,
        price: Double?,
        currency: String? = nil,
        variantId: String? = nil,
        lastUpdated: Double? = nil
    ) {
        self.condition = condition
        self.printing = printing
        self.price = price
        self.currency = currency
        self.variantId = variantId
        self.lastUpdated = lastUpdated
    }

    private enum CodingKeys: String, CodingKey {
        case condition, printing, price, currency
        case uuid, id, variantId
        case lastUpdated
        case lastUpdatedSnakeCase = "last_updated"
    }

    /// Decoded by hand because the identifier this type exists to capture is not
    /// published under the name it is requested by.
    ///
    /// `variantId` is the *request parameter*; the *response field* is `uuid`.
    /// `JustTCGVariant` already accounts for this — see the pinned contract test
    /// — but this type, which is what the identity-resolution pass actually
    /// decodes, was still asking for `variantId` and therefore always got nil.
    /// A nil variant handle is never persisted, so no card ever became
    /// batchable and every refresh re-paid for a search it had already done.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        condition = try container.decodeIfPresent(String.self, forKey: .condition)
        printing = try container.decodeIfPresent(String.self, forKey: .printing)
        price = try container.decodeIfPresent(Double.self, forKey: .price)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        variantId = try container.decodeIfPresent(String.self, forKey: .uuid)
            ?? container.decodeIfPresent(String.self, forKey: .variantId)
            ?? container.decodeIfPresent(String.self, forKey: .id)
        lastUpdated = try container.decodeIfPresent(Double.self, forKey: .lastUpdated)
            ?? container.decodeIfPresent(Double.self, forKey: .lastUpdatedSnakeCase)
    }
}
