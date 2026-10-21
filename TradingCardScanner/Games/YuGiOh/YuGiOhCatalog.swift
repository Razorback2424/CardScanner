import Foundation

enum YuGiOhEdition: String, CaseIterable, Codable, Sendable {
    case first = "yugioh1stEdition", unlimited = "yugiohUnlimited", limited = "yugiohLimited"
    var variant: PhysicalVariant {
        switch self { case .first: .yugiohFirstEdition; case .unlimited: .yugiohUnlimited; case .limited: .yugiohLimited }
    }
    var tcgplayerSubtype: String {
        switch self { case .first: "1st Edition"; case .unlimited: "Unlimited"; case .limited: "Limited" }
    }
}

struct YuGiOhCatalog: Sendable {
    struct SetInfo: Hashable, Sendable { let groupID: Int; let name: String; let abbreviation: String; let releaseDate: Date? }
    struct Card: Hashable, Sendable { let id: UUID; let name: String; let passcodes: Set<Int> }
    struct Printing: Hashable, Sendable {
        let id: UUID; let code: String; let set: SetInfo; let card: Card
        let rarity: String; let artLabel: String?
        let productID: Int; let productName: String
        let editions: [YuGiOhEdition]; let coverageVerified: Bool; let editionEvidence: String?
        let pricedEditions: [YuGiOhEdition]
        let thumbnailURL: URL?; let imageURL: URL?
        var idString: String { id.uuidString.lowercased() }
    }
    enum LoadError: Error { case missingResource, invalidSchema, invalidRow(String) }
    let generation: String
    let capturedAt: Date
    let printingsByCode: [String: [Printing]]
    let printingByID: [UUID: Printing]
    let incompleteCodes: Set<String>
    let autoEligibleCodes: Set<String>
    let setsByGroupID: [Int: SetInfo]
    private struct Seed: Decodable {
        let schemaVersion: Int; let generation: String; let capturedAt: String
        let sets: [SetRow]; let cards: [CardRow]; let printings: [PrintingRow]
        let incompleteCodes: [String]; let autoEligibleCodes: [String]
    }
    private struct SetRow: Decodable { let g: Int; let n: String; let a: String; let d: String }
    private struct CardRow: Decodable { let id: String; let n: String; let pc: [Int] }
    private struct PrintingRow: Decodable {
        let id: String; let c: String; let g: Int; let k: Int; let r: String; let art: String?
        let p: Int; let pn: String; let e: [YuGiOhEdition]; let ec: Bool; let ee: String?
        let pe: [YuGiOhEdition]; let img: String?
    }
    init(data: Data) throws {
        let seed = try JSONDecoder().decode(Seed.self, from: data)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: seed.capturedAt) ?? ISO8601DateFormatter().date(from: seed.capturedAt)
        guard seed.schemaVersion == 1, seed.generation.hasPrefix("yugioh-en-"), seed.generation.count > 10,
              let date, Set(seed.incompleteCodes).isDisjoint(with: seed.autoEligibleCodes) else { throw LoadError.invalidSchema }
        var sets: [Int: SetInfo] = [:]
        for row in seed.sets {
            guard sets[row.g] == nil else { throw LoadError.invalidRow("duplicate group") }
            sets[row.g] = .init(groupID: row.g, name: row.n, abbreviation: row.a,
                releaseDate: ISO8601DateFormatter().date(from: row.d + "T00:00:00Z"))
        }
        var cards: [Card] = [], cardIDs: Set<UUID> = []
        for row in seed.cards {
            guard let id = UUID(uuidString: row.id), id.uuidString.lowercased() == row.id,
                  cardIDs.insert(id).inserted else { throw LoadError.invalidRow("card") }
            cards.append(.init(id: id, name: row.n, passcodes: Set(row.pc)))
        }
        var byID: [UUID: Printing] = [:], byCode: [String: [Printing]] = [:], products: Set<Int> = []
        for row in seed.printings {
            guard let id = UUID(uuidString: row.id), id.uuidString.lowercased() == row.id, byID[id] == nil,
                  products.insert(row.p).inserted, row.p > 0, cards.indices.contains(row.k), let set = sets[row.g],
                  Self.validCode(row.c), !row.r.isEmpty, !row.pn.isEmpty,
                  Set(row.e).count == row.e.count, Set(row.pe).count == row.pe.count,
                  !row.ec || (!row.e.isEmpty && row.ee?.isEmpty == false && Set(row.pe).isSubset(of: Set(row.e))) else {
                throw LoadError.invalidRow(row.id)
            }
            let printing = Printing(id: id, code: row.c, set: set, card: cards[row.k], rarity: row.r, artLabel: row.art,
                productID: row.p, productName: row.pn, editions: row.e.sorted { $0.variant.choicePriority < $1.variant.choicePriority },
                coverageVerified: row.ec, editionEvidence: row.ee, pricedEditions: row.pe,
                thumbnailURL: row.img.flatMap(URL.init(string:)),
                imageURL: row.img.flatMap { URL(string: $0.replacingOccurrences(of: "_200w", with: "_in_1000x1000")) })
            byID[id] = printing; byCode[row.c, default: []].append(printing)
        }
        for code in seed.autoEligibleCodes {
            guard let family = byCode[code], family.count == 1, family[0].coverageVerified,
                  family[0].artLabel == nil else { throw LoadError.invalidRow("automatic eligibility") }
        }
        generation = seed.generation; capturedAt = date; setsByGroupID = sets
        printingByID = byID; printingsByCode = byCode
        incompleteCodes = Set(seed.incompleteCodes); autoEligibleCodes = Set(seed.autoEligibleCodes)
    }
    static func validCode(_ code: String) -> Bool {
        code.range(of: "^[A-Z0-9]{2,4}-(?:(?:EN|E)[A-Z0-9]{3}|[0-9]{3})$", options: .regularExpression) != nil
    }
    static let bundled: Result<Self, Error> = Result {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "YuGiOhCatalogSeed") else { throw LoadError.missingResource }
        return try Self(data: Data(contentsOf: url, options: .mappedIfSafe))
    }
    var runtime: CardGameRuntime { YuGiOhGameRuntime(catalog: self).runtime }
}
