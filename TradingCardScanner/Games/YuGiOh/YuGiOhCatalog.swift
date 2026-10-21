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
        struct Membership: Hashable, Decodable, Sendable {
            let e: YuGiOhEdition; let t: String; let q: Double?; let h: String?; let s: String?; let st: String?
        }
        let id: UUID; let code: String; let set: SetInfo; let card: Card
        let rarity: String; let artLabel: String?
        let productID: Int; let productName: String
        let editions: [YuGiOhEdition]; let coverageVerified: Bool; let editionEvidence: String?
        let pricedEditions: [YuGiOhEdition]
        let membership: [Membership]
        let identityReason: String?
        let canonicalLinkStatus: String?
        var explicitSelectionSupported: Bool {
            identityReason == nil && !editions.isEmpty && (coverageVerified || !membership.isEmpty)
        }
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
    var historicalPricingNotice: String {
        "Yu-Gi-Oh! uses a bundled snapshot captured \(capturedAt.formatted(date: .abbreviated, time: .omitted)). Prices keep their source dates. Live refresh is unavailable."
    }
    static var bundledPricingNotice: String {
        (try? bundled.get().historicalPricingNotice) ?? "Yu-Gi-Oh! live pricing is unavailable."
    }
    static let marketHistoryUnavailableNotice = "Market price history is unavailable for Yu-Gi-Oh! Bundled quotes are dated snapshots."
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
        let m: [Printing.Membership]?; let ir: String?
        let canonicalLink: String?
    }
    init(data: Data) throws {
        let seed = try JSONDecoder().decode(Seed.self, from: data)
        let iso = ISO8601DateFormatter()
        let plainISO = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: seed.capturedAt) ?? plainISO.date(from: seed.capturedAt)
        let sourceDates = Set(seed.printings.flatMap { ($0.m ?? []).compactMap(\.s) })
        let validSourceDates = Set(sourceDates.filter { plainISO.date(from: $0) != nil || iso.date(from: $0) != nil })
        guard seed.schemaVersion == 1, seed.generation.hasPrefix("yugioh-en-"), seed.generation.count > 10,
              let date, Set(seed.incompleteCodes).isDisjoint(with: seed.autoEligibleCodes) else { throw LoadError.invalidSchema }
        var sets: [Int: SetInfo] = [:]
        for row in seed.sets {
            guard sets[row.g] == nil else { throw LoadError.invalidRow("duplicate group") }
            sets[row.g] = .init(groupID: row.g, name: row.n, abbreviation: row.a,
                releaseDate: plainISO.date(from: row.d + "T00:00:00Z"))
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
                  (Self.validCode(row.c) || (row.ir == "unsupportedCode" && !row.c.isEmpty && row.e.isEmpty)), !row.r.isEmpty, !row.pn.isEmpty,
                  Set(row.e).count == row.e.count, Set(row.pe).count == row.pe.count,
                  Set((row.m ?? []).map(\.e)).count == (row.m ?? []).count,
                  row.ec || row.m == nil || Set(row.e) == Set((row.m ?? []).map(\.e)),
                  (row.m ?? []).allSatisfy({ m in
                      row.e.contains(m.e) && ["providerMarket", "providerListing", "independentlyReviewed"].contains(m.t)
                      && m.h.map({ $0.utf8.count == 64 && $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }) == true
                      && validSourceDates.contains(m.s ?? "")
                      && (m.q.map { $0.isFinite && $0 >= 0 } ?? true)
                      && (m.t != "providerListing" || m.q == nil || m.q == 0)
                  }),
                  !row.ec || (!row.e.isEmpty && row.ee?.isEmpty == false) else {
                throw LoadError.invalidRow(row.id)
            }
            let printing = Printing(id: id, code: row.c, set: set, card: cards[row.k], rarity: row.r, artLabel: row.art,
                productID: row.p, productName: row.pn, editions: row.e.sorted { $0.variant.choicePriority < $1.variant.choicePriority },
                coverageVerified: row.ec, editionEvidence: row.ee, pricedEditions: row.pe,
                membership: row.m ?? [], identityReason: row.ir, canonicalLinkStatus: row.canonicalLink,
                thumbnailURL: row.img.flatMap(URL.init(string:)),
                imageURL: row.img.flatMap { URL(string: $0.replacingOccurrences(of: "_200w", with: "_in_1000x1000")) })
            byID[id] = printing; byCode[row.c, default: []].append(printing)
        }
        for code in seed.autoEligibleCodes {
            guard let family = byCode[code], family.count == 1, family[0].coverageVerified, family[0].explicitSelectionSupported,
                  family[0].artLabel == nil else { throw LoadError.invalidRow("automatic eligibility") }
        }
        generation = seed.generation; capturedAt = date; setsByGroupID = sets
        printingByID = byID; printingsByCode = byCode
        incompleteCodes = Set(seed.incompleteCodes); autoEligibleCodes = Set(seed.autoEligibleCodes)
    }
    static func validCode(_ code: String) -> Bool {
        if ["IOC-SE1", "IOC-SE2", "IOC-SE3", "IOC-SE4"].contains(code) { return true }
        return code.range(of: "^[A-Z0-9]{2,4}-(?:(?:EN|E)[A-Z0-9]{3}|[0-9]{3})$", options: .regularExpression) != nil
    }
    static let bundled: Result<Self, Error> = Result {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "YuGiOhCatalogSeed") else { throw LoadError.missingResource }
        return try Self(data: Data(contentsOf: url, options: .mappedIfSafe))
    }
    var runtime: CardGameRuntime { YuGiOhGameRuntime(catalog: self).runtime }
}
