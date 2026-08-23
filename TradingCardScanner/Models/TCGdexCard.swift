import Foundation

struct TCGdexCard: Decodable, Identifiable, Sendable {
    let id: String
    let localId: String
    let name: String
    let image: String?
    let rarity: String?
    let set: TCGdexSetBrief
    /// Optional on purpose. A record that omits variants is a catalog that has
    /// nothing to say about finish — which the resolver records honestly. Making
    /// it required turned a missing field into a failed identification.
    let variants: TCGdexVariants?
    let pricing: TCGdexPricing?

    enum CodingKeys: String, CodingKey {
        case id, localId, name, image, rarity, set, variants, pricing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        rarity = try container.decodeIfPresent(String.self, forKey: .rarity)
        set = try container.decode(TCGdexSetBrief.self, forKey: .set)
        variants = try container.decodeIfPresent(TCGdexVariants.self, forKey: .variants)
        pricing = try container.decodeIfPresent(TCGdexPricing.self, forKey: .pricing)

        if let stringValue = try? container.decode(String.self, forKey: .localId) {
            localId = stringValue
        } else {
            let intValue = try container.decode(Int.self, forKey: .localId)
            localId = String(intValue)
        }
    }

    var highImageURL: URL? {
        guard let image else { return nil }
        return URL(string: image + "/high.png")
    }

    /// What TCGdex says this printing physically exists as. The supplemental
    /// rules layer may widen this for sets whose parallel patterns TCGdex does
    /// not model; it is never widened here.
    var catalogVariants: [PhysicalVariant] {
        guard let variants else { return [] }
        var result: [PhysicalVariant] = []
        if variants.normal { result.append(.normal) }
        if variants.holo { result.append(.holo) }
        if variants.reverse { result.append(.reverse) }
        if variants.firstEdition { result.append(.firstEdition) }
        return result
    }
}

struct CardMarketPrice: Identifiable, Equatable, Sendable {
    /// Which `PhysicalVariant` this price belongs to, when the catalog says so.
    let variantID: String?
    let label: String
    let value: Double

    var id: String { label }
}

struct TCGdexSetBrief: Decodable, Sendable {
    let id: String
    let name: String
    let cardCount: TCGdexCardCount
}

struct TCGdexCardCount: Decodable, Sendable {
    let total: Int
    let official: Int
}

struct TCGdexVariants: Decodable, Sendable {
    let firstEdition: Bool
    let holo: Bool
    let normal: Bool
    let reverse: Bool
    let wPromo: Bool?
}

struct TCGdexPricing: Decodable, Sendable {
    let tcgplayer: TCGPlayerPricing?
}

struct TCGPlayerPricing: Decodable, Sendable {
    /// When TCGplayer's data is current through, per TCGdex. This is not the same
    /// fact as when this app fetched it, and the two must never be presented as
    /// one — a price checked at 3:20pm whose market data is from 1:07pm is
    /// current *as of 1:07pm*.
    let updated: String?
    let normal: TCGPlayerPricePoint?
    let holo: TCGPlayerPricePoint?
    let holofoil: TCGPlayerPricePoint?
    let reverse: TCGPlayerPricePoint?
    let reverseHolofoil: TCGPlayerPricePoint?

    enum CodingKeys: String, CodingKey {
        case updated
        case normal
        case holo
        case holofoil
        case reverse
        case reverseHolofoil = "reverse-holofoil"
    }

    var updatedAt: Date? {
        updated.flatMap(FlexibleDate.parse)
    }
}

/// Provider timestamp formats vary and change. Parsing leniently and returning
/// `nil` on anything unrecognised keeps a format change from turning into a
/// false freshness claim.
enum FlexibleDate {
    private static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dayOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dayAndTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func parse(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return isoWithFraction.date(from: trimmed)
            ?? iso.date(from: trimmed)
            ?? dayAndTime.date(from: trimmed)
            ?? dayOnly.date(from: trimmed)
    }
}

struct TCGPlayerPricePoint: Decodable, Sendable {
    let marketPrice: Double?
}

/// The exact Scryfall printing returned by the direct set/number/language lookup.
struct ScryfallCard: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let setCode: String
    let setName: String
    let collectorNumber: String
    let language: String
    let digital: Bool
    /// Kept for diagnostics only. Frame is a cosmetic fact and deliberately does
    /// not decide whether a printing is supported.
    let frame: String?
    /// Whether this is a single scannable card at all, as opposed to a token,
    /// emblem or art-series print.
    let layout: String?
    let rarity: String?
    /// Scryfall publishes exactly which finishes a printing exists in
    /// (`nonfoil`, `foil`, `etched`). That is authoritative physical-variant
    /// data, so `PhysicalVariant` ids for Magic are these strings verbatim —
    /// there is no translation table to fall out of date.
    let finishes: [String]?
    /// Printing release date. Scryfall publishes it per card, which is what lets
    /// Magic sets be grouped in release order without a local set directory.
    let releasedAt: String?
    /// Scryfall publishes prices as strings and does not stamp them with its own
    /// "current through" time, so this app may only report when *it* checked.
    let prices: ScryfallPrices?
    let imageURIs: ScryfallImageURIs?
    let cardFaces: [ScryfallCardFace]?

    enum CodingKeys: String, CodingKey {
        case id, name, digital, frame, layout, rarity, finishes, prices
        case setCode = "set"
        case setName = "set_name"
        case collectorNumber = "collector_number"
        case language = "lang"
        case releasedAt = "released_at"
        case imageURIs = "image_uris"
        case cardFaces = "card_faces"
    }

    var releaseDate: Date? {
        releasedAt.flatMap(FlexibleDate.parse)
    }

    var catalogVariants: [PhysicalVariant] {
        (finishes ?? []).map(PhysicalVariant.resolving)
    }

    /// DFCs put images on faces rather than the card root. The front is enough
    /// for MVP and does not need a special scanning path.
    var displayImageURL: URL? {
        imageURIs?.normal ?? cardFaces?.first?.imageURIs?.normal
    }

    var thumbnailImageURL: URL? {
        imageURIs?.small ?? cardFaces?.first?.imageURIs?.small ?? displayImageURL
    }
}

