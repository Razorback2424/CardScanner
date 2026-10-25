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
/// v2 batch supports known slab IDs but does not accept graded discovery
/// filters and returns only priced graded variants. This path also needs to
/// distinguish a known card without slab history, so it groups by underlying
/// card and uses GET with `graded=only`.
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
        let finish: PhysicalVariant?

        var groupingValues: [String] {
            [
                setName,
                collectorNumber,
                name,
                catalogID ?? "none",
                pokemonPrintRun?.rawValue ?? "none",
                finish?.id ?? "none"
            ]
        }

        var values: [String] {
            [
                name,
                setName,
                collectorNumber,
                catalogID ?? "none",
                pokemonPrintRun?.rawValue ?? "none",
                finish?.id ?? "none"
            ]
        }
    }

    let name: String
    let setName: String
    let collectorNumber: String
    let catalogID: String?
    let pokemonPrintRun: PokemonPrintRun?
    let finish: PhysicalVariant?

    init(
        name: String,
        setName: String,
        collectorNumber: String,
        catalogID: String? = nil,
        pokemonPrintRun: PokemonPrintRun? = nil,
        finish: PhysicalVariant? = nil
    ) {
        self.name = name
        self.setName = setName
        self.collectorNumber = collectorNumber
        self.catalogID = catalogID
        self.pokemonPrintRun = pokemonPrintRun
        self.finish = finish
    }

    init(_ card: IdentifiedCard, pokemonPrintRun: PokemonPrintRun? = nil, finish: PhysicalVariant? = nil) {
        self.init(
            name: card.name,
            setName: card.setName,
            collectorNumber: card.cardNumber,
            catalogID: card.providerID,
            pokemonPrintRun: pokemonPrintRun,
            finish: finish
        )
    }

    func vendorGame(for game: CardGame) -> ProductCatalogIdentity.Game? {
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
            pokemonPrintRun: pokemonPrintRun,
            finish: finish
        )
    }

    /// Identifies the underlying card, so every owned grade of it shares one
    /// request.
    func groupingKey(game: CardGame) -> String {
        ([vendorGame(for: game)?.rawValue ?? "unsupported:\(game.rawValue)"] + exhaustiveProjection.groupingValues)
            .map { $0.lowercased() }
            .joined(separator: "|")
    }

    func matches(
        _ card: some JustTCGCardIdentityFields,
        game: CardGame,
        expectedSetSlug: String? = nil
    ) -> Bool {
        let projection = exhaustiveProjection
        guard let vendorGame = vendorGame(for: game) else { return false }

        if let expectedSetSlug {
            guard let candidateGame = card.identityGameID,
                  candidateGame.caseInsensitiveCompare(vendorGame.rawValue) == .orderedSame,
                  let candidateSet = card.identitySetID,
                  candidateSet.caseInsensitiveCompare(expectedSetSlug) == .orderedSame
            else { return false }
        } else if let candidateGame = card.identityGameID,
                  !candidateGame.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  candidateGame.caseInsensitiveCompare(vendorGame.rawValue) != .orderedSame {
            return false
        }

        guard let candidateName = card.identityName else { return false }
        guard CatalogIdentityNormalization.namesMatch(
            imported: projection.name,
            catalog: candidateName
        ) else { return false }
        // Once the vendor directory has resolved the set, the exact game and
        // set ID checked above are authoritative. Rechecking the catalog's
        // display name against the vendor's decorated label rejects valid
        // sets (XY - Roaring Skies, bonus sheets, Japanese abbreviations).
        // An unscoped fallback still needs the strict set-name comparison.
        if expectedSetSlug == nil {
            guard CatalogIdentityNormalization.canonicalSetName(projection.setName, game: game)
                == CatalogIdentityNormalization.canonicalSetName(card.identitySetName ?? "", game: game)
            else { return false }
        }

        let requestedNumber = projection.collectorNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateNumber = card.identityPrintedNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        if requestedNumber.isEmpty {
            return candidateNumber?.isEmpty ?? true
        }
        guard let candidateNumber, !candidateNumber.isEmpty else { return false }
        return ProductCatalogIdentity.numbersMatch(requestedNumber, candidateNumber)
    }

    /// The card and its variant are the external product boundary. Nothing
    /// from a graded response becomes a durable handle or price until both the
    /// card identity and the variant's declared print run have passed here.
    func matches(
        _ card: some JustTCGCardIdentityFields,
        variant: JustTCGVariant,
        game: CardGame,
        expectedSetSlug: String? = nil
    ) -> Bool {
        guard matches(card, game: game, expectedSetSlug: expectedSetSlug),
              variant.type?.caseInsensitiveCompare("graded") == .orderedSame
        else { return false }
        if let finish, !Self.matchesFinish(finish, printing: variant.printing, printRun: pokemonPrintRun,
                                         isJapanese: vendorGame(for: game) == .pokemonJapan) {
            return false
        }

        guard let pokemonPrintRun else { return true }
        guard let printing = variant.printing else { return false }
        return ProductEdition.from(pokemonPrintRun).admits(printing: printing)
    }

    static func matchesFinish(_ finish: PhysicalVariant, printing: String?, printRun: PokemonPrintRun? = nil, isJapanese: Bool = false) -> Bool {
        guard let printing, case let .printings(allowed) = ProductFinish.requirement(for: finish, printRun: printRun, isJapanese: isJapanese) else { return false }
        return allowed.contains { $0.caseInsensitiveCompare(printing) == .orderedSame }
    }

}

