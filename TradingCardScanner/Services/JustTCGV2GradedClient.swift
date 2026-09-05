import Foundation

/// Graded slab pricing, from the `/v2/cards` beta.
///
/// Isolated behind its own type on purpose. v2 is in public beta and its schema
/// may move; keeping its decoding here means a breaking change lands in one file
/// rather than across the collection layer. It is also the reason graded prices
/// are labelled as beta wherever they are shown.
///
/// ## Why this does not batch yet
///
/// The batching research establishes `POST /v1/cards` for v1 variants. It does
/// **not** establish that a v2 graded variant UUID may be passed as `variantId`
/// to that endpoint, nor that `/v2/cards` exposes its own POST batching. Until
/// the contract slice answers that, graded refresh groups by underlying card and
/// asks once per card with `graded=only`.
///
/// The interface deliberately hides which of those it is doing, so moving graded
/// work onto batching later changes this file and nothing else.
/// Enough of a card to recognise it in a v2 response.
///
/// Collector number carries the check: a set can hold two cards with the same
/// name, but not at the same number.
struct GradedCardIdentity: Hashable, Sendable {
    let name: String
    let setName: String
    let collectorNumber: String
    let catalogID: String?
    let pokemonPrintRun: PokemonPrintRun?

    init(
        name: String,
        setName: String,
        collectorNumber: String,
        catalogID: String? = nil,
        pokemonPrintRun: PokemonPrintRun? = nil
    ) {
        self.name = name
        self.setName = setName
        self.collectorNumber = collectorNumber
        self.catalogID = catalogID
        self.pokemonPrintRun = pokemonPrintRun
    }

    init(_ card: IdentifiedCard, pokemonPrintRun: PokemonPrintRun? = nil) {
        self.init(
            name: card.name,
            setName: card.setName,
            collectorNumber: card.cardNumber,
            catalogID: card.providerID,
            pokemonPrintRun: pokemonPrintRun
        )
    }

    func vendorGame(for game: CardGame) -> ProductCatalogIdentity.Game {
        ProductCatalogIdentity.game(for: game, catalogID: catalogID)
    }

    var japaneseSetID: String? {
        catalogID.flatMap(PriceFallbackQuoteResolver.japaneseSetID(forCatalogCardID:))
    }

    /// Identifies the underlying card, so every owned grade of it shares one
    /// request.
    func groupingKey(game: CardGame) -> String {
        [vendorGame(for: game).rawValue, setName, collectorNumber, name]
            .map { $0.lowercased() }
            .joined(separator: "|")
    }

    func matches(_ card: JustTCGCard, game: CardGame) -> Bool {
        guard let candidateName = card.name else { return false }
        guard CatalogIdentityNormalization.namesMatch(
            imported: name,
            catalog: candidateName
        ) else { return false }
        // A number is only compared when both sides publish one; sealed rows and
        // some promos carry none.
        if let candidateNumber = card.printedNumber, !collectorNumber.isEmpty {
            return CatalogIdentityNormalization.localNumber(candidateNumber)
                == CatalogIdentityNormalization.localNumber(collectorNumber)
        }
        return CatalogIdentityNormalization.canonicalSetName(setName, game: game)
            == CatalogIdentityNormalization.canonicalSetName(card.setName ?? "", game: game)
    }
}

enum GradedVariantLookupResult: Equatable, Sendable {
    case matched([GradedVariant])
    case cardFoundWithoutGradedVariants
    case noProductMatch
}

struct JustTCGV2GradedClient: Sendable {
    static let apiVersion = "v2"

    private let transport: JustTCGTransport
    private let setDirectoryProvider: ProductSetDirectoryProvider

    init(
        transport: JustTCGTransport,
        setDirectoryProvider: ProductSetDirectoryProvider = .shared
    ) {
        self.transport = transport
        self.setDirectoryProvider = setDirectoryProvider
    }

    /// Keep the outgoing query testable as a value. A missing set is a
    /// deliberate fallback, not a fabricated slug derived from catalog text.
    static func requestQuery(
        identity: GradedCardIdentity,
        game: CardGame,
        setSlug: String?,
        companies: Set<GradingCompany> = [],
        grades: Set<String> = []
    ) -> [(String, String)] {
        var query: [(String, String)] = [
            ("game", identity.vendorGame(for: game).rawValue),
            ("q", identity.name),
            ("graded", "only"),
            ("include_price_history", "false"),
            // A missing set is a deliberate browse fallback, not permission to
            // download an unbounded game-wide response. The vendor's free tier
            // accepts at most this page size; identity matching still decides
            // whether any returned card is the requested one.
            ("limit", String(JustTCGQuota.maximumPageSize))
        ]
        if let setSlug {
            query.insert(("set", setSlug), at: 1)
        }
        if companies.count == 1, let company = companies.first {
            query.append(("grading_company", company.rawValue))
            if grades.count == 1, let grade = grades.first {
                query.append(("grade", grade))
            }
        }
        return query
    }

    /// Resolve the vendor set before constructing the graded request. An empty
    /// directory is not evidence for a derived slug, so it uses the safe
    /// unfiltered fallback and lets identity matching decide what returned.
    static func resolvedSetSlug(
        identity: GradedCardIdentity,
        game: CardGame,
        directory: ProductSetDirectory
    ) -> String? {
        guard !directory.slugs.isEmpty else { return nil }
        let vendorGame = identity.vendorGame(for: game)
        guard let plain = ProductCatalogIdentity.setSlug(
            setName: identity.setName,
            japaneseSetID: identity.japaneseSetID,
            game: vendorGame,
            directory: directory
        ) else {
            return nil
        }
        return ProductEdition.from(identity.pokemonPrintRun).setSlug(
            plain: plain,
            knownSlugs: directory.slugs
        )
    }

