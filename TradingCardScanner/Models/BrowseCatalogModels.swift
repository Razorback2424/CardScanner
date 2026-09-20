import Foundation

enum PokemonPrintRun: String, Hashable, Sendable, Codable {
    case firstEdition
    case shadowless
    case unlimited

    var label: String {
        switch self {
        case .firstEdition: return "1st Edition"
        case .shadowless: return "Shadowless"
        case .unlimited: return "Unlimited"
        }
    }
}

struct CatalogSetID: Hashable, Identifiable, Sendable, Codable {
    let game: CardGame
    let providerID: String
    var pokemonPrintRun: PokemonPrintRun? = nil

    var id: String {
        [game.rawValue, providerID.lowercased(), pokemonPrintRun?.rawValue]
            .compactMap { $0 }
            .joined(separator: ":")
    }
}

struct CatalogSet: Identifiable, Hashable, Sendable, Codable {
    let catalogID: CatalogSetID
    let name: String
    let code: String
    let logoURL: URL?
    let symbolURL: URL?
    let cardCount: Int?
    let releaseDate: Date?
    let sortRank: Int
    /// Signed catalog metadata authorizing the corresponding bundled artwork
    /// source. It is optional so legacy snapshots and non-Pokémon catalogs
    /// remain readable.
    var bundledArtworkSourceID: String? = nil
    /// Publisher-prepared card artwork hints used only after every real set-art
    /// candidate fails. Optional so old bundled/downloaded manifests decode.
    var artworkFallbackURLs: [URL]? = nil

    init(
        catalogID: CatalogSetID,
        name: String,
        code: String,
        logoURL: URL?,
        symbolURL: URL?,
        cardCount: Int?,
        releaseDate: Date?,
        sortRank: Int,
        bundledArtworkSourceID: String? = nil,
        artworkFallbackURLs: [URL]? = nil
    ) {
        self.catalogID = catalogID
        self.name = name
        self.code = code
        self.logoURL = logoURL
        self.symbolURL = symbolURL
        self.cardCount = cardCount
        self.releaseDate = releaseDate
        self.sortRank = sortRank
        self.bundledArtworkSourceID = bundledArtworkSourceID
        self.artworkFallbackURLs = artworkFallbackURLs
    }

    /// Only virtual WotC set rows carry this. The provider set ID remains the
    /// same because print run is an independent physical attribute.
    var pokemonPrintRun: PokemonPrintRun? { catalogID.pokemonPrintRun }

    var id: String { catalogID.id }
    var game: CardGame { catalogID.game }
    var providerID: String { catalogID.providerID }
    var releaseOrder: Int {
        game == .pokemon
            ? sortRank
            : releaseDate.map { Int($0.timeIntervalSince1970 / 86_400) } ?? sortRank
    }
}

struct CatalogCardSummary: Identifiable, Hashable, Sendable, Codable {
    let game: CardGame
    let providerID: String
    let setID: CatalogSetID
    let setName: String
    let setCode: String
    let name: String
    let collectorNumber: String
    let thumbnailURL: URL?
    let imageURL: URL?
    /// Magic treatments are part of the exact printing summary, not another
    /// finish choice. Raw strings keep a newer catalog value readable on an
    /// older build as `MagicTreatment.unclassified` instead of dropping the
    /// card from Browse or ownership matching.
    var magicTreatmentIDsRaw: [String] = []
    /// Reviewed treatment qualifiers (for example a Neon Ink color) travel with
    /// the summary so the Browse grid can describe the exact catalog evidence.
    var magicTreatmentQualifiers: [String: String] = [:]
    /// Pokémon set pages expand one numbered card into the pack-pulled
    /// variations required by a master set. Search and Magic summaries leave
    /// this nil because they still represent a printing rather than a slot.
    var masterSetVariant: PhysicalVariant? = nil
    var isExpandedMasterSetVariant = false
    /// True when the catalog publishes exactly one physical slot for this
    /// numbered card. A copy whose finish was never recorded — a CSV import, or
    /// a scan the resolver could not settle — can only be that slot, so it is
    /// counted rather than shown as missing next to a card the user owns.
    var isSoleSlotForCard = false
    var pokemonPrintRun: PokemonPrintRun? { setID.pokemonPrintRun }

    init(
        game: CardGame,
        providerID: String,
        setID: CatalogSetID,
        setName: String,
        setCode: String,
        name: String,
        collectorNumber: String,
        thumbnailURL: URL?,
        imageURL: URL?,
        masterSetVariant: PhysicalVariant? = nil,
        isExpandedMasterSetVariant: Bool = false,
        isSoleSlotForCard: Bool = false,
        magicTreatmentIDsRaw: [String] = [],
        magicTreatmentQualifiers: [String: String] = [:]
    ) {
        self.game = game
        self.providerID = providerID
        self.setID = setID
        self.setName = setName
        self.setCode = setCode
        self.name = name
        self.collectorNumber = collectorNumber
        self.thumbnailURL = thumbnailURL
        self.imageURL = imageURL
        let storedTreatmentIDs = MagicTreatmentKeyCodec.storedIDs(from: magicTreatmentIDsRaw)
        self.magicTreatmentIDsRaw = storedTreatmentIDs
        let treatmentIDSet = Set(MagicTreatmentKeyCodec.canonicalIDs(from: storedTreatmentIDs))
        self.magicTreatmentQualifiers = MagicTreatmentKeyCodec.storedQualifiers(
            from: magicTreatmentQualifiers
        ).filter { treatmentIDSet.contains($0.key) }
        self.masterSetVariant = masterSetVariant
        self.isExpandedMasterSetVariant = isExpandedMasterSetVariant
        self.isSoleSlotForCard = isSoleSlotForCard
    }

