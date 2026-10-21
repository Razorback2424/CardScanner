import CryptoKit
import Foundation

struct YuGiOhBrowseAdapter: GameBrowseAdapter {
    let catalog: YuGiOhCatalog
    var game: CardGame { .yuGiOh }
    var generation: String { catalog.generation }
    private let setsByID: [CatalogSetID: CatalogSet]
    private let cardsBySetID: [CatalogSetID: [CatalogCardSummary]]
    private let searchTextByID: [String: String]
    private let pageSize = 60

    init(catalog: YuGiOhCatalog) {
        self.catalog = catalog
        let adapter = YuGiOhCatalogAdapter(catalog: catalog)
        var grouped: [CatalogSetID: [(YuGiOhCatalog.Printing, ResolvedCatalogCard)]] = [:]
        for p in catalog.printingByID.values {
            guard let card = try? adapter.resolution(forPrintingID: p.id).card else { continue }
            grouped[CatalogSetID(game: .yuGiOh, providerID: "tcgplayer-group:\(p.set.groupID)"), default: []].append((p, card))
        }
        var sets: [CatalogSetID: CatalogSet] = [:], cards: [CatalogSetID: [CatalogCardSummary]] = [:], texts: [String: String] = [:]
        for (id, members) in grouped {
            let ordered = members.sorted {
                if $0.0.code != $1.0.code { return $0.0.code < $1.0.code }
                if $0.0.rarity != $1.0.rarity { return $0.0.rarity < $1.0.rarity }
                return $0.0.idString < $1.0.idString
            }
            let setInfo = ordered[0].0.set
            var set = CatalogSet(catalogID: id, name: setInfo.name, code: setInfo.abbreviation,
                logoURL: nil, symbolURL: nil, cardCount: ordered.count, releaseDate: setInfo.releaseDate, sortRank: 0,
                physicalPrintingIDs: Set(ordered.map { $0.0.idString }))
            let summaries = ordered.map { p, card in
                let summary = CatalogCardSummary(game: .yuGiOh, providerID: p.idString, setID: id,
                    setName: p.set.name, setCode: p.set.abbreviation, name: card.name, collectorNumber: p.code,
                    thumbnailURL: p.thumbnailURL, imageURL: p.imageURL, catalogGeneration: catalog.generation)
                texts[summary.id] = CardNameSearch.normalize([card.name, p.code, p.rarity, p.artLabel ?? "", p.set.name].joined(separator: " "))
                return summary
            }
            var seen: Set<URL> = []
            set.artworkFallbackURLs = Array(summaries.compactMap(\.thumbnailURL).filter { seen.insert($0).inserted }.prefix(3))
            sets[id] = set; cards[id] = summaries
        }
        setsByID = sets; cardsBySetID = cards; searchTextByID = texts
    }
    func sets() async throws -> [CatalogSet] {
        setsByID.values.sorted { left, right in
            if left.releaseDate != right.releaseDate { return (left.releaseDate ?? .distantPast) > (right.releaseDate ?? .distantPast) }
            return left.id < right.id
        }
    }
    func cards(in set: CatalogSet, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        guard set.game == game, setsByID[set.catalogID] == set else { throw CatalogLookupError.staleCatalog }
        return try page(cardsBySetID[set.catalogID] ?? [], cursor: cursor, scope: "set:" + set.id)
    }
    func search(query: String, setIDs: Set<CatalogSetID>, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        guard setIDs.allSatisfy({ $0.game == game && setsByID[$0] != nil }) else { throw CatalogLookupError.staleCatalog }
        let normalized = CardNameSearch.normalize(query)
        guard normalized.count >= 2 else {
            guard cursor == nil else { throw CatalogLookupError.staleCatalog }
            return .init(items: [], nextCursor: nil)
        }
        let scope = ([normalized] + setIDs.map(\.id).sorted()).map { "\($0.utf8.count):\($0)" }.joined()
        let rows = cardsBySetID.filter { setIDs.isEmpty || setIDs.contains($0.key) }.values.flatMap { $0 }
            .filter { searchTextByID[$0.id]?.contains(normalized) == true }.sorted { $0.id < $1.id }
        return try page(rows, cursor: cursor, scope: "search:" + scope)
    }
    func details(for summary: CatalogCardSummary) async throws -> CatalogCardDetails {
        guard summary.game == game, summary.catalogGeneration == generation,
              cardsBySetID[summary.setID]?.contains(summary) == true, let set = setsByID[summary.setID],
              let id = UUID(uuidString: summary.providerID) else { throw CatalogLookupError.staleCatalog }
        let resolved = try YuGiOhCatalogAdapter(catalog: catalog).resolution(forPrintingID: id)
        return .init(card: resolved.card, set: set, retrievedAt: resolved.retrievedAt)
    }
    private struct Cursor: Codable { let generation: String; let scope: String; let offset: Int }
    private func page(_ rows: [CatalogCardSummary], cursor: String?, scope: String) throws -> CatalogPage<CatalogCardSummary> {
        let fingerprint = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        var offset = 0
        if let cursor {
            guard cursor.utf8.count <= 512, let bytes = Data(base64Encoded: cursor), bytes.base64EncodedString() == cursor,
                  let decoded = try? JSONDecoder().decode(Cursor.self, from: bytes), decoded.generation == generation,
                  decoded.scope == fingerprint, decoded.offset > 0, decoded.offset < rows.count,
                  decoded.offset % pageSize == 0 else { throw CatalogLookupError.staleCatalog }
            offset = decoded.offset
        }
        let end = min(offset + pageSize, rows.count)
        let next: String?
        if end < rows.count {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            next = try encoder.encode(Cursor(generation: generation, scope: fingerprint, offset: end)).base64EncodedString()
        } else { next = nil }
        return .init(items: Array(rows[offset..<end]), nextCursor: next)
    }
}