    /// Every graded variant of one card, narrowed to what the user actually owns.
    ///
    /// `graded=only` rather than `graded=include`: including raw results costs a
    /// surcharge and returns data the raw path already has. Filtering to the
    /// owned graders and grades keeps the response small — a card can have well
    /// over a hundred grader/grade permutations, almost none of them owned.
    /// The graded variants of one card, found by set and name.
    ///
    /// Not by `cardId`. v2 **ignores** that parameter and answers with a browse:
    /// asking for `cardId=base1-4` returns twenty arbitrary graded cards from
    /// across the game — Charizard Star, Shining Celebi, Rayquaza VMAX — and
    /// nothing in the response says it was not a hit. The existing note that a
    /// `cardId` "is not enough to stop it being treated as a browse" was
    /// describing exactly this, and the `game` parameter added to satisfy the
    /// browse only made the browse legal.
    ///
    /// Set plus name narrows it to one card, verified against `identity` before
    /// anything is returned, so a browse can never be mistaken for a match.
    func lookup(
        identity: GradedCardIdentity,
        game: CardGame,
        companies: Set<GradingCompany> = [],
        grades: Set<String> = [],
        lane: JustTCGRequestLane = .interactive
    ) async throws -> GradedVariantLookupResult {
        let vendorGame = identity.vendorGame(for: game)
        let directory = try await setDirectoryProvider.directory(for: vendorGame) { [transport] in
            let response: GradedSetsResponse = try await transport.get(
                "v1/sets",
                query: [("game", vendorGame.rawValue)],
                lane: lane
            )
            return ProductSetDirectory(
                sets: response.data.compactMap { set in
                    set.id.map { (id: $0, name: set.name) }
                }
            )
        }
        let setSlug = Self.resolvedSetSlug(
            identity: identity,
            game: game,
            directory: directory
        )
        var query = Self.requestQuery(
            identity: identity,
            game: game,
            setSlug: setSlug
        )
        // The parameter is `grading_company`, not `company`: sending the latter
        // is accepted right up until a `grade` accompanies it, at which point v2
        // answers 400 — "grade requires grading_company". And only a single
        // value of each is sent, because comma-separated lists are not verified
        // here and a filter the vendor reads differently than intended would
        // silently drop owned slabs from the response rather than erroring.
        // Omitting both returns every graded variant, which is the same one
        // request; the caller matches on its stored handle regardless.
        if companies.count == 1, let company = companies.first {
            query.append(("grading_company", company.rawValue))
            if grades.count == 1, let grade = grades.first {
                query.append(("grade", grade))
            }
        }

        let response: GradedResponse = try await transport.get(
            "v2/cards",
            query: query,
            lane: lane
        )

        // Only cards that are demonstrably the one asked for.
        let matchingCards = response.data.filter { identity.matches($0, game: game) }
        let variants = matchingCards.flatMap { card in
            (card.variants ?? []).compactMap { variant -> GradedVariant? in
                guard let id = variant.variantId,
                      let grading = variant.grading,
                      let company = grading.gradingCompany else {
                    return nil
                }
                return GradedVariant(
                    id: id,
                    // Kept so a later refresh can find this slab again without
                    // paying to resolve the card a second time.
                    cardID: card.uuid ?? card.id,
                    company: company,
                    grade: grading.cardGrade,
                    // `null` is a real answer: the vendor does not manufacture a
                    // number for every grader/grade permutation, and an absent
                    // price must read as "no reliable market price" rather than
                    // as zero.
                    marketPriceUSD: variant.marketPriceUSD,
                    updatedAt: variant.updatedAt
                )
            }
        }
        if !variants.isEmpty { return .matched(variants) }
        return matchingCards.isEmpty
            ? .noProductMatch
            : .cardFoundWithoutGradedVariants
    }

    func gradedVariants(
        identity: GradedCardIdentity,
        game: CardGame,
        companies: Set<GradingCompany> = [],
        grades: Set<String> = [],
        lane: JustTCGRequestLane = .interactive
    ) async throws -> [GradedVariant] {
        switch try await lookup(
            identity: identity,
            game: game,
            companies: companies,
            grades: grades,
            lane: lane
        ) {
        case let .matched(variants): return variants
        case .cardFoundWithoutGradedVariants, .noProductMatch: return []
        }
    }

    /// The graders and grades a set of owned slabs covers, so a refresh asks
    /// only about those.
    static func ownedFilters(
        for cards: [CollectedCard]
    ) -> (companies: Set<GradingCompany>, grades: Set<String>) {
        var companies: Set<GradingCompany> = []
        var grades: Set<String> = []
        for card in cards where card.itemKind == .gradedCard {
            if let company = card.gradingCompany { companies.insert(company) }
            if let grade = card.gradeRaw { grades.insert(grade) }
        }
        return (companies, grades)
    }

    private struct GradedResponse: Decodable {
        let data: [JustTCGCard]
        let metadata: JustTCGQuotaMetadata?

        enum CodingKeys: String, CodingKey {
            case data
            case metadata = "_metadata"
        }
    }

    private struct GradedSetsResponse: Decodable {
        let data: [GradedSet]
    }

    private struct GradedSet: Decodable {
        let id: String?
        let name: String?
    }
}
