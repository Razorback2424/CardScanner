import Foundation

public struct PokemonCatalogProviderCardCount: Codable, Equatable, Hashable, Sendable {
    public let total: Int
    public let official: Int
    public let normal: Int?
    public let reverse: Int?
    public let holo: Int?
    public let firstEd: Int?

    public init(
        total: Int,
        official: Int,
        normal: Int? = nil,
        reverse: Int? = nil,
        holo: Int? = nil,
        firstEd: Int? = nil
    ) {
        self.total = total
        self.official = official
        self.normal = normal
        self.reverse = reverse
        self.holo = holo
        self.firstEd = firstEd
    }
}

public struct PokemonCatalogProviderDirectoryRow: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let logo: String?
    public let symbol: String?
    public let cardCount: PokemonCatalogProviderCardCount?
    public let tcgOnline: String?
    /// Recorded fixtures can mark products such as Pokémon Pocket explicitly.
    /// A live adapter may set this from the provider's series endpoint before
    /// handing the rows to the core.
    public let isUnsupportedProduct: Bool

    public init(
        id: String,
        name: String,
        logo: String? = nil,
        symbol: String? = nil,
        cardCount: PokemonCatalogProviderCardCount? = nil,
        tcgOnline: String? = nil,
        isUnsupportedProduct: Bool = false
    ) {
        self.id = id
        self.name = name
        self.logo = logo
        self.symbol = symbol
        self.cardCount = cardCount
        self.tcgOnline = tcgOnline
        self.isUnsupportedProduct = isUnsupportedProduct
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, logo, symbol, cardCount, tcgOnline, isUnsupportedProduct
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        logo = try container.decodeIfPresent(String.self, forKey: .logo)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        cardCount = try container.decodeIfPresent(PokemonCatalogProviderCardCount.self, forKey: .cardCount)
        tcgOnline = try container.decodeIfPresent(String.self, forKey: .tcgOnline)
        isUnsupportedProduct = try container.decodeIfPresent(Bool.self, forKey: .isUnsupportedProduct) ?? false
    }
}

public struct PokemonCatalogProviderCardBrief: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let localID: String
    public let name: String
    public let image: String?

    public init(id: String, localID: String, name: String, image: String? = nil) {
        self.id = id
        self.localID = localID
        self.name = name
        self.image = image
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case localID = "localId"
        case name
        case image
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        if let string = try? container.decode(String.self, forKey: .localID) {
            localID = string
        } else {
            localID = String(try container.decode(Int.self, forKey: .localID))
        }
    }
}

public struct PokemonCatalogProviderSet: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let cards: [PokemonCatalogProviderCardBrief]
    public let logo: String?
    public let symbol: String?
    public let releaseDate: String?
    public let tcgOnline: String?
    public let cardCount: PokemonCatalogProviderCardCount?

    public init(
        id: String,
        name: String,
        cards: [PokemonCatalogProviderCardBrief],
        logo: String? = nil,
        symbol: String? = nil,
        releaseDate: String? = nil,
        tcgOnline: String? = nil,
        cardCount: PokemonCatalogProviderCardCount? = nil
    ) {
        self.id = id
        self.name = name
        self.cards = cards
        self.logo = logo
        self.symbol = symbol
        self.releaseDate = releaseDate
        self.tcgOnline = tcgOnline
        self.cardCount = cardCount
    }
}

public struct PokemonCatalogProviderCard: Codable, Equatable, Sendable {
    public let id: String
    public let localID: String
    public let name: String
    public let image: String?
    public let setID: String?

    public init(
        id: String,
        localID: String,
        name: String,
        image: String? = nil,
        setID: String? = nil
    ) {
        self.id = id
        self.localID = localID
        self.name = name
        self.image = image
        self.setID = setID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case localID = "localId"
        case name
        case image
        case setID
        case set
    }

    private struct SetReference: Decodable {
        let id: String
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        if let string = try? container.decode(String.self, forKey: .localID) {
            localID = string
        } else {
            localID = String(try container.decode(Int.self, forKey: .localID))
        }
        setID = try container.decodeIfPresent(String.self, forKey: .setID)
            ?? (try? container.decode(SetReference.self, forKey: .set))?.id
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(localID, forKey: .localID)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encodeIfPresent(setID, forKey: .setID)
    }
}

public struct PokemonCatalogProviderFixture: Codable, Equatable, Sendable {
    public let directory: [PokemonCatalogProviderDirectoryRow]
    public let sets: [PokemonCatalogProviderSet]
    public let cards: [PokemonCatalogProviderCard]

    public init(
        directory: [PokemonCatalogProviderDirectoryRow],
        sets: [PokemonCatalogProviderSet],
        cards: [PokemonCatalogProviderCard]
    ) {
        self.directory = directory
        self.sets = sets
        self.cards = cards
    }
}

/// Human-entered facts are kept separate from provider data in the input file.
/// In particular, a provider row can never silently become a scanner code.
public struct PokemonCatalogHumanInput: Codable, Equatable, Sendable {
    public let providerSetID: String
    public let recognitionKind: PokemonCatalogSetDescriptor.RecognitionKind
    public let printedCode: String?
    public let claimedOfficialCount: Int?
    public let printedPrefix: String?
    public let catalogLocalIDPrefix: String?
    public let localIDPadWidth: Int?
    public let displayName: String?
    public let releaseDate: String?
    public let releaseOrder: Int?
    public let scanEnabled: Bool
    public let logoURL: String?
    public let symbolURL: String?
    public let rulesVersion: Int

    public init(
        providerSetID: String,
        recognitionKind: PokemonCatalogSetDescriptor.RecognitionKind,
        printedCode: String? = nil,
        claimedOfficialCount: Int? = nil,
        printedPrefix: String? = nil,
        catalogLocalIDPrefix: String? = nil,
        localIDPadWidth: Int? = nil,
        displayName: String? = nil,
        releaseDate: String? = nil,
        releaseOrder: Int? = nil,
        scanEnabled: Bool = true,
        logoURL: String? = nil,
        symbolURL: String? = nil,
        rulesVersion: Int = PokemonCatalogCoreContract.rulesVersion
    ) {
        self.providerSetID = providerSetID
        self.recognitionKind = recognitionKind
        self.printedCode = printedCode
        self.claimedOfficialCount = claimedOfficialCount
        self.printedPrefix = printedPrefix
        self.catalogLocalIDPrefix = catalogLocalIDPrefix
        self.localIDPadWidth = localIDPadWidth
        self.displayName = displayName
        self.releaseDate = releaseDate
        self.releaseOrder = releaseOrder
        self.scanEnabled = scanEnabled
        self.logoURL = logoURL
        self.symbolURL = symbolURL
        self.rulesVersion = rulesVersion
    }
}

public struct PokemonCatalogHumanInputFile: Codable, Equatable, Sendable {
    public let sets: [PokemonCatalogHumanInput]

    public init(sets: [PokemonCatalogHumanInput]) {
        self.sets = sets
    }
}
