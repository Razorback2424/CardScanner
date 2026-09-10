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
    /// A value projection kept deliberately exhaustive. It is not another
    /// identity boundary; it is the checklist every derived lookup/match
    /// projection must consume. The structural test mirrors these stored
    /// fields so a future discriminator cannot disappear silently.
    struct Projection: Hashable, Sendable {
        let name: String
        let setName: String
        let collectorNumber: String
        let catalogID: String?
        let pokemonPrintRun: PokemonPrintRun?

        var groupingValues: [String] {
            [
                setName,
                collectorNumber,
                name,
                catalogID ?? "none",
                pokemonPrintRun?.rawValue ?? "none"
            ]
        }

        var values: [String] {
            [
                name,
                setName,
                collectorNumber,
                catalogID ?? "none",
                pokemonPrintRun?.rawValue ?? "none"
            ]
        }
    }

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

    var exhaustiveProjection: Projection {
        Projection(
            name: name,
            setName: setName,
            collectorNumber: collectorNumber,
            catalogID: catalogID,
            pokemonPrintRun: pokemonPrintRun
        )
    }

    /// Identifies the underlying card, so every owned grade of it shares one
    /// request.
    func groupingKey(game: CardGame) -> String {
        ([vendorGame(for: game).rawValue] + exhaustiveProjection.groupingValues)
            .map { $0.lowercased() }
            .joined(separator: "|")
    }

    func matches(
        _ card: JustTCGCard,
        game: CardGame,
        expectedSetSlug: String? = nil
    ) -> Bool {
        let projection = exhaustiveProjection

        if let expectedSetSlug {
            guard let candidateGame = card.game,
                  candidateGame.caseInsensitiveCompare(vendorGame(for: game).rawValue) == .orderedSame,
                  let candidateSet = card.set,
                  candidateSet.caseInsensitiveCompare(expectedSetSlug) == .orderedSame
            else { return false }
        } else if let candidateGame = card.game,
                  !candidateGame.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  candidateGame.caseInsensitiveCompare(vendorGame(for: game).rawValue) != .orderedSame {
            return false
        }

        guard let candidateName = card.name else { return false }
        guard CatalogIdentityNormalization.namesMatch(
            imported: projection.name,
            catalog: candidateName
        ) else { return false }
        guard CatalogIdentityNormalization.canonicalSetName(projection.setName, game: game)
            == CatalogIdentityNormalization.canonicalSetName(card.setName ?? "", game: game)
        else { return false }

        let requestedNumber = Self.normalizedCollectorNumber(projection.collectorNumber)
        let candidateNumber = card.printedNumber.flatMap(Self.normalizedCollectorNumber)
        switch (requestedNumber, candidateNumber) {
        case let (requested?, candidate?):
            return requested == candidate
        case (nil, nil):
            return projection.collectorNumber
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        default:
            // One side omitted a discriminator. It is not safe to widen a
            // numbered graded lookup to an unnumbered product, or vice versa.
            return false
        }
    }

    /// The card and its variant are the external product boundary. Nothing
    /// from a graded response becomes a durable handle or price until both the
    /// card identity and the variant's declared print run have passed here.
    func matches(
        _ card: JustTCGCard,
        variant: JustTCGVariant,
        game: CardGame,
        expectedSetSlug: String? = nil
    ) -> Bool {
        guard matches(card, game: game, expectedSetSlug: expectedSetSlug),
              variant.type?.caseInsensitiveCompare("graded") == .orderedSame
        else { return false }

        guard let pokemonPrintRun else { return true }
        guard let printing = variant.printing else { return false }
        return ProductEdition.from(pokemonPrintRun).admits(printing: printing)
    }

    private static func normalizedCollectorNumber(_ value: String) -> [String]? {
        let parts = value
            .split(separator: "/", omittingEmptySubsequences: false)
            .map {
                let component = $0
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                guard !component.isEmpty else { return "" }
                return Int(component).map(String.init) ?? component
            }
        guard parts.count <= 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return parts
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
        if companies.count == 1,
           let company = companies.first,
           let vendorCompany = vendorCompanyValue(company) {
            query.append(("grading_company", vendorCompany))
            if let grade = normalizedGradeFilter(grades) {
                query.append(("grade", grade))
            }
        }
        return query
    }

    /// JustTCG documents the company filter with uppercase tokens. TAG is a
    /// scanner-recognised grader, but it is not one of the vendor's six filter
    /// values; leaving the filter off is safer than turning a TAG refresh into
    /// an undocumented empty result.
    private static func vendorCompanyValue(_ company: GradingCompany) -> String? {
        switch company {
        case .tag:
            return nil
        case .psa, .bgs, .cgc, .bccg, .bvg, .sgc:
            return company.label
        }
    }

    /// The API accepts bare numeric grades, not persisted display strings.
    /// Invalid or named grades (including Authentic) intentionally produce no
    /// grade filter, so a refresh can still inspect the returned variants.
    static func normalizedVendorGrade(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let value = Double(trimmed),
              value.isFinite else { return nil }
        if value == value.rounded() {
            guard let integer = Int(exactly: value) else { return nil }
            return String(integer)
        }
        return String(value)
    }

    private static func normalizedGradeFilter(_ grades: Set<String>) -> String? {
        guard !grades.isEmpty else { return nil }
        let normalized = grades.compactMap(normalizedVendorGrade)
        // If one owned row contains an unrecognised display string, omit the
        // whole narrowing filter rather than silently excluding that row.
        guard normalized.count == grades.count else { return nil }
        let unique = Set(normalized)
        return unique.sorted {
            (Double($0) ?? .greatestFiniteMagnitude)
                < (Double($1) ?? .greatestFiniteMagnitude)
        }
        .joined(separator: ",")
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
    ///
    /// The variants are found by set and name, not by `cardId`. v2 **ignores**
    /// that parameter and answers with a browse:
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
        if identity.pokemonPrintRun != nil, setSlug == nil {
            // A known print run without a trustworthy vendor set projection is
            // ambiguous. Do not issue a browse request whose first result could
            // become an authoritative slab binding.
            return .noProductMatch
        }
        let query = Self.requestQuery(
            identity: identity,
            game: game,
            setSlug: setSlug,
            companies: companies,
            grades: grades
        )

        let response: GradedResponse = try await transport.get(
            "v2/cards",
            query: query,
            lane: lane
        )

        // Only cards that are demonstrably the one asked for.
        let matchingCards = response.data.filter {
            identity.matches($0, game: game, expectedSetSlug: setSlug)
        }
        var variants: [GradedVariant] = []
        for card in matchingCards {
            for variant in card.variants ?? [] {
                guard identity.matches(
                        card,
                        variant: variant,
                        game: game,
                        expectedSetSlug: setSlug
                    ),
                      let id = variant.variantId,
                      let grading = variant.grading,
                      let company = grading.gradingCompany else {
                    continue
                }
                variants.append(GradedVariant(
                    id: id,
                    // Kept so a later refresh can find this slab again without
                    // paying to resolve the card a second time.
                    cardID: card.uuid ?? card.id,
                    company: company,
                    grade: grading.cardGrade,
                    canonical: grading.canonical,
                    // `null` is a real answer: the vendor does not manufacture a
                    // number for every grader/grade permutation, and an absent
                    // price must read as "no reliable market price" rather than
                    // as zero.
                    marketPriceUSD: variant.marketPriceUSD,
                    updatedAt: variant.updatedAt
                ))
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

    /// The documented graders and numeric grades a set of owned slabs covers,
    /// so a refresh can narrow the request without sending an undocumented TAG
    /// company or a persisted display string such as `Authentic`.
    static func ownedFilters(
        for cards: [CollectedCard]
    ) -> (companies: Set<GradingCompany>, grades: Set<String>) {
        var companies: Set<GradingCompany> = []
        var grades: Set<String> = []
        for card in cards where card.itemKind == .gradedCard {
            if let company = card.gradingCompany,
               vendorCompanyValue(company) != nil {
                companies.insert(company)
            }
            if let grade = normalizedVendorGrade(card.gradeRaw) {
                grades.insert(grade)
            }
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