struct ScryfallPrices: Decodable, Sendable {
    let usd: String?
    let usdFoil: String?
    let usdEtched: String?

    enum CodingKeys: String, CodingKey {
        case usd
        case usdFoil = "usd_foil"
        case usdEtched = "usd_etched"
    }

    func value(forKey key: String) -> Double? {
        switch key {
        case "usd": return usd.flatMap(Double.init)
        case "usd_foil": return usdFoil.flatMap(Double.init)
        case "usd_etched": return usdEtched.flatMap(Double.init)
        default: return nil
        }
    }
}

struct ScryfallCardFace: Decodable, Sendable {
    let imageURIs: ScryfallImageURIs?
    enum CodingKeys: String, CodingKey { case imageURIs = "image_uris" }
}

struct ScryfallImageURIs: Decodable, Sendable {
    let small: URL?
    let normal: URL?
}

/// A provider-neutral value used by the scanner session and collection UI.
enum IdentifiedCard: Identifiable, Sendable {
    case pokemon(TCGdexCard, setCode: String)
    case magic(ScryfallCard)

    var id: String {
        switch self {
        case let .pokemon(card, _): return "pokemon:\(card.id)"
        case let .magic(card): return "magic:\(card.id)"
        }
    }

    var game: CardGame {
        switch self {
        case .pokemon: return .pokemon
        case .magic: return .magic
        }
    }

    var providerID: String {
        switch self {
        case let .pokemon(card, _): return card.id
        case let .magic(card): return card.id
        }
    }

    /// The row a scan mutates.
    ///
    /// A Master Ball copy and a plain reverse copy of one printing are different
    /// physical objects and must not share a quantity. The legacy bare-provider
    /// key is preserved when no variant is known, so a collection built before
    /// finish resolution keeps incrementing the row it already has.
    func collectionKey(variant: PhysicalVariant?) -> String {
        switch self {
        case let .pokemon(card, _):
            return variant.map { "\(card.id)#\($0.id)" } ?? card.id
        case let .magic(card):
            return variant.map { "magic:\(card.id)#\($0.id)" } ?? "magic:\(card.id)"
        }
    }

    var name: String {
        switch self {
        case let .pokemon(card, _): return card.name
        case let .magic(card): return card.name
        }
    }

    var setName: String {
        switch self {
        case let .pokemon(card, _): return card.set.name
        case let .magic(card): return card.setName
        }
    }

    var setCode: String {
        switch self {
        case let .pokemon(_, setCode): return setCode
        case let .magic(card): return card.setCode.uppercased()
        }
    }

    var cardNumber: String {
        switch self {
        case let .pokemon(card, _): return card.localId
        case let .magic(card): return card.collectorNumber
        }
    }

    var identifier: String {
        switch self {
        case let .pokemon(card, setCode):
            return "\(setCode) \(card.localId)/\(card.set.cardCount.official)"
        case let .magic(card):
            return "\(card.setCode.uppercased()) \(card.collectorNumber)"
        }
    }

    var rarity: String? {
        switch self {
        case let .pokemon(card, _): return card.rarity
        case let .magic(card): return card.rarity
        }
    }

    var displayImageURL: URL? {
        switch self {
        case let .pokemon(card, _): return card.highImageURL
        case let .magic(card): return card.displayImageURL
        }
    }

    var thumbnailImageURL: URL? {
        switch self {
        case let .pokemon(card, _):
            guard let image = card.image else { return nil }
            return URL(string: image + "/low.png")
        case let .magic(card): return card.thumbnailImageURL
        }
    }

    var marketPrices: [CardMarketPrice] {
        CardPricing.publishedPrices(for: self)
    }

    /// Release ordering for "Set + Card Number". Pokémon uses the position in the
    /// local set table; Magic uses the printing's release date. Both grow with
    /// time, and sorting always groups by game first so the two scales are never
    /// compared against each other.
    var setReleaseOrder: Int {
        switch self {
        case let .pokemon(_, setCode):
            return SetCodeMap.releaseIndex(forPrintedCode: setCode) ?? 0
        case let .magic(card):
            guard let date = card.releaseDate else { return 0 }
            return Int(date.timeIntervalSince1970 / 86_400)
        }
    }

    /// The only thing the variant resolver is ever shown.
    var variantEvidence: VariantEvidence {
        switch self {
        case let .pokemon(card, _):
            return VariantEvidence(
                game: .pokemon,
                setID: card.set.id,
                cardNumber: card.localId,
                catalogVariants: card.catalogVariants
            )
        case let .magic(card):
            return VariantEvidence(
                game: .magic,
                setID: card.setCode.lowercased(),
                cardNumber: card.collectorNumber,
                catalogVariants: card.catalogVariants
            )
        }
    }
}