    enum CodingKeys: String, CodingKey {
        case game, providerID, setID, setName, setCode, name, collectorNumber
        case thumbnailURL, imageURL
        case magicTreatmentIDsRaw, magicTreatmentQualifiers
        case masterSetVariant, isExpandedMasterSetVariant, isSoleSlotForCard
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        game = try container.decode(CardGame.self, forKey: .game)
        providerID = try container.decode(String.self, forKey: .providerID)
        setID = try container.decode(CatalogSetID.self, forKey: .setID)
        setName = try container.decode(String.self, forKey: .setName)
        setCode = try container.decode(String.self, forKey: .setCode)
        name = try container.decode(String.self, forKey: .name)
        collectorNumber = try container.decode(String.self, forKey: .collectorNumber)
        thumbnailURL = try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
        imageURL = try container.decodeIfPresent(URL.self, forKey: .imageURL)
        let storedTreatmentIDs = MagicTreatmentKeyCodec.storedIDs(
            from: try container.decodeIfPresent([String].self, forKey: .magicTreatmentIDsRaw) ?? []
        )
        magicTreatmentIDsRaw = storedTreatmentIDs
        let treatmentIDSet = Set(MagicTreatmentKeyCodec.canonicalIDs(from: storedTreatmentIDs))
        let rawQualifiers = try container.decodeIfPresent(
            [String: String].self,
            forKey: .magicTreatmentQualifiers
        ) ?? [:]
        magicTreatmentQualifiers = MagicTreatmentKeyCodec.storedQualifiers(
            from: rawQualifiers
        ).filter { treatmentIDSet.contains($0.key) }
        masterSetVariant = try container.decodeIfPresent(
            PhysicalVariant.self,
            forKey: .masterSetVariant
        )
        isExpandedMasterSetVariant = try container.decodeIfPresent(
            Bool.self,
            forKey: .isExpandedMasterSetVariant
        ) ?? false
        isSoleSlotForCard = try container.decodeIfPresent(
            Bool.self,
            forKey: .isSoleSlotForCard
        ) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(game, forKey: .game)
        try container.encode(providerID, forKey: .providerID)
        try container.encode(setID, forKey: .setID)
        try container.encode(setName, forKey: .setName)
        try container.encode(setCode, forKey: .setCode)
        try container.encode(name, forKey: .name)
        try container.encode(collectorNumber, forKey: .collectorNumber)
        try container.encodeIfPresent(thumbnailURL, forKey: .thumbnailURL)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        // Keep Pokémon checklist resources byte-compatible and sparse. The
        // absent keys decode as the empty Magic treatment axis above.
        if !magicTreatmentIDsRaw.isEmpty {
            try container.encode(magicTreatmentIDsRaw, forKey: .magicTreatmentIDsRaw)
        }
        if !magicTreatmentQualifiers.isEmpty {
            try container.encode(magicTreatmentQualifiers, forKey: .magicTreatmentQualifiers)
        }
        try container.encodeIfPresent(masterSetVariant, forKey: .masterSetVariant)
        try container.encode(isExpandedMasterSetVariant, forKey: .isExpandedMasterSetVariant)
        try container.encode(isSoleSlotForCard, forKey: .isSoleSlotForCard)
    }

    var id: String {
        [setID.id, providerID, masterSetVariant?.id]
            .compactMap { $0 }
            .joined(separator: ":")
    }

    var masterSetVariantLabel: String? { masterSetVariant?.label }

    var magicTreatments: [MagicTreatment] {
        magicTreatmentIDsRaw.compactMap(MagicTreatment.init(id:))
    }

    var magicTreatmentEvidence: MagicTreatmentEvidence {
        MagicTreatmentEvidence(
            treatments: magicTreatments,
            qualifiers: magicTreatmentQualifiers
        )
    }

    var magicTreatmentDisplayLabel: String? {
        magicTreatmentEvidence.displayLabel
    }
}

/// Presentation-only kind labels used by the unified Catalog search surface.
/// Card and sealed identities remain owned by their respective providers.
enum CatalogResultKind: String, Hashable, Sendable {
    case card
    case sealed
}

/// One result in the Catalog search stream. The stable id is deliberately
/// namespaced so a card and a sealed product can never collide in a `ForEach`.
enum CatalogSearchResult: Identifiable, Hashable, Sendable {
    case card(CatalogCardSummary)
    case sealed(game: CardGame, product: SealedProductSummary)

    var kind: CatalogResultKind {
        switch self {
        case .card: return .card
        case .sealed: return .sealed
        }
    }

    var game: CardGame {
        switch self {
        case let .card(summary): return summary.game
        case let .sealed(game, _): return game
        }
    }

    var name: String {
        switch self {
        case let .card(summary): return summary.name
        case let .sealed(_, product): return product.name
        }
    }

    var id: String {
        switch self {
        case let .card(summary):
            return "card:" + summary.id
        case let .sealed(game, product):
            return "sealed:" + [
                game.rawValue,
                product.id,
                product.variantID ?? ""
            ].joined(separator: ":")
        }
    }
}

/// A UI grouping key for one numbered card. It intentionally excludes the
/// Pokémon master-set finish axis while retaining the provider identity and the
/// set's print-run-qualified id.
struct CatalogCardDisplayIdentity: Hashable, Sendable {
    let game: CardGame
    let setID: CatalogSetID
    let providerID: String
    let collectorNumber: String

    var id: String {
        [game.rawValue, setID.id, providerID, collectorNumber].joined(separator: "|")
    }
}

struct CatalogCardDisplayGroup: Identifiable, Hashable, Sendable {
    let identity: CatalogCardDisplayIdentity
    let summaries: [CatalogCardSummary]

    init(identity: CatalogCardDisplayIdentity, summary: CatalogCardSummary) {
        self.identity = identity
        self.summaries = [summary]
    }

    init?(identity: CatalogCardDisplayIdentity, summaries: [CatalogCardSummary]) {
        guard !summaries.isEmpty else { return nil }
        self.identity = identity
        self.summaries = summaries
    }

    var id: String { identity.id }