enum GradedVariantLookupResult: Equatable, Sendable {
    case matched([GradedVariant])
    case cardFoundWithoutGradedVariants
    case noProductMatch
    case incompleteSearch
    case localIdentityUnresolved
}

protocol GradedProductIdentity: Sendable {
    var productIDs: [String] { get }
    func matches(_ card: JustTCGV2Card) -> Bool
    func admits(_ variant: JustTCGVariant, productID: String?, requestedFinish: PhysicalVariant?) -> Bool
}

/// Derived from a freshly resolved catalog printing, never from an imported
/// marketplace handle. The product ID remains tied to the source UUID, full
/// collector identifier, release, language and available physical finishes.
struct MagicGradedProductIdentity: GradedProductIdentity {
    let catalogID: String
    let productIDs: [String]
    var productID: String? { productIDs.count == 1 ? productIDs.first : nil }
    private let names: [String]
    private let finishesByProduct: [String: Set<String>]

    private static func catalogFinishID(_ finish: PhysicalVariant) -> String {
        // Legacy CSV exports may store Magic nonfoil as Normal; both already
        // project to the same vendor printing in ProductFinish.
        finish == .normal ? PhysicalVariant.nonfoil.id : finish.id
    }

    init(identity: GradedCardIdentity, card: ScryfallCard, now: Date = .now) throws {
        guard identity.pokemonPrintRun == nil,
              let requestedID = identity.catalogID, UUID(uuidString: requestedID) != nil,
              card.id.caseInsensitiveCompare(requestedID) == .orderedSame,
              card.object == "card",
              CatalogIdentityNormalization.canonicalText(identity.name) == CatalogIdentityNormalization.canonicalText(card.name),
              CatalogIdentityNormalization.canonicalSetName(identity.setName, game: .magic)
                == CatalogIdentityNormalization.canonicalSetName(card.setName, game: .magic),
              ProductCatalogIdentity.numbersMatch(identity.collectorNumber, card.collectorNumber)
        else { throw ScryfallError.identityMismatch }
        guard card.language == "en", !card.digital, card.games?.contains("paper") == true,
              card.oversized == false, let layout = card.layout,
              !ScryfallService.unsupportedLayouts.contains(layout),
              let released = card.releaseDate, released <= now,
              let available = card.finishes, !available.isEmpty,
              available.allSatisfy({ ["nonfoil", "foil", "etched"].contains($0) }),
              Set(available).count == available.count,
              identity.finish.map({ available.contains(Self.catalogFinishID($0)) }) ?? true
        else { throw ScryfallError.unsupportedPrinting }
        catalogID = card.id
        var products: [String: Set<String>] = [:]
        var missingProduct = false
        for finish in identity.finish.map({ [Self.catalogFinishID($0)] }) ?? available {
            guard let id = card.tcgplayerProductID(for: PhysicalVariant.resolving(finish)).map(String.init) else {
                missingProduct = true
                continue
            }
            products[id, default: []].insert(finish)
        }
        // A partial product projection must not claim complete grade discovery.
        // Retain the strict legacy search if any requested finish lacks an ID.
        finishesByProduct = missingProduct ? [:] : products
        productIDs = finishesByProduct.keys.sorted()
        // Only provider-declared faces may answer a one-face vendor title.
        names = [card.name] + (card.cardFaces ?? []).compactMap(\.name)
    }

