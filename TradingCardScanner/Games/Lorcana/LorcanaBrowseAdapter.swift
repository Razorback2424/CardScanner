import CryptoKit
import Foundation

/// A bounded local view of currently acquirable, distinguishable physical UUIDs.
/// The set rail explicitly describes reviewed printings, not whole-set coverage.
struct LorcanaBrowseAdapter: GameBrowseAdapter {
    let registry: LorcanaCatalogRegistry
    var game: CardGame { .lorcana }
    var generation: String { registry.generation }
    private let setsByID: [CatalogSetID: CatalogSet]
    private let cardsBySetID: [CatalogSetID: [CatalogCardSummary]]
    private let searchTextByID: [String: String]
    private let pageSize = 60

    init(registry: LorcanaCatalogRegistry) {
        self.registry = registry
        let catalog = LorcanaCatalogAdapter(registry: registry)
        var grouped: [CatalogSetID: [(LorcanaPhysicalPrinting, ResolvedCatalogCard)]] = [:]
        for footer in registry.familiesByFooter.keys {
            for (printing, resolution) in catalog.resolutions(forFooter: footer) {
                let id = CatalogSetID(game: .lorcana, providerID: footer.setScopeID)
                grouped[id, default: []].append((printing, resolution.card))
            }
        }
        var sets: [CatalogSetID: CatalogSet] = [:], cards: [CatalogSetID: [CatalogCardSummary]] = [:]
        var texts: [String: String] = [:]
        for (id, members) in grouped {
            let ordered = members.sorted {
                let result = CollectorNumber.compare($0.1.cardNumber, $1.1.cardNumber)
                return result == .orderedSame ? $0.1.physicalPrintingID < $1.1.physicalPrintingID : result == .orderedAscending
            }
            let footer = ordered[0].0.identity.footer
            let names = Set(ordered.map { $0.0.setName }), codes = Set(ordered.map { $0.0.providerSetCode })
            let baseName = names.count == 1 ? names.first! : "Printed set \(footer.printedSetMarker)/\(footer.denominator)"
            let label = baseName + " · " + footer.language.uppercased() + " (reviewed printings)"
            var set = CatalogSet(catalogID: id, name: label, code: codes.count == 1 ? codes.first! : footer.printedSetMarker,
                logoURL: nil, symbolURL: nil, cardCount: ordered.count, releaseDate: nil, sortRank: 0,
                physicalPrintingIDs: Set(ordered.map { $0.1.physicalPrintingID }))
            let summaries = ordered.map { printing, card in
                let summary = CatalogCardSummary(game: .lorcana, providerID: card.physicalPrintingID, setID: id,
                    setName: label, setCode: card.setCode, name: card.name, collectorNumber: card.cardNumber,
                    thumbnailURL: card.thumbnailImageURL, imageURL: card.displayImageURL, catalogGeneration: registry.generation)
                texts[summary.id] = CardNameSearch.normalize([summary.name, printing.identity.footer.displayIdentifier,
                    label, card.setCode].joined(separator: " "))
                return summary
            }
            var seen: Set<URL> = []
            set.artworkFallbackURLs = Array(summaries.compactMap(\.thumbnailURL).filter { seen.insert($0).inserted }.prefix(3))
            sets[id] = set; cards[id] = summaries
        }
        setsByID = sets; cardsBySetID = cards; searchTextByID = texts
    }

    func sets() async throws -> [CatalogSet] { setsByID.values.sorted { $0.id < $1.id } }

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
              cardsBySetID[summary.setID]?.contains(summary) == true,
              let set = setsByID[summary.setID], let id = UUID(uuidString: summary.providerID) else {
            throw CatalogLookupError.staleCatalog
        }
        let resolved = try LorcanaCatalogAdapter(registry: registry).resolution(forPrintingID: id)
        return .init(card: resolved.card, set: set, retrievedAt: resolved.retrievedAt)
    }

    private struct Cursor: Codable { let generation: String; let scope: String; let offset: Int }
    private func page(_ rows: [CatalogCardSummary], cursor: String?, scope: String) throws -> CatalogPage<CatalogCardSummary> {
        let fingerprint = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        var offset = 0
        if let cursor {
            guard cursor.utf8.count <= 512, let bytes = Data(base64Encoded: cursor),
                  bytes.base64EncodedString() == cursor, let decoded = try? JSONDecoder().decode(Cursor.self, from: bytes),
                  decoded.generation == generation, decoded.scope == fingerprint, decoded.offset > 0,
                  decoded.offset < rows.count, decoded.offset % pageSize == 0 else { throw CatalogLookupError.staleCatalog }
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