    /// Normal is the primary card surface. A nil variant is the ordinary
    /// printing used by search and Magic, so it is also preferred when present.
    var preferredSummary: CatalogCardSummary {
        return summaries.first(where: { $0.masterSetVariant?.id == PhysicalVariant.normal.id })
            ?? summaries.first(where: { $0.masterSetVariant == nil })
            ?? summaries[0]
    }
}

enum CatalogCardDisplayGrouping {
    /// The order is a presentation contract: common master-set variants are
    /// stable even if the provider changes the order of its detailed fields.
    static let variantOrder: [String] = [
        PhysicalVariant.normal.id,
        PhysicalVariant.reverse.id,
        PhysicalVariant.pokeBall.id,
        PhysicalVariant.masterBall.id,
        PhysicalVariant.duskBall.id,
        PhysicalVariant.friendBall.id,
        PhysicalVariant.quickBall.id,
        PhysicalVariant.loveBall.id
    ]

    static func groups(for summaries: [CatalogCardSummary]) -> [CatalogCardDisplayGroup] {
        var groups: [CatalogCardDisplayGroup] = []
        var indexByIdentity: [CatalogCardDisplayIdentity: Int] = [:]

        for summary in summaries {
            let number = SetCompletionCalculator.canonicalNumber(summary.collectorNumber)
                ?? summary.collectorNumber.lowercased()
            var identity = CatalogCardDisplayIdentity(
                game: summary.game,
                setID: summary.setID,
                providerID: summary.providerID,
                collectorNumber: number
            )

            // Magic treatments are exact printings. Keep every Magic summary a
            // singleton, while still disambiguating an unexpectedly duplicated
            // provider identity so the resulting ForEach ids stay unique.
            if summary.game == .magic {
                if indexByIdentity[identity] != nil {
                    var collisionIndex = groups.count
                    repeat {
                        identity = CatalogCardDisplayIdentity(
                            game: summary.game,
                            setID: summary.setID,
                            providerID: summary.providerID,
                            collectorNumber: "\(number)#\(collisionIndex)"
                        )
                        collisionIndex += 1
                    } while indexByIdentity[identity] != nil
                }
                indexByIdentity[identity] = groups.count
                groups.append(
                    CatalogCardDisplayGroup(identity: identity, summary: summary)
                )
                continue
            }

            if let index = indexByIdentity[identity] {
                var updated = groups[index].summaries
                guard !updated.contains(where: { $0.id == summary.id }) else { continue }
                updated.append(summary)
                if let replacement = CatalogCardDisplayGroup(
                    identity: identity,
                    summaries: updated
                ) {
                    groups[index] = replacement
                }
            } else {
                indexByIdentity[identity] = groups.count
                groups.append(
                    CatalogCardDisplayGroup(identity: identity, summary: summary)
                )
            }
        }

        return groups.compactMap { group in
            CatalogCardDisplayGroup(
                identity: group.identity,
                summaries: group.summaries.sorted(by: variantPrecedes)
            )
        }
    }

    static func variantPrecedes(
        _ lhs: CatalogCardSummary,
        _ rhs: CatalogCardSummary
    ) -> Bool {
        let leftID = lhs.masterSetVariant?.id ?? PhysicalVariant.normal.id
        let rightID = rhs.masterSetVariant?.id ?? PhysicalVariant.normal.id
        let leftRank = variantOrder.firstIndex(of: leftID)
        let rightRank = variantOrder.firstIndex(of: rightID)
        switch (leftRank, rightRank) {
        case let (left?, right?) where left != right:
            return left < right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            let leftLabel = lhs.masterSetVariantLabel ?? "Standard"
            let rightLabel = rhs.masterSetVariantLabel ?? "Standard"
            let comparison = leftLabel.localizedCaseInsensitiveCompare(rightLabel)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.id < rhs.id
        }
    }
}

/// Result of the root's dated-first release-rail policy.
struct CatalogReleaseRail: Equatable, Sendable {
    let title: String
    let sets: [CatalogSet]
    let showsNewBadges: Bool
}

/// The small value summary used by the root game rows. The eligible collection
/// is filtered once, then the full quantity and three-row artwork fan are both
/// derived from it so the two displays cannot drift. The fan prefers the
/// newest Pokémon sets with bundled logo artwork, then fills any remaining
/// slots from the newest catalog rows so its offline fallback stays useful.
struct CatalogGameSummary: Equatable, Sendable {
    let game: CardGame
    let setCount: Int
    let ownedCardQuantity: Int
    let recentArtworkRows: [CollectionRow]
    let recentSetArtwork: [CatalogSet]

    init(game: CardGame, sets: [CatalogSet], rows: [CollectionRow]) {
        self.game = game
        setCount = sets.count
        let releaseOrderedSets = sets.sorted {
            if $0.releaseOrder != $1.releaseOrder {
                return $0.releaseOrder > $1.releaseOrder
            }
            return $0.id < $1.id
        }
        let bundledArtworkSets = releaseOrderedSets.filter {
            $0.game == .pokemon
                && PokemonArtworkFallbacks.localAssetName(
                    forProviderID: $0.providerID,
                    sourceID: $0.bundledArtworkSourceID,
                    kind: .logo
                ) != nil
        }
        var seenArtworkSetIDs = Set<String>()
        var artworkCandidates: [CatalogSet] = []
        for set in bundledArtworkSets + releaseOrderedSets
            where seenArtworkSetIDs.insert(set.id).inserted {
            artworkCandidates.append(set)
        }
        recentSetArtwork = Array(artworkCandidates.prefix(3))
        let eligibleRows = rows
            .filter {
                $0.game == game
                    && $0.quantity > 0
                    && $0.itemKind.countsTowardSetCompletion
            }
            .sorted {
                if $0.dateAdded != $1.dateAdded { return $0.dateAdded > $1.dateAdded }
                return $0.id < $1.id
            }
        ownedCardQuantity = eligibleRows.reduce(0) { $0 + $1.quantity }
        recentArtworkRows = Array(eligibleRows.prefix(3))
    }

