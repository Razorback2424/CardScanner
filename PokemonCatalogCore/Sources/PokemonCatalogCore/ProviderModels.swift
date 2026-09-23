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

/// The nested metadata TCGdex publishes on detailed set responses. These
/// values are provider evidence only; the publisher validates any proposed
/// code before it can enter a signed release.
public struct PokemonCatalogProviderSeries: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String?

    public init(id: String, name: String? = nil) {
        self.id = id
        self.name = name
    }
}

public struct PokemonCatalogProviderAbbreviation: Codable, Equatable, Hashable, Sendable {
    public let official: String?

    public init(official: String? = nil) {
        self.official = official
    }
}

public struct PokemonCatalogProviderDirectoryRow: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let logo: String?
    public let symbol: String?
    public let cardCount: PokemonCatalogProviderCardCount?
    public let releaseDate: String?
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
        releaseDate: String? = nil,
        tcgOnline: String? = nil,
        isUnsupportedProduct: Bool = false
    ) {
        self.id = id
        self.name = name
        self.logo = logo
        self.symbol = symbol
        self.cardCount = cardCount
        self.releaseDate = releaseDate
        self.tcgOnline = tcgOnline
        self.isUnsupportedProduct = isUnsupportedProduct
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, logo, symbol, cardCount, releaseDate, tcgOnline, isUnsupportedProduct
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        logo = try container.decodeIfPresent(String.self, forKey: .logo)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        cardCount = try container.decodeIfPresent(PokemonCatalogProviderCardCount.self, forKey: .cardCount)
        releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate)
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

/// The flat variant flags TCGdex publishes on a detailed card. These fields
/// affect the physical rows the app expands from one provider card.
public struct PokemonCatalogProviderVariants: Codable, Equatable, Hashable, Sendable {
    public let firstEdition: Bool
    public let holo: Bool
    public let normal: Bool
    public let reverse: Bool
    public let wPromo: Bool?

    public init(
        firstEdition: Bool,
        holo: Bool,
        normal: Bool,
        reverse: Bool,
        wPromo: Bool? = nil
    ) {
        self.firstEdition = firstEdition
        self.holo = holo
        self.normal = normal
        self.reverse = reverse
        self.wPromo = wPromo
    }
}

/// Only the detailed-variant fields that can affect checklist expansion are
/// retained. Pricing and marketplace identifiers are intentionally excluded.
public struct PokemonCatalogProviderDetailedVariant: Codable, Equatable, Hashable, Sendable {
    public let type: String?
    public let subtype: String?
    public let stamp: [String]?
    public let foil: String?
    public let size: String?
    public let variantID: String?
    public let languages: [String]?

    public init(
        type: String?,
        subtype: String?,
        stamp: [String]?,
        foil: String?,
        size: String?,
        variantID: String?,
        languages: [String]?
    ) {
        self.type = type
        self.subtype = subtype
        self.stamp = stamp
        self.foil = foil
        self.size = size
        self.variantID = variantID
        self.languages = languages
    }

    private enum CodingKeys: String, CodingKey {
        case type, subtype, stamp, foil, size
        case variantID = "variantId"
        case languages
    }
}

/// Publisher-only per-card artwork evidence. It is intentionally not
/// Codable: the provider fingerprint must remain reproducible from TCGdex
/// data on the device, while the signed descriptor carries the approved URLs.
public struct PokemonCatalogResolvedCardArtwork: Equatable, Sendable {
    public enum Source: String, Equatable, Hashable, Sendable {
        case tcgdexCardDetail
        case secondaryProvider
    }

    public let thumbnail: String
    public let image: String
    public let source: Source

    public init(
        thumbnail: String,
        image: String,
        source: Source = .secondaryProvider
    ) {
        self.thumbnail = thumbnail
        self.image = image
        self.source = source
    }

    public var thumbnailURL: String { thumbnail }
    public var imageURL: String { image }
}

