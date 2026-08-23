import Foundation

struct TCGdexCard: Decodable, Identifiable {
    let id: String
    let localId: String
    let name: String
    let image: String?
    let rarity: String?
    let set: TCGdexSetBrief
    let variants: TCGdexVariants
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
        variants = try container.decode(TCGdexVariants.self, forKey: .variants)
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

    /// The MVP does not yet detect physical finish. Never guess one market price;
    /// expose each available TCGplayer variant with an explicit label instead.
    var marketPrices: [CardMarketPrice] {
        guard let tcg = pricing?.tcgplayer else { return [] }

        var prices: [CardMarketPrice] = []

        if variants.normal, let price = tcg.normal?.marketPrice {
            prices.append(.init(label: "Normal", value: price))
        }

        if variants.holo, let price = tcg.holofoil?.marketPrice ?? tcg.holo?.marketPrice {
            prices.append(.init(label: "Holofoil", value: price))
        }

        if variants.reverse, let price = tcg.reverseHolofoil?.marketPrice ?? tcg.reverse?.marketPrice {
            prices.append(.init(label: "Reverse Holofoil", value: price))
        }

        return prices
    }
}

struct CardMarketPrice: Identifiable, Equatable {
    let label: String
    let value: Double

    var id: String { label }
}

struct TCGdexSetBrief: Decodable {
    let id: String
    let name: String
    let cardCount: TCGdexCardCount
}

struct TCGdexCardCount: Decodable {
    let total: Int
    let official: Int
}

struct TCGdexVariants: Decodable {
    let firstEdition: Bool
    let holo: Bool
    let normal: Bool
    let reverse: Bool
    let wPromo: Bool?
}

struct TCGdexPricing: Decodable {
    let tcgplayer: TCGPlayerPricing?
}

struct TCGPlayerPricing: Decodable {
    let normal: TCGPlayerPricePoint?
    let holo: TCGPlayerPricePoint?
    let holofoil: TCGPlayerPricePoint?
    let reverse: TCGPlayerPricePoint?
    let reverseHolofoil: TCGPlayerPricePoint?

    enum CodingKeys: String, CodingKey {
        case normal
        case holo
        case holofoil
        case reverse
        case reverseHolofoil = "reverse-holofoil"
    }
}

struct TCGPlayerPricePoint: Decodable {
    let marketPrice: Double?
}