    var subtitle: String {
        let setsCopy = countLabel(setCount, singular: "set", plural: "sets")
        let cardsCopy = ownedCardQuantity > 0
            ? countLabel(ownedCardQuantity, singular: "card owned", plural: "cards owned")
            : "No cards owned"
        return "\(setsCopy) · \(cardsCopy)"
    }
}

/// Grammar shared by the browse tiles, directories, and game summaries.
func countLabel(_ count: Int, singular: String, plural: String) -> String {
    "\(count) \(count == 1 ? singular : plural)"
}

struct CatalogSearchLaneStatus: Equatable, Sendable {
    let isRequested: Bool
    let isLoading: Bool
    let error: String?

    init(
        isRequested: Bool = true,
        isLoading: Bool = false,
        error: String? = nil
    ) {
        self.isRequested = isRequested
        self.isLoading = isLoading
        self.error = error
    }
}

enum CatalogSearchState: Equatable, Sendable {
    case idle
    case loading
    case results(hasFailures: Bool)
    case failed
    case empty(needsSealedSetup: Bool)

    static func reduce(
        resultCount: Int,
        lanes: [CatalogSearchLaneStatus],
        sealedWasSkippedForMissingCredentials: Bool
    ) -> CatalogSearchState {
        if resultCount > 0 {
            return .results(hasFailures: lanes.contains { $0.isRequested && $0.error != nil })
        }

        let requested = lanes.filter(\.isRequested)
        if requested.contains(where: \.isLoading) {
            return .loading
        }
        if requested.contains(where: { $0.error != nil }) {
            return .failed
        }
        return .empty(needsSealedSetup: sealedWasSkippedForMissingCredentials)
    }
}

enum CatalogSearchResultRanking {
    private struct RankedResult {
        let bucket: Int
        let name: String
        let kind: String
        let game: String
        let id: String
        let result: CatalogSearchResult
    }

    static func sorted(
        _ results: [CatalogSearchResult],
        query: String
    ) -> [CatalogSearchResult] {
        let normalizedQuery = CardNameSearch.normalize(query)
        let ranked = results.map { result in
            RankedResult(
                bucket: relevance(
                    normalizedName: CardNameSearch.normalize(result.name),
                    normalizedQuery: normalizedQuery
                ),
                name: result.name,
                kind: result.kind.rawValue,
                game: result.game.rawValue,
                id: result.id,
                result: result
            )
        }
        return ranked.sorted { lhs, rhs in
            if lhs.bucket != rhs.bucket { return lhs.bucket < rhs.bucket }

            let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            if lhs.kind != rhs.kind {
                return lhs.kind < rhs.kind
            }
            if lhs.game != rhs.game {
                return lhs.game < rhs.game
            }
            return lhs.id < rhs.id
        }.map(\.result)
    }

    static func relevance(of name: String, query: String) -> Int {
        let normalizedName = CardNameSearch.normalize(name)
        let normalizedQuery = CardNameSearch.normalize(query)
        return relevance(normalizedName: normalizedName, normalizedQuery: normalizedQuery)
    }

    private static func relevance(normalizedName: String, normalizedQuery: String) -> Int {
        guard !normalizedQuery.isEmpty else { return 4 }
        if normalizedName == normalizedQuery { return 0 }
        if normalizedName.hasPrefix(normalizedQuery) { return 1 }
        if normalizedName.split(separator: " ").contains(where: {
            $0.hasPrefix(normalizedQuery)
        }) {
            return 2
        }
        if normalizedName.contains(normalizedQuery) { return 3 }
        return 4
    }
}

struct CatalogCardDetails: Sendable {
    let card: IdentifiedCard
    let set: CatalogSet
}

struct CatalogPage<Element: Sendable>: Sendable {
    let items: [Element]
    let nextCursor: String?
}

extension CatalogPage: Codable where Element: Codable {}

struct SetCompletion: Equatable, Sendable {
    let owned: Int
    let total: Int?
    var unit: String = "cards"

    var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(Double(owned) / Double(total), 1)
    }

    var label: String {
        total.map { "\(owned)/\($0) \(unit)" } ?? "\(owned)/— \(unit)"
    }
}

/// Completion values prepared from the same checklist manifest used by the
/// set screen. The tier is part of the value so an old asynchronous rebuild
/// cannot be displayed for a newly selected master-set definition.
struct CatalogSetCompletionIndex: Equatable, Sendable {
    private let tier: PokemonMasterSetTier
    private let completions: [String: SetCompletion]

    init(
        completions: [String: SetCompletion],
        tier: PokemonMasterSetTier = .standard
    ) {
        self.tier = tier
        self.completions = completions
    }

    func completion(
        for set: CatalogSet,
        tier: PokemonMasterSetTier
    ) -> SetCompletion? {
        guard self.tier == tier else { return nil }
        return completions[set.id]
    }
}

/// Sorting options for the catalog's set directory. These are deliberately
/// separate from `CatalogSetSort`, which sorts cards inside one set.
enum CatalogSetListSort: String, CaseIterable, Identifiable, Sendable {
    case newestFirst
    case oldestFirst
    case nameAToZ
    case mostComplete

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newestFirst: return "Newest first"
        case .oldestFirst: return "Oldest first"
        case .nameAToZ: return "Name A–Z"
        case .mostComplete: return "Most complete"
        }
    }
}

/// The set directory exposes only ownership state that the catalog can answer
/// locally. Era and series filters are intentionally deferred until both
/// providers publish a decoded, cached field for them.
enum CatalogSetListFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case started

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All sets"
        case .started: return "Started"
        }
    }
}

/// Set-list completion counts distinct numbered cards because the provider's
/// set total is a card count. The loaded set screen uses the separate slot
/// overload below, where both numerator and denominator are variations.
enum SetCompletionCalculator {
    static func progress(for set: CatalogSet, cards: [CollectedCard]) -> SetCompletion {
        let numbers = Set(cards.compactMap { card -> String? in
            guard belongs(card, to: set) else { return nil }
            return canonicalNumber(card.cardNumber)
        })
        return SetCompletion(
            owned: numbers.count,
            total: set.cardCount,
            unit: "cards"
        )
    }