public struct PokemonCatalogProviderSet: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let cards: [PokemonCatalogProviderCardBrief]
    /// Raw values decoded from the provider set payload. These are the only
    /// artwork values that may participate in the provider fingerprint.
    public let logo: String?
    public let symbol: String?
    /// Publisher-only artwork enrichment. These fields are intentionally not
    /// part of the Codable provider payload or provider fingerprint.
    public let resolvedLogo: String?
    public let resolvedSymbol: String?
    public let resolvedCardArtworkURLs: [String]?
    public let resolvedCardArtworkByLocalID: [String: PokemonCatalogResolvedCardArtwork]?
    /// Unsigned diagnostic provenance for the resolved artwork. It is never
    /// part of the provider payload or fingerprint.
    public let resolvedArtworkSource: String?
    public let releaseDate: String?
    public let tcgOnline: String?
    public let cardCount: PokemonCatalogProviderCardCount?
    /// TCGdex uses the JSON key `serie` for this nested value.
    public let serie: PokemonCatalogProviderSeries?
    public let abbreviation: PokemonCatalogProviderAbbreviation?

    public init(
        id: String,
        name: String,
        cards: [PokemonCatalogProviderCardBrief],
        logo: String? = nil,
        symbol: String? = nil,
        releaseDate: String? = nil,
        tcgOnline: String? = nil,
        cardCount: PokemonCatalogProviderCardCount? = nil,
        serie: PokemonCatalogProviderSeries? = nil,
        abbreviation: PokemonCatalogProviderAbbreviation? = nil,
        resolvedLogo: String? = nil,
        resolvedSymbol: String? = nil,
        resolvedCardArtworkURLs: [String]? = nil,
        resolvedCardArtworkByLocalID: [String: PokemonCatalogResolvedCardArtwork]? = nil,
        resolvedArtworkSource: String? = nil
    ) {
        self.id = id
        self.name = name
        self.cards = cards
        self.logo = logo
        self.symbol = symbol
        self.resolvedLogo = resolvedLogo
        self.resolvedSymbol = resolvedSymbol
        self.resolvedCardArtworkURLs = resolvedCardArtworkURLs
        self.resolvedCardArtworkByLocalID = resolvedCardArtworkByLocalID
        self.resolvedArtworkSource = resolvedArtworkSource
        self.releaseDate = releaseDate
        self.tcgOnline = tcgOnline
        self.cardCount = cardCount
        self.serie = serie
        self.abbreviation = abbreviation
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, cards, logo, symbol, releaseDate, tcgOnline, cardCount
        case serie, abbreviation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        cards = try container.decode([PokemonCatalogProviderCardBrief].self, forKey: .cards)
        logo = try container.decodeIfPresent(String.self, forKey: .logo)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        resolvedLogo = nil
        resolvedSymbol = nil
        resolvedCardArtworkURLs = nil
        resolvedCardArtworkByLocalID = nil
        resolvedArtworkSource = nil
        releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate)
        tcgOnline = try container.decodeIfPresent(String.self, forKey: .tcgOnline)
        cardCount = try container.decodeIfPresent(
            PokemonCatalogProviderCardCount.self,
            forKey: .cardCount
        )
        serie = try container.decodeIfPresent(
            PokemonCatalogProviderSeries.self,
            forKey: .serie
        )
        abbreviation = try container.decodeIfPresent(
            PokemonCatalogProviderAbbreviation.self,
            forKey: .abbreviation
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(cards, forKey: .cards)
        try container.encodeIfPresent(logo, forKey: .logo)
        try container.encodeIfPresent(symbol, forKey: .symbol)
        try container.encodeIfPresent(releaseDate, forKey: .releaseDate)
        try container.encodeIfPresent(tcgOnline, forKey: .tcgOnline)
        try container.encodeIfPresent(cardCount, forKey: .cardCount)
        try container.encodeIfPresent(serie, forKey: .serie)
        try container.encodeIfPresent(abbreviation, forKey: .abbreviation)
    }
}

public struct PokemonCatalogProviderCard: Codable, Equatable, Sendable {
    public let id: String
    public let localID: String
    public let name: String
    public let image: String?
    public let setID: String?
    public let variants: PokemonCatalogProviderVariants?
    public let variantsDetailed: [PokemonCatalogProviderDetailedVariant]?

    public init(
        id: String,
        localID: String,
        name: String,
        image: String? = nil,
        setID: String? = nil,
        variants: PokemonCatalogProviderVariants? = nil,
        variantsDetailed: [PokemonCatalogProviderDetailedVariant]? = nil
    ) {
        self.id = id
        self.localID = localID
        self.name = name
        self.image = image
        self.setID = setID
        self.variants = variants
        self.variantsDetailed = variantsDetailed
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case localID = "localId"
        case name
        case image
        case setID
        case set
        case variants
        case variantsDetailed = "variants_detailed"
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
        variants = try container.decodeIfPresent(
            PokemonCatalogProviderVariants.self,
            forKey: .variants
        )
        variantsDetailed = try container.decodeIfPresent(
            [PokemonCatalogProviderDetailedVariant].self,
            forKey: .variantsDetailed
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(localID, forKey: .localID)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encodeIfPresent(setID, forKey: .setID)
        try container.encodeIfPresent(variants, forKey: .variants)
        try container.encodeIfPresent(variantsDetailed, forKey: .variantsDetailed)
    }
}

public struct PokemonCatalogProviderFixture: Codable, Equatable, Sendable {
    public let directory: [PokemonCatalogProviderDirectoryRow]
    public let sets: [PokemonCatalogProviderSet]
    public let cards: [PokemonCatalogProviderCard]
    public let secondary: PokemonCatalogSecondaryFixture?

    public init(
        directory: [PokemonCatalogProviderDirectoryRow],
        sets: [PokemonCatalogProviderSet],
        cards: [PokemonCatalogProviderCard],
        secondary: PokemonCatalogSecondaryFixture? = nil
    ) {
        self.directory = directory
        self.sets = sets
        self.cards = cards
        self.secondary = secondary
    }
}

/// Compatibility model for operator overrides and fallback policy kept separate
/// from provider evidence. Ordinary expansions may derive their code without a
/// row here; a provider value still cannot become scanner authority until the
/// publisher validates and signs the release.
public struct PokemonCatalogHumanInput: Codable, Equatable, Sendable {
    /// Compatibility name for the operator override/fallback file. The input
    /// is not the scanner authority; only a validated signed release is.
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
    /// Manual, protected relationship used when a provider gallery set has no
    /// usable artwork of its own. The publisher resolves the parent's final
    /// artwork URL before it enters the signed descriptor.
    public let parentProviderSetID: String?
    public let bundledArtworkSourceID: String?
    public let rulesVersion: Int
    public let membershipRecognition: PokemonCatalogMembershipRecognition?

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
        parentProviderSetID: String? = nil,
        bundledArtworkSourceID: String? = nil,
        rulesVersion: Int = PokemonCatalogCoreContract.rulesVersion,
        membershipRecognition: PokemonCatalogMembershipRecognition? = nil
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
        self.parentProviderSetID = parentProviderSetID
        self.bundledArtworkSourceID = bundledArtworkSourceID
        self.rulesVersion = rulesVersion
        self.membershipRecognition = membershipRecognition
    }
}

public struct PokemonCatalogHumanInputFile: Codable, Equatable, Sendable {
    public let sets: [PokemonCatalogHumanInput]

    public init(sets: [PokemonCatalogHumanInput]) {
        self.sets = sets
    }
}
