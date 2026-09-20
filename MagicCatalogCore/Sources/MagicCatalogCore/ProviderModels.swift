import Foundation

/// The subset of Scryfall's `/sets` response that is allowed to influence the
/// Magic catalog. Card-level fields are intentionally absent: Scryfall stays a
/// live card-data provider after a set release is signed.
public struct MagicCatalogProviderSet: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let code: String
    public let name: String
    public let releasedAt: String?
    public let setType: String
    public let cardCount: Int?
    public let printedSize: Int?
    public let iconSVGURL: URL?
    public let parentSetCode: String?
    public let digital: Bool

    public init(
        id: String,
        code: String,
        name: String,
        releasedAt: String? = nil,
        setType: String,
        cardCount: Int? = nil,
        printedSize: Int? = nil,
        iconSVGURL: URL? = nil,
        parentSetCode: String? = nil,
        digital: Bool = false
    ) {
        self.id = id
        self.code = code
        self.name = name
        self.releasedAt = releasedAt
        self.setType = setType
        self.cardCount = cardCount
        self.printedSize = printedSize
        self.iconSVGURL = iconSVGURL
        self.parentSetCode = parentSetCode
        self.digital = digital
    }

    private enum CodingKeys: String, CodingKey {
        case id, code, name
        case releasedAt = "released_at"
        case setType = "set_type"
        case cardCount = "card_count"
        case printedSize = "printed_size"
        case iconSVGURL = "icon_svg_uri"
        case parentSetCode = "parent_set_code"
        case digital
    }
}

public struct MagicCatalogProviderFixture: Codable, Equatable, Sendable {
    public let sets: [MagicCatalogProviderSet]

    public init(sets: [MagicCatalogProviderSet]) {
        self.sets = sets
    }
}

public enum MagicCatalogProviderJSON {
    public static func decodeDirectory(from data: Data) throws -> [MagicCatalogProviderSet] {
        if let rows = try? JSONDecoder().decode([MagicCatalogProviderSet].self, from: data) {
            return rows
        }
        if let response = try? JSONDecoder().decode(DirectoryResponse.self, from: data) {
            return response.data
        }
        return try JSONDecoder().decode(MagicCatalogProviderFixture.self, from: data).sets
    }

    private struct DirectoryResponse: Decodable {
        let data: [MagicCatalogProviderSet]
    }
}