    static func owns(_ summary: CatalogCardSummary, cards: [CollectedCard]) -> Bool {
        guard let targetNumber = canonicalNumber(summary.collectorNumber) else { return false }
        let targetProviderID = summary.providerID.lowercased()
        let requiredTreatmentIDs = Set(
            MagicTreatmentKeyCodec.canonicalIDs(from: summary.magicTreatmentIDsRaw)
        )
        return cards.contains { card in
            guard card.itemKind.countsTowardSetCompletion else { return false }
            guard !PokemonStampedReleaseCatalog.isStamped(variantID: card.variantID) else {
                return false
            }
            guard card.cardGame == summary.game, card.quantity > 0 else { return false }
            guard pokemonPrintRunMatches(card, required: summary.pokemonPrintRun) else {
                return false
            }
            let identityMatches: Bool
            if card.providerID.lowercased() == targetProviderID
                || card.catalogProviderID?.lowercased() == targetProviderID {
                identityMatches = true
            } else {
                guard canonicalNumber(card.cardNumber) == targetNumber else { return false }
                let cardCode = normalized(card.setCode)
                identityMatches = cardCode == normalized(summary.setCode)
                    || normalized(card.setName) == normalized(summary.setName)
            }
            guard identityMatches else { return false }
            guard treatmentIDs(for: card) == requiredTreatmentIDs
                || requiredTreatmentIDs.isEmpty else {
                return false
            }
            guard let required = summary.masterSetVariant else { return true }
            if card.variantID == nil && summary.isSoleSlotForCard { return true }
            return masterVariantID(card.variantID) == masterVariantID(required.id)
        }
    }

    static func progress(
        for slots: [CatalogCardSummary],
        cards: [CollectedCard]
    ) -> SetCompletion {
        SetCompletion(
            owned: slots.reduce(0) { $0 + (owns($1, cards: cards) ? 1 : 0) },
            total: slots.count,
            unit: "variations"
        )
    }

    private static func treatmentIDs(for card: CollectedCard) -> Set<String> {
        let rawIDs: [String]
        switch card.itemKind {
        case .rawCard:
            rawIDs = card.magicTreatmentIDs(for: card.variant)
        case .gradedCard, .sealedProduct:
            rawIDs = card.magicTreatmentIDsRaw
        }
        return Set(MagicTreatmentKeyCodec.canonicalIDs(from: rawIDs))
    }

    private static func belongs(_ card: CollectedCard, to set: CatalogSet) -> Bool {
        // A sealed product is not a card and completes no slot. Graded copies do
        // count, and because progress is measured over a *set* of collector
        // numbers, a raw and a graded copy of the same card count once between
        // them — owning three grades of one card cannot inflate completion.
        guard card.itemKind.countsTowardSetCompletion else { return false }
        guard !PokemonStampedReleaseCatalog.isStamped(variantID: card.variantID) else {
            return false
        }
        guard card.cardGame == set.game else { return false }
        guard pokemonPrintRunMatches(card, required: set.pokemonPrintRun) else { return false }

        let normalizedCardCode = normalized(card.setCode)
        let normalizedSetCode = normalized(set.code)
        if normalizedCardCode == normalizedSetCode { return true }

        guard set.game == .pokemon else { return false }
        let providerID = card.catalogProviderID ?? card.providerID
        return providerID.lowercased().hasPrefix(set.providerID.lowercased() + "-")
    }

    private static func pokemonPrintRunMatches(
        _ card: CollectedCard,
        required: PokemonPrintRun?
    ) -> Bool {
        guard card.cardGame == .pokemon else { return true }
        switch required {
        case .firstEdition:
            return card.pokemonPrintRun == .firstEdition
        case .shadowless:
            return card.pokemonPrintRun == .shadowless
        case .unlimited:
            // Rows written before print-run persistence were Unlimited unless
            // they used the legacy first-edition pseudo-finish.
            return card.pokemonPrintRun == .unlimited || card.pokemonPrintRun == nil
        case nil:
            return card.pokemonPrintRun == nil
        }
    }

    private static func masterVariantID(_ variantID: String?) -> String {
        switch variantID {
        case PhysicalVariant.reverse.id: return PhysicalVariant.reverse.id
        case PhysicalVariant.pokeBall.id: return PhysicalVariant.pokeBall.id
        case PhysicalVariant.masterBall.id: return PhysicalVariant.masterBall.id
        case PhysicalVariant.duskBall.id: return PhysicalVariant.duskBall.id
        case PhysicalVariant.friendBall.id: return PhysicalVariant.friendBall.id
        case PhysicalVariant.quickBall.id: return PhysicalVariant.quickBall.id
        case PhysicalVariant.loveBall.id: return PhysicalVariant.loveBall.id
        case PhysicalVariant.normal.id, PhysicalVariant.firstEdition.id, nil:
            return PhysicalVariant.normal.id
        case let value?: return value
        }
    }

    static func canonicalNumber(_ value: String) -> String? {
        let printed = value.split(separator: "/", maxSplits: 1).first.map(String.init) ?? value
        let trimmed = printed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // A suffixed collector number is still one numeric identity. Strip
        // padding from its numeric stem without turning `0523a` into a
        // different string from the catalog's `523a`.
        let numberEnd = trimmed.firstIndex(where: { !$0.isNumber }) ?? trimmed.endIndex
        if numberEnd > trimmed.startIndex,
           numberEnd < trimmed.endIndex {
            let numericPart = String(trimmed[..<numberEnd])
            let suffix = trimmed[numberEnd...]
            if suffix.allSatisfy({ $0.isLetter }),
               let number = Int(numericPart) {
                return "\(number)\(suffix.lowercased())"
            }
        }

        return Int(trimmed).map(String.init) ?? trimmed.lowercased()
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}

/// Ownership answers for a page of catalog slots, prepared once.
///
/// `SetCompletionCalculator.owns` scans the whole collection and case-folds
/// strings on every comparison. A browse grid asks it twice per visible card —
/// once for the check badge, once for the owned quantity — so on a large
/// collection the same scan runs over and over while the user scrolls. Bucketing
/// the collection by collector number and provider ID first narrows each answer
/// to a handful of candidates without changing what counts as a match.
struct CatalogOwnershipCardSnapshot: Equatable, Sendable, Identifiable {
    let collectionKey: String
    let game: CardGame
    let providerID: String
    let catalogProviderID: String?
    let setCode: String
    let setName: String
    let cardNumber: String
    let quantity: Int
    let itemKind: CollectionItemKind
    let variantID: String?
    let variantLabel: String?
    let pokemonPrintRunRaw: String?
    let magicTreatmentIDsRaw: [String]

