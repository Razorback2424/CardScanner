import Foundation

/// The small set-level identity and artwork surface used from the secondary
/// Pokémon catalog. It is evidence only; it never grants scanner authority.
public struct PokemonCatalogSecondarySet: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let ptcgoCode: String?
    public let releaseDate: String?
    public let printedTotal: Int?
    public let total: Int?
    public let logoURL: String?
    public let symbolURL: String?
    public let cardArtworkURLs: [String]

    public init(
        id: String,
        name: String,
        ptcgoCode: String? = nil,
        releaseDate: String? = nil,
        printedTotal: Int? = nil,
        total: Int? = nil,
        logoURL: String? = nil,
        symbolURL: String? = nil,
        cardArtworkURLs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.ptcgoCode = ptcgoCode
        self.releaseDate = releaseDate
        self.printedTotal = printedTotal
        self.total = total
        self.logoURL = logoURL
        self.symbolURL = symbolURL
        self.cardArtworkURLs = cardArtworkURLs
    }
}

/// Per-card artwork evidence from the secondary catalog. The original
/// printed number is retained for diagnostics, but matching to TCGdex is
/// name-based because the two providers use different numbering schemes.
public struct PokemonCatalogSecondaryCard: Codable, Equatable, Hashable, Sendable {
    public let number: String
    public let name: String
    public let thumbnailURL: String?
    public let imageURL: String?

    public init(
        number: String,
        name: String,
        thumbnailURL: String? = nil,
        imageURL: String? = nil
    ) {
        self.number = number
        self.name = name
        self.thumbnailURL = thumbnailURL
        self.imageURL = imageURL
    }
}

/// Optional recorded secondary evidence. Keeping it optional makes older
/// fixtures decode unchanged and keeps the offline validation lane network-free.
public struct PokemonCatalogSecondaryFixture: Codable, Equatable, Sendable {
    public let sets: [PokemonCatalogSecondarySet]
    public let cards: [PokemonCatalogSecondaryCard]?
    public let ambiguousSetIDs: [String]

    public init(
        sets: [PokemonCatalogSecondarySet],
        cards: [PokemonCatalogSecondaryCard]? = nil,
        ambiguousSetIDs: [String] = []
    ) {
        self.sets = sets
        self.cards = cards
        self.ambiguousSetIDs = ambiguousSetIDs
    }
}