    func matches(_ card: JustTCGV2Card) -> Bool {
        guard let productID = card.externalIDs?.tcgplayer, productIDs.contains(productID),
              card.game?.id == ProductCatalogIdentity.Game.magic.rawValue,
              let name = card.name, !(card.id ?? card.uuid ?? "").isEmpty,
              names.contains(where: { CatalogIdentityNormalization.namesMatch(imported: $0, catalog: name) })
        else { return false }
        if let sourceID = card.externalIDs?.scryfall,
           sourceID.caseInsensitiveCompare(catalogID) != .orderedSame { return false }
        return true
    }

    func admits(_ variant: JustTCGVariant, productID: String? = nil, requestedFinish: PhysicalVariant?) -> Bool {
        guard variant.type?.caseInsensitiveCompare("graded") == .orderedSame,
              variant.language == nil || ["en", "english"].contains(variant.language!.lowercased()),
              let printing = variant.printing,
              let finishes = (productID ?? self.productID).flatMap({ finishesByProduct[$0] }) else { return false }
        if let requestedFinish, !finishes.contains(Self.catalogFinishID(requestedFinish)) { return false }
        let allowed = requestedFinish.map { [$0] } ?? finishes.map(PhysicalVariant.resolving)
        return allowed.contains { GradedCardIdentity.matchesFinish($0, printing: printing) }
    }
}

/// Reviewed subset identities, not aliases equating a TCGdex set with its
/// broader vendor group. Whole-source receipts and native product replays are
/// pinned in pokemon-subset-product-proof.json and the Yellow A finish proof.
/// Entries are standard English physical objects without edition or stamp ambiguity.
struct ReviewedPokemonProductIdentity: GradedProductIdentity {
    private struct Entry: Sendable {
        let catalogID, name, setName, printedNumber: String
        let productID: Int
        var finish: PhysicalVariant = .holo
    }