    var id: String { collectionKey }
    let sealedProductID: String?
    let sealedVariantID: String?

    init(_ card: CollectedCard) {
        collectionKey = card.collectionKey
        game = card.cardGame
        providerID = card.providerID
        catalogProviderID = card.catalogProviderID
        setCode = card.setCode
        setName = card.setName
        cardNumber = card.cardNumber
        quantity = card.quantity
        itemKind = card.itemKind
        variantID = card.variantID
        variantLabel = card.variantLabel
        pokemonPrintRunRaw = card.pokemonPrintRunRaw
        magicTreatmentIDsRaw = card.magicTreatmentIDsRaw
        sealedProductID = card.justTCGCardID
        sealedVariantID = card.justTCGVariantID
    }

    var pokemonPrintRun: PokemonPrintRun? {
        pokemonPrintRunRaw.flatMap(PokemonPrintRun.init(rawValue:))
    }

    var variant: PhysicalVariant? {
        guard let variantID else { return nil }
        return PhysicalVariant(id: variantID, label: variantLabel ?? variantID.capitalized)
    }
}

/// Ownership answers are value data. The index can be built on a model actor
/// and passed to every browse route without retaining SwiftData model objects.
struct CatalogOwnershipIndex: Equatable, Sendable {
    private var byNumber: [String: [CatalogOwnershipCardSnapshot]] = [:]
    private var byProviderID: [String: [CatalogOwnershipCardSnapshot]] = [:]
    private var bySealedProduct: [String: Int] = [:]
    private var ownedSetCodes: Set<String> = []
    private var ownedProviderIDs: Set<String> = []
    private var completionRows: [CatalogOwnershipCardSnapshot] = []

    init(_ cards: [CollectedCard]) {
        self.init(rows: cards.map(CatalogOwnershipCardSnapshot.init))
    }

    init(rows: [CatalogOwnershipCardSnapshot]) {
        var seenCompletionRowKeys: Set<String> = []
        for card in rows where card.quantity > 0 {
            if card.itemKind == .sealedProduct,
               let productID = card.sealedProductID {
                bySealedProduct[Self.sealedKey(productID, card.sealedVariantID), default: 0] += card.quantity
                continue
            }
            guard card.itemKind.countsTowardSetCompletion else { continue }
            ownedSetCodes.insert(Self.normalizedKey(card.setCode))
            ownedProviderIDs.insert(Self.normalizedKey(card.providerID))
            if let catalogID = card.catalogProviderID {
                ownedProviderIDs.insert(Self.normalizedKey(catalogID))
            }
            if seenCompletionRowKeys.insert(card.collectionKey).inserted {
                completionRows.append(card)
            }
            if let number = SetCompletionCalculator.canonicalNumber(card.cardNumber) {
                byNumber[number, default: []].append(card)
            }
            var providerIDs = [card.providerID.lowercased()]
            if let catalogID = card.catalogProviderID?.lowercased(),
               !providerIDs.contains(catalogID) {
                providerIDs.append(catalogID)
            }
            for id in providerIDs { byProviderID[id, default: []].append(card) }
        }
    }

    func owns(_ summary: CatalogCardSummary) -> Bool {
        guard let targetNumber = SetCompletionCalculator.canonicalNumber(summary.collectorNumber)
        else { return false }
        let targetProviderID = summary.providerID.lowercased()
        let requiredTreatmentIDs = Set(
            MagicTreatmentKeyCodec.canonicalIDs(from: summary.magicTreatmentIDsRaw)
        )
        return candidates(for: summary).contains { card in
            guard card.itemKind.countsTowardSetCompletion,
                  !PokemonStampedReleaseCatalog.isStamped(variantID: card.variantID),
                  card.game == summary.game,
                  card.quantity > 0,
                  Self.pokemonPrintRunMatches(card, required: summary.pokemonPrintRun)
            else { return false }

            let identityMatches: Bool
            if card.providerID.lowercased() == targetProviderID
                || card.catalogProviderID?.lowercased() == targetProviderID {
                identityMatches = true
            } else {
                guard SetCompletionCalculator.canonicalNumber(card.cardNumber) == targetNumber
                else { return false }
                identityMatches = Self.normalized(card.setCode) == Self.normalized(summary.setCode)
                    || Self.normalized(card.setName) == Self.normalized(summary.setName)
            }
            guard identityMatches else { return false }
            guard Self.treatmentIDs(for: card) == requiredTreatmentIDs
                || requiredTreatmentIDs.isEmpty else { return false }
            guard let required = summary.masterSetVariant else { return true }
            if card.variantID == nil && summary.isSoleSlotForCard { return true }
            return Self.masterVariantID(card.variantID) == Self.masterVariantID(required.id)
        }
    }

    func quantity(of summary: CatalogCardSummary) -> Int {
        candidates(for: summary)
            .filter { Self.matches($0, summary: summary) }
            .reduce(0) { $0 + $1.quantity }
    }

