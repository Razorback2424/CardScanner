import Foundation

struct CatalogSetID: Hashable, Identifiable, Sendable {
    let game: CardGame
    let providerID: String

    var id: String { "\(game.rawValue):\(providerID.lowercased())" }
}

struct CatalogSet: Identifiable, Hashable, Sendable {
    let catalogID: CatalogSetID
    let name: String
    let code: String
    let logoURL: URL?
    let symbolURL: URL?
    let cardCount: Int?
    let releaseDate: Date?
    let sortRank: Int

    var id: String { catalogID.id }
    var game: CardGame { catalogID.game }
    var providerID: String { catalogID.providerID }
    var releaseOrder: Int {
        game == .pokemon
            ? sortRank
            : releaseDate.map { Int($0.timeIntervalSince1970 / 86_400) } ?? sortRank
    }
}

struct CatalogCardSummary: Identifiable, Hashable, Sendable {
    let game: CardGame
    let providerID: String
    let setID: CatalogSetID
    let setName: String
    let setCode: String
    let name: String
    let collectorNumber: String
    let thumbnailURL: URL?
    let imageURL: URL?

    var id: String { "\(game.rawValue):\(providerID)" }
}

struct CatalogCardDetails: Sendable {
    let card: IdentifiedCard
    let set: CatalogSet
}

struct CatalogPage<Element: Sendable>: Sendable {
    let items: [Element]
    let nextCursor: String?
}

struct SetCompletion: Equatable, Sendable {
    let owned: Int
    let total: Int?

    var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(Double(owned) / Double(total), 1)
    }

    var label: String {
        total.map { "\(owned)/\($0) cards" } ?? "\(owned)/— cards"
    }
}

/// Set completion counts distinct collector numbers, not physical variants or
/// quantities. That keeps the numerator on the same scale as the provider's
/// set card count: three finishes of card 074 are one completed card.
enum SetCompletionCalculator {
    static func progress(for set: CatalogSet, cards: [CollectedCard]) -> SetCompletion {
        let numbers = Set(cards.compactMap { card -> String? in
            guard belongs(card, to: set) else { return nil }
            return canonicalNumber(card.cardNumber)
        })
        return SetCompletion(owned: numbers.count, total: set.cardCount)
    }

    static func owns(_ summary: CatalogCardSummary, cards: [CollectedCard]) -> Bool {
        guard let targetNumber = canonicalNumber(summary.collectorNumber) else { return false }
        let targetProviderID = summary.providerID.lowercased()
        return cards.contains { card in
            guard card.itemKind.countsTowardSetCompletion else { return false }
            guard card.cardGame == summary.game, card.quantity > 0 else { return false }
            if card.providerID.lowercased() == targetProviderID
                || card.catalogProviderID?.lowercased() == targetProviderID {
                return true
            }
            guard canonicalNumber(card.cardNumber) == targetNumber else { return false }
            let cardCode = normalized(card.setCode)
            return cardCode == normalized(summary.setCode)
                || normalized(card.setName) == normalized(summary.setName)
        }
    }

    private static func belongs(_ card: CollectedCard, to set: CatalogSet) -> Bool {
        // A sealed product is not a card and completes no slot. Graded copies do
        // count, and because progress is measured over a *set* of collector
        // numbers, a raw and a graded copy of the same card count once between
        // them — owning three grades of one card cannot inflate completion.
        guard card.itemKind.countsTowardSetCompletion else { return false }
        guard card.cardGame == set.game else { return false }

        let normalizedCardCode = normalized(card.setCode)
        let normalizedSetCode = normalized(set.code)
        if normalizedCardCode == normalizedSetCode { return true }

        guard set.game == .pokemon else { return false }
        let providerID = card.catalogProviderID ?? card.providerID
        return providerID.lowercased().hasPrefix(set.providerID.lowercased() + "-")
    }

    private static func canonicalNumber(_ value: String) -> String? {
        let printed = value.split(separator: "/", maxSplits: 1).first.map(String.init) ?? value
        let trimmed = printed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed).map(String.init) ?? trimmed.lowercased()
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
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
        case .all: return "All Products"
        case .owned: return "Products Owned"
        case .notOwned: return "Products Not Owned"
        }
    }
}

enum CatalogSetQuery {
    static func apply(
        _ cards: [CatalogCardSummary],
        search: String,
        sort: CatalogSetSort,
        ownership: CatalogOwnershipFilter,
        ownedCards: [CollectedCard],
        prices: [String: Double]
    ) -> [CatalogCardSummary] {
        let query = CardNameSearch.normalize(search)
        let filtered = cards.filter { card in
            let matchesSearch = query.isEmpty
                || CardNameSearch.normalize(card.name).contains(query)
                || CardNameSearch.normalize(card.collectorNumber).contains(query)
            guard matchesSearch else { return false }
            let isOwned = SetCompletionCalculator.owns(card, cards: ownedCards)
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
}
