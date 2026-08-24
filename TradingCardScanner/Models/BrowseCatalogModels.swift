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

    private static func belongs(_ card: CollectedCard, to set: CatalogSet) -> Bool {
        guard card.cardGame == set.game else { return false }

        let normalizedCardCode = card.setCode.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let normalizedSetCode = set.code.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
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
}