    func progress(for set: CatalogSet) -> SetCompletion {
        let ownedNumbers = Set(byNumber.values.flatMap { $0 }.compactMap { card -> String? in
            guard card.game == set.game,
                  card.itemKind.countsTowardSetCompletion,
                  !PokemonStampedReleaseCatalog.isStamped(variantID: card.variantID),
                  Self.pokemonPrintRunMatches(card, required: set.pokemonPrintRun) else { return nil }
            let code = Self.normalized(card.setCode)
            if code == Self.normalized(set.code) { return SetCompletionCalculator.canonicalNumber(card.cardNumber) }
            guard set.game == .pokemon else { return nil }
            let provider = (card.catalogProviderID ?? card.providerID).lowercased()
            return provider.hasPrefix(set.providerID.lowercased() + "-")
                ? SetCompletionCalculator.canonicalNumber(card.cardNumber)
                : nil
        })
        return SetCompletion(owned: ownedNumbers.count, total: set.cardCount, unit: "cards")
    }

    func progress(for slots: [CatalogCardSummary]) -> SetCompletion {
        SetCompletion(
            owned: slots.reduce(0) { $0 + (owns($1) ? 1 : 0) },
            total: slots.count,
            unit: "variations"
        )
    }

    /// Keys used to decide whether loading an on-disk Pokémon checklist can
    /// pay off. This deliberately exposes only normalized value data; the
    /// ownership buckets remain private to this index.
    func ownedSetKeys() -> (codes: Set<String>, providerIDs: Set<String>) {
        (ownedSetCodes, ownedProviderIDs)
    }

    /// Counts the positive collection rows belonging to each candidate set in
    /// one pass. The completion builder calls this before applying its forty
    /// set bound, so repeating a whole-collection scan once per candidate would
    /// defeat the bound on the directory's first-frame path.
    func ownedRowCounts(for sets: [CatalogSet]) -> [String: Int] {
        guard !sets.isEmpty, !completionRows.isEmpty else { return [:] }

        var setsByCode: [String: [CatalogSet]] = [:]
        var pokemonSetsByProviderPrefix: [String: [CatalogSet]] = [:]
        for set in sets {
            setsByCode[Self.normalizedKey(set.code), default: []].append(set)
            if set.game == .pokemon {
                pokemonSetsByProviderPrefix[Self.normalizedKey(set.providerID), default: []]
                    .append(set)
            }
        }

        var counts: [String: Int] = [:]
        for row in completionRows {
            guard row.quantity > 0,
                  !PokemonStampedReleaseCatalog.isStamped(variantID: row.variantID) else {
                continue
            }

            var matchingSetIDs: Set<String> = []
            for set in setsByCode[Self.normalizedKey(row.setCode)] ?? [] {
                guard row.game == set.game,
                      Self.pokemonPrintRunMatches(row, required: set.pokemonPrintRun) else {
                    continue
                }
                matchingSetIDs.insert(set.id)
            }

            if row.game == .pokemon {
                var providerIDs = Set([row.providerID])
                if let catalogProviderID = row.catalogProviderID {
                    providerIDs.insert(catalogProviderID)
                }
                for providerID in providerIDs {
                    for prefix in Self.providerSetPrefixes(Self.normalizedKey(providerID)) {
                        for set in pokemonSetsByProviderPrefix[prefix] ?? [] {
                            guard Self.pokemonPrintRunMatches(row, required: set.pokemonPrintRun) else {
                                continue
                            }
                            matchingSetIDs.insert(set.id)
                        }
                    }
                }
            }

            for setID in matchingSetIDs {
                counts[setID, default: 0] += 1
            }
        }
        return counts
    }

    func sealedQuantity(productID: String, variantID: String?) -> Int {
        bySealedProduct[Self.sealedKey(productID, variantID)] ?? 0
    }

    func matchingRows(for summary: CatalogCardSummary) -> [CatalogOwnershipCardSnapshot] {
        candidates(for: summary).filter { Self.matches($0, summary: summary) }
    }

    /// A match needs either the provider ID or the collector number, so nothing
    /// outside those two buckets can qualify.
    private func candidates(for summary: CatalogCardSummary) -> [CatalogOwnershipCardSnapshot] {
        var results = byProviderID[summary.providerID.lowercased()] ?? []
        guard let number = SetCompletionCalculator.canonicalNumber(summary.collectorNumber) else {
            return results
        }
        let seen = Set(results.map(\.collectionKey))
        results.append(contentsOf: (byNumber[number] ?? []).filter { !seen.contains($0.collectionKey) })
        return results
    }

    private static func matches(
        _ card: CatalogOwnershipCardSnapshot,
        summary: CatalogCardSummary
    ) -> Bool {
        guard card.itemKind.countsTowardSetCompletion,
              !PokemonStampedReleaseCatalog.isStamped(variantID: card.variantID),
              card.game == summary.game,
              card.quantity > 0,
              pokemonPrintRunMatches(card, required: summary.pokemonPrintRun) else { return false }
        let targetNumber = SetCompletionCalculator.canonicalNumber(summary.collectorNumber)
        let identityMatches = card.providerID.caseInsensitiveCompare(summary.providerID) == .orderedSame
            || card.catalogProviderID?.caseInsensitiveCompare(summary.providerID) == .orderedSame
            || (SetCompletionCalculator.canonicalNumber(card.cardNumber) == targetNumber
                && (normalized(card.setCode) == normalized(summary.setCode)
                    || normalized(card.setName) == normalized(summary.setName)))
        guard identityMatches else { return false }
        let required = Set(MagicTreatmentKeyCodec.canonicalIDs(from: summary.magicTreatmentIDsRaw))
        guard treatmentIDs(for: card) == required || required.isEmpty else { return false }
        guard let variant = summary.masterSetVariant else { return true }
        if card.variantID == nil && summary.isSoleSlotForCard { return true }
        return masterVariantID(card.variantID) == masterVariantID(variant.id)
    }

    private static func treatmentIDs(for card: CatalogOwnershipCardSnapshot) -> Set<String> {
        Set(MagicTreatmentKeyCodec.canonicalIDs(from: card.magicTreatmentIDsRaw))
    }