    private static let entries: [Entry] = {
        let unown: [(String, Int)] = [
            ("!", 90166), ("%3F", 90167), ("A", 90168), ("B", 90169), ("C", 90170),
            ("D", 90171), ("E", 90172), ("F", 90173), ("G", 90174), ("H", 90175),
            ("I", 90176), ("J", 90177), ("K", 90178), ("L", 90179), ("M", 90180),
            ("N", 90181), ("O", 90182), ("P", 90183), ("Q", 90184), ("R", 90185),
            ("S", 90186), ("T", 90187), ("U", 90188), ("V", 90189), ("W", 90190),
            ("X", 90191), ("Y", 90192), ("Z", 90193)
        ]
        let futsal: [(String, String, Int)] = [
            ("1", "Pikachu on the Ball", 223761), ("2", "Eevee on the Ball", 223760),
            ("3", "Grookey on the Ball", 227413), ("4", "Scorbunny on the Ball", 248016),
            ("5", "Sobble on the Ball", 248015)
        ]
        return unown.map { local, product in
            Entry(catalogID: "exu-" + local, name: "Unown", setName: "Unseen Forces Unown Collection",
                printedNumber: (local == "%3F" ? "?" : local) + "/28", productID: product)
        } + futsal.map { local, name, product in
            Entry(catalogID: "fut2020-" + local, name: name, setName: "Pokémon Futsal 2020",
                printedNumber: local + "/5", productID: product)
        } + [
            Entry(catalogID: "xya-24a", name: "M Manectric-EX", setName: "Yellow A Alternate", printedNumber: "24a/119", productID: 131696),
            Entry(catalogID: "xya-28a", name: "Jolteon-EX", setName: "Yellow A Alternate", printedNumber: "28a/83", productID: 131697),
            Entry(catalogID: "xya-54a", name: "Zygarde-EX", setName: "Yellow A Alternate", printedNumber: "54a/124", productID: 131698),
            Entry(catalogID: "xya-55a", name: "M Lucario-EX", setName: "Yellow A Alternate", printedNumber: "55a/111", productID: 131695),
            Entry(catalogID: "xya-92a", name: "Trainers’ Mail", setName: "Yellow A Alternate", printedNumber: "92a/108", productID: 133815, finish: .normal),
            Entry(catalogID: "xya-92a", name: "Trainers’ Mail", setName: "Yellow A Alternate", printedNumber: "92a/108", productID: 133816),
            Entry(catalogID: "xya-107a", name: "Professor Sycamore", setName: "Yellow A Alternate", printedNumber: "107a/122", productID: 133814, finish: .normal),
            Entry(catalogID: "xya-107a", name: "Professor Sycamore", setName: "Yellow A Alternate", printedNumber: "107a/122", productID: 133813)
        ]
    }()
    private static let byID = Dictionary(grouping: entries, by: \.catalogID)
    static var catalogIDs: Set<String> { Set(byID.keys) }

    private let selectedEntries: [Entry]
    private let printRun: PokemonPrintRun?
    var productIDs: [String] { selectedEntries.map { String($0.productID) }.sorted() }

    static func productID(for card: TCGdexCard, variant: PhysicalVariant, printRun: PokemonPrintRun?) -> Int? {
        guard let identity = try? Self(identity: .init(name: card.name, setName: card.set.name,
            collectorNumber: card.localId, catalogID: card.id, pokemonPrintRun: printRun, finish: variant)),
              identity.productIDs.count == 1 else { return nil }
        return identity.productIDs.first.flatMap(Int.init)
    }

    static func printedNumber(for card: TCGdexCard) -> String? {
        guard let identity = try? Self(identity: .init(name: card.name, setName: card.set.name,
            collectorNumber: card.localId, catalogID: card.id)) else { return nil }
        let numbers = Set(identity.selectedEntries.map(\.printedNumber))
        return numbers.count == 1 ? numbers.first : nil
    }

    init?(identity: GradedCardIdentity) throws {
        guard let id = identity.catalogID, let records = Self.byID[id], let entry = records.first else { return nil }
        var number = identity.collectorNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        // TCGdex's literal provider key is percent-encoded. Translate only this
        // reviewed card's local symbol, preserving any stated denominator.
        if id == "exu-%3F", number.lowercased() == "%3f" || number.lowercased().hasPrefix("%3f/") {
            number = "?" + number.dropFirst(3)
        }
        if id.hasPrefix("xya-") {
            // Only these reviewed letter-suffix cards need the vendor's padded
            // numeric prefix reconciled; suffixes and denominators stay intact.
            number = number.replacingOccurrences(of: #"^0+([0-9]+[a-zA-Z])(?=/|$)"#,
                with: "$1", options: .regularExpression)
        }
        guard CatalogIdentityNormalization.canonicalText(identity.name) == CatalogIdentityNormalization.canonicalText(entry.name),
              CatalogIdentityNormalization.canonicalSetName(identity.setName, game: .pokemon)
                == CatalogIdentityNormalization.canonicalSetName(entry.setName, game: .pokemon),
              ProductCatalogIdentity.numbersMatch(number, entry.printedNumber),
              identity.finish.map({ finish in records.contains { $0.finish == finish } }) ?? true,
              identity.pokemonPrintRun == nil || identity.pokemonPrintRun == .unlimited
        else { throw TCGdexError.identityMismatch }
        selectedEntries = records.filter { identity.finish == nil || $0.finish == identity.finish }
        printRun = identity.pokemonPrintRun
    }

