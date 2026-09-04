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
struct CatalogOwnershipIndex {
    private var byNumber: [String: [CollectedCard]] = [:]
    private var byProviderID: [String: [CollectedCard]] = [:]

    init(_ cards: [CollectedCard]) {
        for card in cards where card.itemKind.countsTowardSetCompletion && card.quantity > 0 {
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
        SetCompletionCalculator.owns(summary, cards: candidates(for: summary))
    }

    func quantity(of summary: CatalogCardSummary) -> Int {
        candidates(for: summary).reduce(0) { total, card in
            total + (SetCompletionCalculator.owns(summary, cards: [card]) ? card.quantity : 0)
        }
    }

    /// A match needs either the provider ID or the collector number, so nothing
    /// outside those two buckets can qualify.
    private func candidates(for summary: CatalogCardSummary) -> [CollectedCard] {
        var results = byProviderID[summary.providerID.lowercased()] ?? []
        guard let number = SetCompletionCalculator.canonicalNumber(summary.collectorNumber) else {
            return results
        }
        var seen = Set(results.map(ObjectIdentifier.init))
        for card in byNumber[number] ?? [] where seen.insert(ObjectIdentifier(card)).inserted {
            results.append(card)
        }
        return results
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
    func sortPrices(for cards: [CatalogCardSummary]) async -> [String: Double]
    /// Starts an opportunistic local-snapshot refresh. Existing test doubles
    /// and non-Pokémon catalog implementations do not need to participate.
    func prepareCatalog() async
}

extension BrowseCatalogProviding {
    func prepareCatalog() async {}
}
