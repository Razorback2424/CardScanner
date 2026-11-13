import CryptoKit
import Foundation
import OnePieceCatalogCore

extension OnePiecePhysicalPrinting {
    var isBrowsableInEnglish: Bool {
        language == "en" && [.verified, .provisional, .conflicted].contains(status)
    }
}

/// Immutable local projection of verified and held English physical printings.
/// Product appearances do not allocate another physical ownership identity.
struct OnePieceBrowseAdapter: GameBrowseAdapter {
    let registry: OnePieceCatalogRegistry
    var game: CardGame { .onePiece }
    var generation: String { registry.generation }
    private let setsByID: [CatalogSetID: CatalogSet]
    private let cardsBySetID: [CatalogSetID: [CatalogCardSummary]]
    private let searchRows: [SearchRow]
    private let pageSize = 60
    private struct SearchRow: Sendable {
        let summary: CatalogCardSummary
        let searchableText: String
    }
    private static let collectorNumber = try! NSRegularExpression(
        pattern: #"(?<!\S)([a-z]{1,8}) ?([0-9]{0,3}) ?([0-9]{3})(?!\S)"#)

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
        for printing in release.printings where printing.isBrowsableInEnglish {
            var products = memberships[printing.id] ?? []
            if let primary = printing.releaseID { products.insert(primary) }
            if products.isEmpty { products.insert(unassignedID) }
            for product in products { grouped[product, default: []].append(printing) }
        }
        var discoveries: [String: [String: Set<String>]] = [:]
        for observation in registry.verifiedRelease.release.observations where observation.isBrowseDiscovery {
            if let product = observation.productEvidence.first, let number = observation.printedEvidence["number"] {
                let labels = observation.printedEvidence["productLabel"].map { [$0] } ?? []
                discoveries[product, default: [:]][number, default: []].formUnion(labels)
            }
        }
        var sets: [CatalogSetID: CatalogSet] = [:]
        var cards: [CatalogSetID: [CatalogCardSummary]] = [:]
        for productID in Set(grouped.keys).union(discoveries.keys) {
            let printings = grouped[productID] ?? []
            let unresolvedNumbers = discoveries[productID] ?? [:]
            let product = registry.productsByID[productID]
            let setID = CatalogSetID(game: .onePiece, providerID: productID)
            var set = CatalogSet(catalogID: setID, name: product?.label ?? "Other releases",
                code: product?.label ?? "Other releases", logoURL: nil, symbolURL: nil,
                cardCount: printings.count + unresolvedNumbers.count,
                releaseDate: product?.releaseDate.flatMap(OnePieceTextNormalization.releaseDate), sortRank: 0,
                physicalPrintingIDs: Set(printings.lazy.filter { $0.status == .verified }.map { $0.id.uuidString.lowercased() }))
            if !unresolvedNumbers.isEmpty || printings.contains(where: {
                $0.status != .verified || registry.canonicalByID[$0.canonicalCardID]?.printingCoverageComplete != true
            }) {
                set.collectionAvailabilityNotice = "Partial catalog"
            }
            let physicalRows = printings.compactMap { printing -> CatalogCardSummary? in
                guard let canonical = registry.canonicalByID[printing.canonicalCardID] else { return nil }
                let image = registry.artworkURLByID[printing.artworkID]
                let qualifiers = [printing.treatment, printing.distributionLabel, printing.stamp]
                    .compactMap { $0 }.filter { !$0.isEmpty }
                let name = qualifiers.isEmpty ? canonical.name : canonical.name + " · " + qualifiers.joined(separator: " · ")
                let finishSearchTerms = printing.status == .verified ? printing.supportedVariantIDs.compactMap { id in
                    registry.variantsByID[id].map { "\(canonical.name) \($0.label)" }
                } : []
                return CatalogCardSummary(game: .onePiece, providerID: printing.id.uuidString.lowercased(),
                    setID: setID, setName: set.name,
                    setCode: OnePieceTextNormalization.prefix(of: canonical.printedNumber) ?? "",
                    name: name,
                    collectorNumber: canonical.printedNumber, thumbnailURL: image, imageURL: image,
                    catalogGeneration: registry.generation,
                    collectionAvailabilityNotice: printing.status == .verified ? nil : "Browse only",
                    searchFields: Self.searchFields(name: name, number: canonical.printedNumber, additionalText: finishSearchTerms))
            }
            let discoveryRows = unresolvedNumbers.compactMap { number, labels -> CatalogCardSummary? in
                guard let card = registry.canonicalByPrintedNumber[number] else { return nil }
                return .init(game: .onePiece, providerID: Self.discoveryID(for: card), setID: setID,
                    setName: set.name, setCode: OnePieceTextNormalization.prefix(of: number) ?? "",
                    name: card.name, collectorNumber: number, thumbnailURL: nil, imageURL: nil,
                    catalogGeneration: registry.generation, collectionAvailabilityNotice: "Printing needs review",
                    searchFields: Self.searchFields(name: card.name, number: number, additionalText: labels.sorted()))
            }
            cards[setID] = (physicalRows + discoveryRows).sorted {
                $0.collectorNumber == $1.collectorNumber ? $0.providerID < $1.providerID
                    : $0.collectorNumber < $1.collectorNumber
            }
            // Reuse verified member artwork; product releases do not publish logos.
            // Sorting above makes the selection stable across registry rebuilds.
            var seenImages: Set<URL> = []
            set.artworkFallbackURLs = Array((cards[setID] ?? []).filter { $0.collectionAvailabilityNotice == nil }
                .compactMap(\.thumbnailURL)
                .filter { seenImages.insert($0).inserted }.prefix(3))
            sets[setID] = set
        }
        setsByID = sets
        cardsBySetID = cards
        searchRows = cards.values.flatMap { $0 }.sorted { $0.id < $1.id }.map {
            let cardText = $0.searchFields?.text ?? "\($0.name) \($0.collectorNumber)"
            return SearchRow(summary: $0, searchableText: CardNameSearch.normalize(cardText + " " + $0.setName))
        }
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

    func completeLocalCards(in set: CatalogSet) async throws -> [CatalogCardSummary]? {
        guard setsByID[set.catalogID] == set else { throw CatalogLookupError.staleCatalog }
        return cardsBySetID[set.catalogID] ?? []
    }

    private static func searchFields(name: String, number: String, additionalText: [String]) -> CatalogCardSearchFields {
        let text = ([name, number] + additionalText).joined(separator: " ")
        let parts = number.lowercased().split(separator: "-", maxSplits: 1)
        guard parts.count == 2 else { return .init(collectorNumber: number, denominator: nil, text: text) }
        let prefix = parts[0], digits = parts[1]
        let letters = prefix.prefix(while: \.isLetter)
        let splitPrefix = "\(letters) \(prefix.dropFirst(letters.count))"
        return .init(collectorNumber: number, denominator: nil,
            text: text,
            collectorNumberAliases: ["\(prefix) \(digits)", "\(prefix)\(digits)",
                                     "\(splitPrefix) \(digits)", "\(splitPrefix)\(digits)"].map(CardNameSearch.normalize))
    }

    func search(query: String, setIDs: Set<CatalogSetID>, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        let query = CardNameSearch.normalize(query)
        guard query.count >= 2 else { return .init(items: [], nextCursor: nil) }
        let selected = setIDs.filter { $0.game == game }
        let scope = ([query] + selected.map(\.id).sorted()).map { "\($0.utf8.count):\($0)" }.joined()
        let (number, text) = collectorNumber(in: query)
        var seen: Set<String> = []
        let matches = searchRows.compactMap { row -> CatalogCardSummary? in
            let card = row.summary
            guard selected.isEmpty || selected.contains(card.setID),
                  number == nil || card.collectorNumber == number,
                  text.isEmpty || row.searchableText.contains(text),
                  seen.insert(card.providerID).inserted else { return nil }
            return card
        }
        return try page(matches, cursor: cursor, scope: "search:" + scope)
    }

    private func collectorNumber(in query: String) -> (String?, String) {
        let input = query as NSString
        for match in Self.collectorNumber.matches(in: query, range: NSRange(location: 0, length: input.length)) {
            let prefix = (input.substring(with: match.range(at: 1)) + input.substring(with: match.range(at: 2))).uppercased()
            guard registry.recognitionPrefixes.contains(prefix) else { continue }
            let number = prefix + "-" + input.substring(with: match.range(at: 3))
            let remaining = input.replacingCharacters(in: match.range, with: " ")
            return (number, CardNameSearch.normalize(remaining))
        }
        return (nil, query)
    }

    func details(for summary: CatalogCardSummary) async throws -> CatalogCardDetails {
        guard summary.game == game, summary.catalogGeneration == generation,
              cardsBySetID[summary.setID]?.contains(summary) == true,
              let set = setsByID[summary.setID] else {
            throw CatalogLookupError.staleCatalog
        }
        if let id = UUID(uuidString: summary.providerID) {
            return try OnePieceCatalogAdapter(registry: registry).browseDetails(forPrintingID: id, set: set)
        }
        guard let canonical = registry.canonicalByPrintedNumber[summary.collectorNumber],
              summary.providerID == Self.discoveryID(for: canonical) else { throw CatalogLookupError.staleCatalog }
        let preview = try ResolvedCatalogCard(game: game, physicalPrintingID: summary.providerID,
            canonicalCardID: canonical.id, language: canonical.language, name: canonical.name,
            setName: set.name, setCode: summary.setCode, cardNumber: canonical.printedNumber,
            printedIdentifier: canonical.printedNumber, setReleaseOrder: set.releaseOrder,
            variantEvidence: .init(game: game, setID: set.providerID, cardNumber: canonical.printedNumber,
                                   catalogVariants: [], physicalCoverageVerified: false))
        return .init(card: preview, set: set, retrievedAt: registry.retrievedAt,
            collectionWriteUnavailableReason: "The card is listed by Bandai. Its printing and finish need review before it can be added.")
    }

    private static func discoveryID(for card: OnePieceCanonicalCard) -> String { "one-piece-discovery:" + card.id }

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