    func matches(_ card: JustTCGV2Card) -> Bool {
        selectedEntries.contains { entry in card.externalIDs?.tcgplayer == String(entry.productID)
            && card.game?.id == ProductCatalogIdentity.Game.pokemon.rawValue
            && !(card.id ?? card.uuid ?? "").isEmpty
            && card.name.map { CatalogIdentityNormalization.namesMatch(imported: entry.name, catalog: $0) } == true }
    }

    func admits(_ variant: JustTCGVariant, productID: String?, requestedFinish: PhysicalVariant?) -> Bool {
        guard let entry = selectedEntries.first(where: { String($0.productID) == productID }),
              requestedFinish == nil || requestedFinish == entry.finish,
              variant.type?.caseInsensitiveCompare("graded") == .orderedSame,
              variant.language == nil || ["en", "english"].contains(variant.language!.lowercased()) else { return false }
        return GradedCardIdentity.matchesFinish(entry.finish, printing: variant.printing, printRun: printRun)
    }
}

struct JustTCGV2GradedClient: Sendable {
    static let apiVersion = "v2"

    private let transport: JustTCGTransport
    private let setDirectoryProvider: ProductSetDirectoryProvider
    private let maximumPages: Int
    typealias MagicCardLoader = @Sendable (String) async throws -> ScryfallCard
    private let magicCardLoader: MagicCardLoader?

    static func loadMagicCard(_ id: String) async throws -> ScryfallCard {
        try await ScryfallService().fetchCard(id: id)
    }

    init(
        transport: JustTCGTransport,
        setDirectoryProvider: ProductSetDirectoryProvider = .shared,
        maximumPages: Int = 3,
        magicCardLoader: MagicCardLoader? = nil
    ) {
        self.transport = transport
        self.setDirectoryProvider = setDirectoryProvider
        self.maximumPages = max(1, maximumPages)
        self.magicCardLoader = magicCardLoader
    }

