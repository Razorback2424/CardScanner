import CryptoKit
import Foundation

struct YuGiOhBrowseAdapter: GameBrowseAdapter {
    let catalog: YuGiOhCatalog
    var game: CardGame { .yuGiOh }
    var generation: String { catalog.generation }
    private let pageSize = 60
    /// Grouping and search text cover every printing, so they are built on
    /// first browse rather than when Yu-Gi-Oh is registered at launch.
    private let index: LoadOnce<Index>

    private struct SearchRow: Sendable {
        let setID: CatalogSetID
        let cardOffset: Int
        let text: String
    }

    private struct Index: Sendable {
        let setsByID: [CatalogSetID: CatalogSet]
        let cardsBySetID: [CatalogSetID: [CatalogCardSummary]]
        let searchRows: [SearchRow]

        init(catalog: YuGiOhCatalog) {
            var grouped: [CatalogSetID: [YuGiOhCatalog.Printing]] = [:]
            for p in catalog.printingByID.values {
                grouped[CatalogSetID(game: .yuGiOh, providerID: p.set.providerID), default: []].append(p)
            }
            var sets: [CatalogSetID: CatalogSet] = [:], cards: [CatalogSetID: [CatalogCardSummary]] = [:]
            var search: [(id: String, row: SearchRow)] = []
            search.reserveCapacity(catalog.printingByID.count)
            let generation = catalog.generation
            for (id, members) in grouped {
                let ordered = members.sorted {
                    if $0.code != $1.code { return $0.code < $1.code }
                    if $0.displayRarity != $1.displayRarity { return $0.displayRarity < $1.displayRarity }
                    return $0.idString < $1.idString
                }
                let setInfo = ordered[0].set
                var set = CatalogSet(catalogID: id, name: setInfo.name, code: setInfo.abbreviation,
                    logoURL: nil, symbolURL: nil, cardCount: ordered.count, releaseDate: setInfo.releaseDate, sortRank: 0,
                    physicalPrintingIDs: Set(ordered.map { $0.idString }))
                let summaries = ordered.enumerated().map { offset, p in
                    let summary = CatalogCardSummary(game: .yuGiOh, providerID: p.idString, setID: id,
                        setName: p.set.name, setCode: p.set.abbreviation, name: p.browseName, collectorNumber: p.code,
                        thumbnailURL: p.thumbnailURL, imageURL: p.imageURL, catalogGeneration: generation)
                    let text = CardNameSearch.normalize([p.cardName, p.productName, p.code, p.displayRarity,
                        p.displayArtLabel ?? "", p.set.name].joined(separator: " "))
                    search.append((summary.id, SearchRow(setID: id, cardOffset: offset, text: text)))
                    return summary
                }
                var seen: Set<URL> = []
                set.artworkFallbackURLs = Array(summaries.compactMap(\.thumbnailURL).filter { seen.insert($0).inserted }.prefix(3))
                sets[id] = set; cards[id] = summaries
            }
            setsByID = sets
            cardsBySetID = cards
            searchRows = search.sorted { $0.id < $1.id }.map(\.row)
        }
    }

