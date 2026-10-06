import CryptoKit
import Foundation
import OnePieceCatalogCore

/// Immutable local projection of verified English physical printings.
/// Product appearances do not allocate another physical ownership identity.
struct OnePieceBrowseAdapter: GameBrowseAdapter {
    let registry: OnePieceCatalogRegistry
    var game: CardGame { .onePiece }
    var generation: String { registry.generation }
    private let setsByID: [CatalogSetID: CatalogSet]
    private let cardsBySetID: [CatalogSetID: [CatalogCardSummary]]
    private let pageSize = 60

    init(registry: OnePieceCatalogRegistry) {
        self.registry = registry
        let release = registry.verifiedRelease.release.registry
        var unassignedID = "one-piece:unassigned"
        while registry.productsByID[unassignedID] != nil { unassignedID += ":" }
        var memberships: [UUID: Set<String>] = [:]
        for appearance in release.appearances {
            memberships[appearance.printingID, default: []].insert(appearance.productID)
        }
        var grouped: [String: [OnePiecePhysicalPrinting]] = [:]
        for printing in release.printings where printing.status == .verified && printing.language == "en" {
            var products = memberships[printing.id] ?? []
            if let primary = printing.releaseID { products.insert(primary) }
            if products.isEmpty { products.insert(unassignedID) }
            for product in products { grouped[product, default: []].append(printing) }
        }
        var sets: [CatalogSetID: CatalogSet] = [:]
        var cards: [CatalogSetID: [CatalogCardSummary]] = [:]
        for (productID, printings) in grouped {
            let product = registry.productsByID[productID]
            let setID = CatalogSetID(game: .onePiece, providerID: productID)
            let set = CatalogSet(catalogID: setID, name: product?.label ?? "Other releases",
                code: product?.label ?? "Other releases", logoURL: nil, symbolURL: nil, cardCount: printings.count,
                releaseDate: product?.releaseDate.flatMap(OnePieceTextNormalization.releaseDate), sortRank: 0,
                physicalPrintingIDs: Set(printings.map { $0.id.uuidString.lowercased() }))
            sets[setID] = set
            cards[setID] = printings.compactMap { printing in
                guard let canonical = registry.canonicalByID[printing.canonicalCardID] else { return nil }
                let image = registry.artworkByID[printing.artworkID]?.referenceImageURL
                let qualifiers = [printing.treatment, printing.distributionLabel, printing.stamp]
                    .compactMap { $0 }.filter { !$0.isEmpty }
                return CatalogCardSummary(game: .onePiece, providerID: printing.id.uuidString.lowercased(),
                    setID: setID, setName: set.name,
                    setCode: OnePieceTextNormalization.prefix(of: canonical.printedNumber) ?? "",
                    name: qualifiers.isEmpty ? canonical.name : canonical.name + " · " + qualifiers.joined(separator: " · "),
                    collectorNumber: canonical.printedNumber, thumbnailURL: image, imageURL: image,
                    catalogGeneration: registry.generation)
            }.sorted {
                $0.collectorNumber == $1.collectorNumber ? $0.providerID < $1.providerID
                    : $0.collectorNumber < $1.collectorNumber
            }
        }
        setsByID = sets
        cardsBySetID = cards
    }

    func sets() async throws -> [CatalogSet] {
        setsByID.values.sorted {
            if $0.releaseOrder != $1.releaseOrder { return $0.releaseOrder > $1.releaseOrder }
            return $0.id < $1.id
        }
    }

    func cards(in set: CatalogSet, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        guard let current = setsByID[set.catalogID], current == set else { throw CatalogLookupError.staleCatalog }
        return try page(cardsBySetID[set.catalogID] ?? [], cursor: cursor, scope: "set:" + set.id)
    }

    func search(query: String, setIDs: Set<CatalogSetID>, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        let query = CardNameSearch.normalize(query)
        guard query.count >= 2 else { return .init(items: [], nextCursor: nil) }
        let selected = setIDs.filter { $0.game == game }
        let scope = ([query] + selected.map(\.id).sorted()).map { "\($0.utf8.count):\($0)" }.joined()
        let rows = cardsBySetID.filter { selected.isEmpty || selected.contains($0.key) }.values.flatMap { $0 }
        var seen: Set<String> = []
        let matches = rows.sorted { $0.id < $1.id }.filter {
            CardNameSearch.normalize($0.name + " " + $0.collectorNumber + " " + $0.setName).contains(query)
                && seen.insert($0.providerID).inserted
        }
        return try page(matches, cursor: cursor, scope: "search:" + scope)
    }

    func details(for summary: CatalogCardSummary) async throws -> CatalogCardDetails {
        guard summary.game == game, summary.catalogGeneration == generation,
              cardsBySetID[summary.setID]?.contains(summary) == true,
              let set = setsByID[summary.setID], let id = UUID(uuidString: summary.providerID) else {
            throw CatalogLookupError.staleCatalog
        }
        let resolution = try OnePieceCatalogAdapter(registry: registry).resolution(forPrintingID: id)
        return .init(card: resolution.card, set: set, retrievedAt: resolution.retrievedAt)
    }

    private func page(_ rows: [CatalogCardSummary], cursor: String?, scope: String) throws -> CatalogPage<CatalogCardSummary> {
        let fingerprint = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        var offset = 0
        if let cursor {
            let fields = cursor.split(separator: ":")
            guard fields.count == 3, fields[0] == generation, fields[1] == fingerprint,
                  let value = Int(fields[2]), value > 0, value < rows.count, value % pageSize == 0 else {
                throw CatalogLookupError.staleCatalog
            }
            offset = value
        }
        let end = min(offset + pageSize, rows.count)
        return .init(items: Array(rows[offset..<end]),
                     nextCursor: end < rows.count ? "\(generation):\(fingerprint):\(end)" : nil)
    }

}