    /// Keep the outgoing query testable as a value. A missing set is a
    /// deliberate fallback, not a fabricated slug derived from catalog text.
    static func requestQuery(
        identity: GradedCardIdentity,
        game: CardGame,
        setSlug: String?,
        verifiedProductID: String? = nil,
        companies: Set<GradingCompany> = [],
        grades: Set<String> = []
    ) -> [(String, String)] {
        guard let vendorGame = identity.vendorGame(for: game) else { return [] }
        var query: [(String, String)] = [
            ("game", vendorGame.rawValue),
            ("q", identity.name),
            ("graded", "only"),
            // JustTCG v2 returns the NA market by default. Spell it out so
            // the quote remains USD if the endpoint's default ever changes.
            ("regions", "NA"),
            // A missing set is a deliberate browse fallback, not permission to
            // download an unbounded game-wide response. The vendor's free tier
            // accepts at most this page size; identity matching still decides
            // whether any returned card is the requested one.
            ("limit", String(JustTCGQuota.maximumPageSize))
        ]
        if let verifiedProductID {
            query.removeAll { $0.0 == "q" }
            query.insert(("tcgplayer_id", verifiedProductID), at: 1)
        } else if let setSlug {
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
        guard let vendorGame = identity.vendorGame(for: game) else { return nil }
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

    /// Every graded variant of one card. Callers match the owned grader and
    /// grade locally so a missing grade remains distinguishable from a missing
    /// card or a card with no graded history.
    ///
    /// `graded=only` rather than `graded=include`: including raw results costs a
    /// surcharge and returns data the raw path already has. One card-level
    /// response also reveals which other grades JustTCG currently lists.
    ///
    /// Exact Magic printings and reviewed Pokémon subsets use the documented
    /// `tcgplayer_id`, checked against returned external_ids. Others use set/name, not the
    /// legacy camelCase `cardId`. v2 ignores that parameter and browses:
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
        try Task.checkCancellation()
        guard let vendorGame = identity.vendorGame(for: game) else {
            throw CardGameSupportError.unsupportedGame(game)
        }
        var exactProduct: (any GradedProductIdentity)?
        if game == .pokemon {
            do {
                exactProduct = try ReviewedPokemonProductIdentity(identity: identity)
            } catch TCGdexError.identityMismatch {
                return .localIdentityUnresolved
            }
        }
        if game == .magic, let id = identity.catalogID, UUID(uuidString: id) != nil,
           let magicCardLoader {
            do {
                let source = try await magicCardLoader(id)
                try Task.checkCancellation()
                let verified = try MagicGradedProductIdentity(identity: identity, card: source)
                if !verified.productIDs.isEmpty { exactProduct = verified }
            } catch ScryfallError.identityMismatch {
                return .localIdentityUnresolved
            } catch ScryfallError.unsupportedPrinting {
                return .localIdentityUnresolved
            } catch ScryfallError.cardNotFound {
                return .localIdentityUnresolved
            }
        }
        let setSlug: String?
        if exactProduct != nil {
            // A product spans vendor grouping conventions; a display-name set
            // filter can exclude this exact printing (anthologies, promos).
            setSlug = nil
        } else {
            let directory: ProductSetDirectory
            do {
                directory = try await setDirectoryProvider.directory(for: vendorGame) { [transport] in
                    let response: GradedSetsResponse = try await transport.get(
                        "v1/sets", query: [("game", vendorGame.rawValue)], lane: lane
                    )
                    return ProductSetDirectory(sets: response.data.compactMap { set in
                        set.id.map { (id: $0, name: set.name) }
                    })
                }
            } catch let error as JustTCGTransport.TransportError {
                switch error {
                case .budgetReached, .monthlyBudgetReached: return .incompleteSearch
                default: throw error
                }
            }
            setSlug = Self.resolvedSetSlug(identity: identity, game: game, directory: directory)
        }
        if identity.pokemonPrintRun != nil, setSlug == nil, exactProduct == nil {
            // A known print run without a trustworthy vendor set projection is
            // ambiguous. Do not issue a browse request whose first result could
            // become an authoritative slab binding.
            return .localIdentityUnresolved
        }
        var cards: [JustTCGV2Card] = []
        let productQueries: [String?] = exactProduct?.productIDs.map(Optional.some) ?? [nil]
        for productID in productQueries {
            let query = Self.requestQuery(identity: identity, game: game, setSlug: setSlug,
                verifiedProductID: productID, companies: companies, grades: grades)
            var productCards: [JustTCGV2Card] = []
            var cursor: String?
            var visited = Set<String>()
            productPages: for pageIndex in 0..<maximumPages {
                try Task.checkCancellation()
                var pageQuery = query
                if let cursor { pageQuery.append(("cursor", cursor)) }
                let page: (value: JustTCGV2CardsResponse, link: String?)
                do {
                    page = try await transport.getPage("v2/cards", query: pageQuery, lane: lane)
                } catch let error as JustTCGTransport.TransportError {
                    switch error {
                    case .budgetReached, .monthlyBudgetReached: return .incompleteSearch
                    case .badResponse(status: 404) where productID != nil && pageIndex == 0:
                        break productPages
                    default: throw error
                    }
                }
                productCards.append(contentsOf: page.value.data)
                do { cursor = try Self.nextCursor(from: page.link) }
                catch { return .incompleteSearch }
                guard let cursor else { break }
                guard visited.insert(cursor).inserted, pageIndex + 1 < maximumPages else { return .incompleteSearch }
            }
            if let exactProduct, let productID {
                let exact = productCards.filter { $0.externalIDs?.tcgplayer == productID && exactProduct.matches($0) }
                guard exact.count <= 1 else { return .incompleteSearch }
                cards.append(contentsOf: exact)
            } else {
                cards.append(contentsOf: productCards)
            }
        }

        // Only cards that are demonstrably the one asked for.
        let matchingCards = cards.filter {
            exactProduct?.matches($0) ?? identity.matches($0, game: game, expectedSetSlug: setSlug)
        }
        var variants: [GradedVariant] = []
        // Keep incompatible finish evidence visible to final selection. A card
        // with Reverse-only slabs has graded listings, but cannot price Normal.
        let cardIdentity = GradedCardIdentity(name: identity.name, setName: identity.setName,
            collectorNumber: identity.collectorNumber, catalogID: identity.catalogID,
            pokemonPrintRun: identity.pokemonPrintRun)
        for card in matchingCards {
            for variant in card.variants ?? [] {
                let matchesVariant = exactProduct.map {
                    $0.admits(variant, productID: card.externalIDs?.tcgplayer, requestedFinish: nil)
                }
                    ?? cardIdentity.matches(
                        card,
                        variant: variant,
                        game: game,
                        expectedSetSlug: setSlug
                    )
                guard matchesVariant,
                      let id = variant.variantId,
                      let grading = variant.grading,
                      let company = grading.gradingCompany else {
                    continue
                }
                variants.append(GradedVariant(
                    id: id,
                    // Kept so a later refresh can find this slab again without
                    // paying to resolve the card a second time.
                    cardID: card.uuid ?? card.id ?? card.slug,
                    company: company,
                    grade: grading.cardGrade,
                    canonical: grading.canonical,
                    printing: variant.printing,
                    // `null` is a real answer: the vendor does not manufacture a
                    // number for every grader/grade permutation, and an absent
                    // price must read as "no reliable market price" rather than
                    // as zero.
                    marketPriceUSD: variant.marketPriceUSD,
                    updatedAt: variant.updatedAt
                ))
            }
        }
        if exactProduct != nil, Set(variants.map(\.id)).count != variants.count { return .incompleteSearch }
        if !variants.isEmpty { return .matched(variants) }
        return matchingCards.isEmpty
            ? .noProductMatch
            : .cardFoundWithoutGradedVariants
    }

    /// Only the cursor is consumed. The original identity/grade/region filters
    /// stay authoritative; a provider link cannot replace them or receive a key.
    static func nextCursor(from link: String?) throws -> String? {
        guard let link, !link.isEmpty else { return nil }
        let next = link.components(separatedBy: ",").filter {
            $0.range(of: #"\brel\s*=\s*"?next\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
        guard !next.isEmpty else {
            if link.lowercased().contains("next") { throw JustTCGTransport.TransportError.invalidURL }
            return nil
        }
        guard next.count == 1, let part = next.first,
              let start = part.firstIndex(of: "<"), let end = part.firstIndex(of: ">"), start < end,
              let url = URLComponents(string: String(part[part.index(after: start)..<end])),
              url.scheme == "https", url.host == "api.justtcg.com", url.path == "/v2/cards",
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil else {
            throw JustTCGTransport.TransportError.invalidURL
        }
        let cursors = (url.queryItems ?? []).filter { $0.name == "cursor" }
        guard cursors.count == 1, let cursor = cursors[0].value, !cursor.isEmpty else {
            throw JustTCGTransport.TransportError.invalidURL
        }
        return cursor
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

    private struct GradedSetsResponse: Decodable {
        let data: [GradedSet]
    }

    private struct GradedSet: Decodable {
        let id: String?
        let name: String?
    }
}