    private static func sealedKey(_ productID: String, _ variantID: String?) -> String {
        productID + "|" + (variantID ?? "")
    }

    private static func pokemonPrintRunMatches(
        _ card: CatalogOwnershipCardSnapshot,
        required: PokemonPrintRun?
    ) -> Bool {
        guard card.game == .pokemon else { return true }
        switch required {
        case .firstEdition: return card.pokemonPrintRun == .firstEdition
        case .shadowless: return card.pokemonPrintRun == .shadowless
        case .unlimited: return card.pokemonPrintRun == .unlimited || card.pokemonPrintRun == nil
        case nil: return card.pokemonPrintRun == nil
        }
    }

    private static func masterVariantID(_ variantID: String?) -> String {
        switch variantID {
        case PhysicalVariant.reverse.id: return PhysicalVariant.reverse.id
        case PhysicalVariant.pokeBall.id: return PhysicalVariant.pokeBall.id
        case PhysicalVariant.masterBall.id: return PhysicalVariant.masterBall.id
        case PhysicalVariant.duskBall.id: return PhysicalVariant.duskBall.id
        case PhysicalVariant.friendBall.id: return PhysicalVariant.friendBall.id
        case PhysicalVariant.quickBall.id: return PhysicalVariant.quickBall.id
        case PhysicalVariant.loveBall.id: return PhysicalVariant.loveBall.id
        case PhysicalVariant.normal.id, PhysicalVariant.firstEdition.id, nil:
            return PhysicalVariant.normal.id
        case let value?: return value
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func normalizedKey(_ value: String) -> String {
        normalized(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func providerSetPrefixes(_ providerID: String) -> [String] {
        let components = providerID.split(separator: "-", omittingEmptySubsequences: true)
        guard components.count > 1 else { return [] }
        return (1..<components.count).map { end in
            components[..<end].joined(separator: "-")
        }
    }
}

enum CatalogSetSort: String, CaseIterable, Identifiable, Sendable {
    case priceHighToLow
    case priceLowToHigh
    case numberLowToHigh
    case numberHighToLow

    var id: String { rawValue }
    var label: String {
        switch self {
        case .priceHighToLow: return "Price: High to Low"
        case .priceLowToHigh: return "Price: Low to High"
        case .numberLowToHigh: return "Card Number: Low to High"
        case .numberHighToLow: return "Card Number: High to Low"
        }
    }
    var needsPrices: Bool { self == .priceHighToLow || self == .priceLowToHigh }
}

enum CatalogOwnershipFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case owned
    case notOwned

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .owned: return "Owned"
        case .notOwned: return "Missing"
        }
    }
}

enum PokemonMasterSetTier: String, CaseIterable, Identifiable, Sendable {
    case standard
    case expanded

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var explanation: String {
        switch self {
        case .standard:
            return "Numbered cards, holos, reverse holos, and secret rares pulled from packs."
        case .expanded:
            return "Standard plus catalog-confirmed Poké Ball, Master Ball, and other pack parallels."
        }
    }
}

enum CatalogSetQuery {
    static func apply(
        _ cards: [CatalogCardSummary],
        search: String,
        sort: CatalogSetSort,
        ownership: CatalogOwnershipFilter,
        owned: CatalogOwnershipIndex,
        prices: [String: Double]
    ) -> [CatalogCardSummary] {
        let query = CardNameSearch.normalize(search)
        let filtered = cards.filter { card in
            let matchesSearch = query.isEmpty
                || CardNameSearch.normalize(card.name).contains(query)
                || CardNameSearch.normalize(card.collectorNumber).contains(query)
            guard matchesSearch else { return false }
            guard ownership != .all else { return true }
            let isOwned = owned.owns(card)
            switch ownership {
            case .all: return true
            case .owned: return isOwned
            case .notOwned: return !isOwned
            }
        }

        return filtered.sorted { left, right in
            switch sort {
            case .numberLowToHigh:
                return compareNumber(left, right) == .orderedAscending
            case .numberHighToLow:
                return compareNumber(left, right) == .orderedDescending
            case .priceHighToLow, .priceLowToHigh:
                let leftPrice = prices[left.id]
                let rightPrice = prices[right.id]
                switch (leftPrice, rightPrice) {
                case let (left?, right?) where left != right:
                    return sort == .priceHighToLow ? left > right : left < right
                case (_?, nil): return true
                case (nil, _?): return false
                default: return compareNumber(left, right) == .orderedAscending
                }
            }
        }
    }

    private static func compareNumber(_ left: CatalogCardSummary, _ right: CatalogCardSummary) -> ComparisonResult {
        let result = CollectorNumber.compare(left.collectorNumber, right.collectorNumber)
        if result != .orderedSame { return result }
        return left.id.compare(right.id)
    }
}

protocol BrowseCatalogProviding: Sendable {
    func sets(for game: CardGame) async throws -> [CatalogSet]
    func cards(in set: CatalogSet, cursor: String?) async throws -> CatalogPage<CatalogCardSummary>
    func searchCards(
        named query: String,
        game: CardGame,
        setIDs: Set<CatalogSetID>,
        cursor: String?
    ) async throws -> CatalogPage<CatalogCardSummary>
    func details(for summary: CatalogCardSummary) async throws -> CatalogCardDetails
    nonisolated func sortPrices(for cards: [CatalogCardSummary]) -> AsyncStream<[String: Double]>
    /// Starts an opportunistic local-snapshot refresh. Existing test doubles
    /// and non-Pokémon catalog implementations do not need to participate.
    func prepareCatalog() async
    /// Emits when a signed catalog revision or a per-set checklist becomes
    /// visible. Existing test doubles may use the empty default stream.
    func catalogUpdates() async -> AsyncStream<BrowseCatalogUpdate>
}

extension BrowseCatalogProviding {
    func prepareCatalog() async {}

    func catalogUpdates() async -> AsyncStream<BrowseCatalogUpdate> {
        AsyncStream { continuation in continuation.finish() }
    }
}