    init(catalog: YuGiOhCatalog) {
        self.catalog = catalog
        index = LoadOnce { Index(catalog: catalog) }
    }
    func sets() async throws -> [CatalogSet] {
        try Task.checkCancellation()
        return index.get().setsByID.values.sorted { left, right in
            if left.releaseDate != right.releaseDate { return (left.releaseDate ?? .distantPast) > (right.releaseDate ?? .distantPast) }
            return left.id < right.id
        }
    }
    func cards(in set: CatalogSet, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        try Task.checkCancellation()
        let index = index.get()
        guard set.game == game, index.setsByID[set.catalogID] == set else { throw CatalogLookupError.staleCatalog }
        let rows = index.cardsBySetID[set.catalogID] ?? []
        let fingerprint = fingerprint("set:" + set.id)
        let start = try offset(for: cursor, fingerprint: fingerprint, count: rows.count)
        guard start.isMultiple(of: pageSize) else { throw CatalogLookupError.staleCatalog }
        let end = min(start + pageSize, rows.count)
        let next = end < rows.count ? try nextCursor(at: end, fingerprint: fingerprint) : nil
        return .init(items: Array(rows[start..<end]), nextCursor: next)
    }
    func search(query: String, setIDs: Set<CatalogSetID>, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        try Task.checkCancellation()
        let normalized = CardNameSearch.normalize(query)
        let index = index.get()
        try Task.checkCancellation()
        guard setIDs.allSatisfy({ $0.game == game && index.setsByID[$0] != nil }) else { throw CatalogLookupError.staleCatalog }
        guard normalized.count >= 2 else {
            guard cursor == nil else { throw CatalogLookupError.staleCatalog }
            return .init(items: [], nextCursor: nil)
        }
        let scope = ([normalized] + setIDs.map(\.id).sorted()).map { "\($0.utf8.count):\($0)" }.joined()
        let fingerprint = fingerprint("search-index:" + scope)
        let start = try offset(for: cursor, fingerprint: fingerprint, count: index.searchRows.count)
        var matches: [CatalogCardSummary] = []
        matches.reserveCapacity(pageSize)
        for position in start..<index.searchRows.count {
            if position.isMultiple(of: 256) { try Task.checkCancellation() }
            let row = index.searchRows[position]
            guard setIDs.isEmpty || setIDs.contains(row.setID),
                  row.text.contains(normalized), let cards = index.cardsBySetID[row.setID] else { continue }
            if matches.count == pageSize {
                return .init(items: matches, nextCursor: try nextCursor(at: position, fingerprint: fingerprint))
            }
            matches.append(cards[row.cardOffset])
        }
        try Task.checkCancellation()
        return .init(items: matches, nextCursor: nil)
    }
    func details(for summary: CatalogCardSummary) async throws -> CatalogCardDetails {
        let index = index.get()
        guard summary.game == game, summary.catalogGeneration == generation,
              index.cardsBySetID[summary.setID]?.contains(summary) == true, let set = index.setsByID[summary.setID],
              let id = UUID(uuidString: summary.providerID), let p = catalog.printingByID[id] else { throw CatalogLookupError.staleCatalog }
        let resolved = try YuGiOhCatalogAdapter(catalog: catalog).discoveryResolution(id)
        let referenceNotice = p.code.isEmpty ? "Reference display card without a printed set code." : nil
        let reason = referenceNotice ?? p.identityReason.map { "This printing needs identity review (\($0))." }
            ?? (p.editions.isEmpty ? "No supported edition is recorded for this product." : nil)
            ?? ((try? YuGiOhCatalogAdapter(catalog: catalog).resolution(forPrintingID: id)) == nil
                ? "The available labels do not distinguish this printing." : nil)
        let printingNotice = p.productID == nil
            ? "Confirm the release, rarity and edition on your copy. This printing has no linked marketplace product. "
            : "Confirm the release, rarity, artwork and edition on your copy. Images are representative marketplace images. "
        return .init(card: resolved.card, set: set, retrievedAt: resolved.retrievedAt,
            collectionWriteUnavailableReason: reason,
            catalogNotice: (p.canonicalLinkStatus == "unresolved" ? "Canonical card linkage is unresolved. " : "")
                + printingNotice + "Other editions may exist. " + catalog.currentPricingNotice)
    }
    private struct Cursor: Codable { let generation: String; let scope: String; let offset: Int }
    private func fingerprint(_ scope: String) -> String {
        SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func offset(for cursor: String?, fingerprint: String, count: Int) throws -> Int {
        guard let cursor else { return 0 }
        guard cursor.utf8.count <= 512, let bytes = Data(base64Encoded: cursor), bytes.base64EncodedString() == cursor,
              let decoded = try? JSONDecoder().decode(Cursor.self, from: bytes), decoded.generation == generation,
              decoded.scope == fingerprint, decoded.offset > 0, decoded.offset < count else {
            throw CatalogLookupError.staleCatalog
        }
        return decoded.offset
    }

    private func nextCursor(at offset: Int, fingerprint: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Cursor(generation: generation, scope: fingerprint, offset: offset)).base64EncodedString()
    }
}
