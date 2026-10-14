import CryptoKit
import Foundation

/// Public source records for discovery. These are deliberately separate from
/// LorcanaPhysicalCatalog: a source observation cannot grant collection authority,
/// prove a complete size/stamp universe, or become a verified physical UUID.
struct LorcanaDiscoveryCatalog: GameCatalogAdapter, GameBrowseAdapter, SealedBrowseProviding {
    struct Card: Decodable, Sendable {
        let id, name, number, printedIdentifier, setCode, setName, rarity, layout: String
        let sourceSetCode: String
        let footer: LorcanaPrintedIdentity?
        let releaseDate: String?
        let imageURL, thumbnailURL: URL?
        let foilTypes: [String]
        let distribution: String?
        let unnumberedSetMarker: String?
        let recognitionTitles: [String]?

        var setID: CatalogSetID { .init(game: .lorcana, providerID: "lorcana-source:" + setCode) }
        var variants: [PhysicalVariant] {
            let foils = foilTypes.filter { $0 != "None" }
            return foilTypes.map { type in
                if type == "None" { return .normal }
                if foils.count == 1 { return .foil }
                return .init(id: "lorcanaFoil:" + type, label: type + " Foil")
            }
        }
    }
    struct Product: Decodable, Sendable {
        let id, name, setID, setName, tcgplayerProductID: String
        let releaseDate: String?
        let imageURL: URL?
        var summary: SealedProductSummary {
            .init(id: id, name: name, setName: setName, variantID: nil,
                  marketPriceUSD: nil, updatedAt: nil, imageURL: imageURL,
                  tcgplayerProductID: tcgplayerProductID)
        }
    }
    private struct Payload: Decodable {
        struct Coverage: Decodable {
            struct SourceSet: Decodable { let hasAllCards: Bool }
            struct Evidence: Decodable { let productID: Int; let reference: String }
            let sourceCardCount, supplementalCardCount, sealedCount: Int
            let sets: [String: SourceSet]
            let productEvidence: [Evidence]?
        }
        let schemaVersion: Int
        let generatedOn: String
        let cards: [Card]
        let sealed: [Product]
        let coverage: Coverage
    }

    static let descriptor = CardGameDescriptor(game: .lorcana, displayName: "Disney Lorcana", sortOrder: 3,
                                               capabilities: [.scan, .browse, .sealed])
    static let bundled: Result<Self, Error> = Result {
        guard let url = Bundle.main.url(forResource: "discovery", withExtension: "json", subdirectory: "LorcanaCatalogSeed")
        else { throw BrowseCatalogError.badResponse }
        return try Self(data: Data(contentsOf: url))
    }
    /// Normal app registration retains discovery/sealed coverage while exact
    /// reviewed UUIDs use the same physical ownership/pricing authority as review.
    static let bundledMarket: Result<Self, Error> = Result {
        guard let source = Bundle.main.url(forResource: "discovery", withExtension: "json", subdirectory: "LorcanaCatalogSeed"),
              let market = Bundle.main.url(forResource: "market", withExtension: "json", subdirectory: "LorcanaCatalogSeed")
        else { throw BrowseCatalogError.badResponse }
        let sourceBytes = try Data(contentsOf: source), marketBytes = try Data(contentsOf: market)
        struct SourceBinding: Decodable { let discoverySHA256: String }
        guard marketBytes.count <= 8 * 1_024 * 1_024,
              try JSONDecoder().decode(SourceBinding.self, from: marketBytes).discoverySHA256
                == SHA256.hash(data: sourceBytes).map({ String(format: "%02x", $0) }).joined()
        else { throw BrowseCatalogError.badResponse }
        return try Self(data: sourceBytes,
            reviewedManifest: JSONDecoder().decode(LorcanaPhysicalCatalogManifest.self, from: marketBytes))
    }

    let game = CardGame.lorcana
    let generation: String
    let registry: LorcanaCatalogRegistry
    let cardsByID: [String: Card]
    let cardsByFooter: [LorcanaPrintedIdentity: [Card]]
    let products: [Product]
    let unnumberedCards: [Card]
    private let setsByID: [CatalogSetID: CatalogSet]
    private let summariesBySetID: [CatalogSetID: [CatalogCardSummary]]
    private let searchTextByID: [String: String]
    private let capturedAt: Date
    private let physicalBySourceID: [String: UUID]
    private let sourceByPhysicalID: [String: Card]
    private var physical: LorcanaCatalogAdapter { .init(registry: registry) }

    init(data: Data, asOf: Date = .now, reviewedManifest: LorcanaPhysicalCatalogManifest? = nil) throws {
        guard data.count <= 8 * 1_024 * 1_024 else { throw BrowseCatalogError.badResponse }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.schemaVersion == 1, !payload.cards.isEmpty, payload.cards.count <= 20_000,
              payload.sealed.count <= 5_000,
              payload.coverage.sourceCardCount + payload.coverage.supplementalCardCount == payload.cards.count,
              payload.coverage.sealedCount == payload.sealed.count,
              Set(payload.cards.map(\.id)).count == payload.cards.count,
              Set(payload.sealed.map(\.id)).count == payload.sealed.count else { throw BrowseCatalogError.badResponse }
        let timestamp = ISO8601DateFormatter()
        guard let captured = timestamp.date(from: payload.generatedOn + "Z") else { throw BrowseCatalogError.badResponse }
        for card in payload.cards {
            guard (card.id.hasPrefix("lorcanajson:en:") || card.id.hasPrefix("tcgcsv:71:")), !card.name.isEmpty,
                  !card.number.isEmpty, !card.setCode.isEmpty, !card.setName.isEmpty,
                  (card.id.hasPrefix("tcgcsv:") || !card.foilTypes.isEmpty), Set(card.foilTypes).count == card.foilTypes.count,
                  [card.imageURL, card.thumbnailURL].compactMap({ $0 }).allSatisfy({ $0.scheme == "https" && $0.host != nil }),
                  card.footer == nil || card.footer?.language == "en" else { throw BrowseCatalogError.badResponse }
            if let marker = card.unnumberedSetMarker {
                guard card.footer == nil, LorcanaPrintedIdentity.matches(marker, "Q[0-9]{1,2}"),
                      card.printedIdentifier == "EN • " + marker,
                      let titles = card.recognitionTitles, !titles.isEmpty, titles.count <= 8,
                      Set(titles).count == titles.count,
                      titles.allSatisfy({ !$0.isEmpty && $0.count <= 256 }) else { throw BrowseCatalogError.badResponse }
            } else if !(card.recognitionTitles ?? []).isEmpty { throw BrowseCatalogError.badResponse }
        }
        for product in payload.sealed {
            guard product.id == "tcgcsv:71:" + product.tcgplayerProductID,
                  product.setID.hasPrefix("tcgcsv:71:"), !product.name.isEmpty, !product.setName.isEmpty,
                  product.imageURL == nil || product.imageURL?.scheme == "https" else { throw BrowseCatalogError.badResponse }
        }
        let upcomingScopes = Set(payload.cards.filter { (Self.date($0.releaseDate) ?? .distantPast) > asOf }
            .map(\.setCode)).sorted().joined(separator: ":")
        // Release labels advance on relaunch. Bind cursors/details to that
        // presentation phase so an old "Upcoming" page cannot survive it.
        let generationBytes = data + Data(upcomingScopes.utf8)
        var catalogGeneration = "lorcana:discovery:" + SHA256.hash(data: generationBytes).map { String(format: "%02x", $0) }.joined()
        capturedAt = captured
        cardsByID = Dictionary(uniqueKeysWithValues: payload.cards.map { ($0.id, $0) })
        cardsByFooter = Dictionary(grouping: payload.cards.filter { $0.footer != nil }, by: { $0.footer! })
        unnumberedCards = payload.cards.filter { $0.unnumberedSetMarker != nil }.sorted { $0.id < $1.id }
        products = payload.sealed
        let sourceEvidence = payload.coverage.productEvidence ?? []
        guard Set(sourceEvidence.map(\.productID)).count == sourceEvidence.count else { throw BrowseCatalogError.badResponse }
        let evidenceReferences = Dictionary(uniqueKeysWithValues: sourceEvidence
            .map { ("tcgcsv:71:\($0.productID)", $0.reference) })
        let discoveryRegistry = try LorcanaCatalogRegistry(manifest: .init(schemaVersion: 1, printFamilies: cardsByFooter.map { footer, rows in
            let first = rows.sorted { $0.id < $1.id }[0]
            return .init(footer: footer, providerSetCode: first.sourceSetCode, name: first.name, version: nil,
                rarity: first.rarity, layout: first.layout,
                sourceAliases: rows.map { .init(provider: $0.id.hasPrefix("tcgcsv:") ? "tcgcsv" : "lorcanajson", id: $0.id) },
                footerEvidenceReference: first.id.hasPrefix("lorcanajson:") ? "https://lorcanajson.org/#field-explanation"
                    : evidenceReferences[first.id] ?? "https://tcgcsv.com/")
        }))
        if let manifest = reviewedManifest {
            var families = discoveryRegistry.familiesByFooter
            for family in manifest.printFamilies {
                guard let source = families[family.footer] else { throw BrowseCatalogError.badResponse }
                families[family.footer] = .init(footer: family.footer, providerSetCode: family.providerSetCode,
                    name: family.name, version: family.version, rarity: family.rarity, layout: family.layout,
                    sourceAliases: Array(Set(source.sourceAliases + family.sourceAliases)), footerEvidenceReference: family.footerEvidenceReference)
            }
            registry = try .init(manifest: .init(schemaVersion: 2, reviewedAt: manifest.reviewedAt,
                printFamilies: Array(families.values), canonicalCards: manifest.canonicalCards,
                physicalPrintings: manifest.physicalPrintings, universes: manifest.universes, corrections: manifest.corrections),
                presentationContext: catalogGeneration)
            catalogGeneration = registry.generation
        } else { registry = discoveryRegistry }
        generation = catalogGeneration
        var physicalIDs: [String: UUID] = [:], physicalSources: [String: Card] = [:]
        let sourceCardsByID = cardsByID
        let adapter = LorcanaCatalogAdapter(registry: registry)
        for printing in registry.physicalCatalog?.manifest.physicalPrintings ?? [] {
            guard (try? adapter.resolution(forPrintingID: printing.id)) != nil else { continue }
            let matches = printing.sourceAliases.compactMap { sourceCardsByID[$0.id] }
            guard matches.count == 1, let source = matches.first, source.footer == printing.identity.footer,
                  physicalIDs.updateValue(printing.id, forKey: source.id) == nil else { throw BrowseCatalogError.badResponse }
            physicalSources[printing.id.uuidString.lowercased()] = source
        }
        physicalBySourceID = physicalIDs; sourceByPhysicalID = physicalSources
        var sets: [CatalogSetID: CatalogSet] = [:]
        var summaries: [CatalogSetID: [CatalogCardSummary]] = [:]
        var texts: [String: String] = [:]
        for (id, rows) in Dictionary(grouping: payload.cards, by: \.setID) {
            let ordered = rows.sorted {
                let comparison = CollectorNumber.compare($0.number, $1.number)
                return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
            }
            let first = ordered[0]
            guard ordered.allSatisfy({ $0.setName == first.setName }) else { throw BrowseCatalogError.badResponse }
            let date = Self.date(first.releaseDate)
            let incomplete = payload.coverage.sets[first.setCode]?.hasAllCards == false || first.setCode == "C3"
            let upcoming = (date ?? .distantPast) > asOf
            let name = first.setName + " · EN" + (incomplete ? " · Partial catalog" : upcoming ? " · Upcoming" : "")
            var set = CatalogSet(catalogID: id, name: name, code: first.setCode,
                logoURL: nil, symbolURL: nil, cardCount: ordered.count, releaseDate: date,
                sortRank: Int(first.setCode) ?? 0)
            let rows = ordered.map { card in
                let summary = CatalogCardSummary(game: .lorcana, providerID: physicalIDs[card.id]?.uuidString.lowercased() ?? card.id, setID: id, setName: set.name,
                    setCode: card.setCode, name: card.name, collectorNumber: card.footer?.collectorNumber ?? card.number,
                    thumbnailURL: card.thumbnailURL, imageURL: card.imageURL, catalogGeneration: catalogGeneration)
                texts[summary.id] = CardNameSearch.normalize([card.name, card.printedIdentifier, card.setName,
                    card.setCode, card.distribution ?? ""].joined(separator: " "))
                return summary
            }
            // Keep discovery rows visible while completion counts explicit
            // reviewed UUID targets rather than inferring ownership from aliases.
            if reviewedManifest != nil { set.physicalPrintingIDs = Set(rows.map(\.providerID)) }
            set.artworkFallbackURLs = Array(rows.compactMap(\.thumbnailURL).prefix(3))
            sets[id] = set; summaries[id] = rows
        }
        setsByID = sets; summariesBySetID = summaries; searchTextByID = texts
    }

    var runtime: CardGameRuntime {
        let hasPhysical = registry.physicalCatalog != nil
        let descriptor = CardGameDescriptor(game: .lorcana, displayName: "Disney Lorcana", sortOrder: 3,
            capabilities: hasPhysical ? [.scan, .browse, .sealed, .pricing, .collectionWrite] : Self.descriptor.capabilities)
        return .init(descriptor: descriptor, variantPolicy: hasPhysical ? LorcanaVariantPolicy(registry: registry) : DiscoveryVariants(),
              pricing: hasPhysical ? LorcanaPriceAdapter(registry: registry) : nil,
              recognizer: LorcanaDiscoveryRecognizer(catalog: self), catalog: self, browse: self,
              importer: hasPhysical ? LorcanaImportAdapter(registry: registry) : nil,
              priceAuthority: hasPhysical ? LorcanaPriceAdapter.priceAuthority(registry) : nil,
              requiresLaunchActivation: false)
    }
    private struct DiscoveryVariants: GameVariantPolicy {
        // Discovery is not finish-lock or ownership authority.
        let selectableVariants: [PhysicalVariant] = []
    }

    func sets() async throws -> [CatalogSet] {
        setsByID.values.sorted {
            if $0.releaseDate != $1.releaseDate { return ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
            return $0.id < $1.id
        }
    }
    func cards(in set: CatalogSet, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        guard setsByID[set.catalogID] == set else { throw CatalogLookupError.staleCatalog }
        return try page(summariesBySetID[set.catalogID] ?? [], cursor: cursor, scope: set.id)
    }
    func search(query: String, setIDs: Set<CatalogSetID>, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        guard setIDs.allSatisfy({ setsByID[$0] != nil }) else { throw CatalogLookupError.staleCatalog }
        let normalized = CardNameSearch.normalize(query)
        let scope = ([normalized] + setIDs.map(\.id).sorted()).map { "\($0.utf8.count):\($0)" }.joined()
        let rows = summariesBySetID.filter { setIDs.isEmpty || setIDs.contains($0.key) }.values.flatMap { $0 }
            .filter { normalized.count >= 2 && searchTextByID[$0.id]?.contains(normalized) == true }.sorted { $0.id < $1.id }
        return try page(rows, cursor: cursor, scope: scope)
    }
    func details(for summary: CatalogCardSummary) async throws -> CatalogCardDetails {
        guard summary.game == game, summary.catalogGeneration == generation,
              summariesBySetID[summary.setID]?.contains(summary) == true,
              let card = sourceByPhysicalID[summary.providerID] ?? cardsByID[summary.providerID], let set = setsByID[summary.setID] else { throw CatalogLookupError.staleCatalog }
        if let id = physicalBySourceID[card.id] {
            return .init(card: try physical.resolution(forPrintingID: id).card, set: set, retrievedAt: capturedAt)
        }
        return .init(card: try resolution(card).card, set: set, retrievedAt: capturedAt,
            collectionWriteUnavailableReason: "This printing needs review before it can be added.")
    }

    func identifierForRetry(_ identifier: ScanIdentifier) throws -> ScanIdentifier {
        if identifier.namespace == "printed-footer" {
            return try LorcanaRecognitionAdapter.identifier(validatedFooter(identifier), generation: generation)
        }
        if identifier.namespace == "catalog-record", let id = identifier.fields.first(where: { $0.key == "sourceID" })?.value,
           let row = cardsByID[id], identifier == (try recordIdentifier(row, generation: identifier.catalogGeneration)) {
            return try recordIdentifier(row, generation: generation)
        }
        if identifier.namespace == "printed-unnumbered",
           let row = unnumberedCards.first(where: { (try? unnumberedIdentifier(for: $0, generation: identifier.catalogGeneration)) == identifier }) {
            return try unnumberedIdentifier(for: row, generation: generation)
        }
        throw CatalogLookupError.invalidAdapterOutcome
    }
    func prepareLookupIdentifier(_ identifier: ScanIdentifier) throws -> ScanIdentifier {
        guard identifier.catalogGeneration == generation else { throw CatalogLookupError.staleCatalog }
        guard try identifierForRetry(identifier) == identifier else { throw CatalogLookupError.invalidAdapterOutcome }
        return identifier
    }
    func lookup(_ identifier: ScanIdentifier) async throws -> CatalogLookupOutcome {
        if identifier.namespace == "printed-footer", registry.physicalCatalog != nil {
            let footer = try validatedFooter(prepareLookupIdentifier(identifier))
            if registry.physicalCatalog?.universesByFooter[footer] != nil { return try await physical.lookup(identifier) }
        }
        let rows = try matches(identifier)
        guard let first = rows.first else { return .catalogIncomplete(nil) }
        let canonical = CanonicalCardSummary(id: first.id, game: game, name: first.name,
                                             printedIdentifier: identifier.displayIdentifier, language: "en")
        // Never auto-acquire a source row: neither an app-data record nor an
        // all-print query establishes the standard/oversized/stamped universe.
        return .needsPrintingChoice(canonical: canonical, candidates: rows.map(candidate))
    }
    func resolve(_ choice: PhysicalPrintingCandidate, for identifier: ScanIdentifier) async throws -> CardCatalog.CatalogResolution {
        if UUID(uuidString: choice.id) != nil { return try await physical.resolve(choice, for: identifier) }
        guard let row = try matches(identifier).first(where: { candidate($0) == choice }) else {
            throw CatalogLookupError.invalidPrintingChoice
        }
        return try resolution(row)
    }
    func identifierForCatalogSelection(printingID: String, original: ScanIdentifier) throws -> ScanIdentifier {
        if sourceByPhysicalID[printingID] != nil { return try physical.identifierForCatalogSelection(printingID: printingID, original: original) }
        guard original.game == game, let row = cardsByID[printingID] else { throw CatalogLookupError.invalidPrintingChoice }
        if let footer = row.footer { return try LorcanaRecognitionAdapter.identifier(footer, generation: generation) }
        if row.unnumberedSetMarker != nil { return try unnumberedIdentifier(for: row, generation: generation) }
        // Explicit recovery can select a known record even when its footer is
        // unavailable. This identifier cannot be generated by automatic OCR.
        return try recordIdentifier(row, generation: generation)
    }
    func validateLookupContext(_ identifier: ScanIdentifier) async throws { _ = try prepareLookupIdentifier(identifier) }
    func validateAcquisition(_ identifier: ScanIdentifier, printingID: String, automatic: Bool) async throws {
        if sourceByPhysicalID[printingID] != nil {
            try await physical.validateAcquisition(identifier, printingID: printingID, automatic: automatic); return
        }
        throw CatalogLookupError.catalogIncomplete(nil)
    }
    func validateVariantCorrection(printingID: String, variantID: String?) throws {
        try physical.validateVariantCorrection(printingID: printingID, variantID: variantID)
    }
    func validateCollectionMutation(printingID: String, catalogProviderID: String?, variantID: String?,
                                    itemKindRaw: String, collectionKey: String) throws {
        guard sourceByPhysicalID[printingID] != nil else { throw CatalogLookupError.catalogIncomplete(nil) }
        try physical.validateCollectionMutation(printingID: printingID, catalogProviderID: catalogProviderID,
            variantID: variantID, itemKindRaw: itemKindRaw, collectionKey: collectionKey)
    }
    private func matches(_ identifier: ScanIdentifier) throws -> [Card] {
        _ = try prepareLookupIdentifier(identifier)
        if identifier.namespace == "catalog-record",
           let id = identifier.fields.first(where: { $0.key == "sourceID" })?.value, let row = cardsByID[id] { return [row] }
        if identifier.namespace == "printed-unnumbered" {
            return unnumberedCards.filter { (try? unnumberedIdentifier(for: $0, generation: generation)) == identifier }
        }
        return (cardsByFooter[try validatedFooter(identifier)] ?? []).sorted { $0.id < $1.id }
    }
    private func validatedFooter(_ identifier: ScanIdentifier) throws -> LorcanaPrintedIdentity {
        // Reuse the strict field/display/suppression validation of the reviewed
        // adapter; only its generation is replaced for the discovery snapshot.
        let rebased = try LorcanaCatalogAdapter(registry: registry).identifierForRetry(identifier)
        let fields = Dictionary(uniqueKeysWithValues: rebased.fields.map { ($0.key, $0.value) })
        return try .init(collectorNumber: fields["collectorNumber"]!, denominator: fields["denominator"]!,
                         language: fields["language"]!, printedSetMarker: fields["printedSetMarker"]!)
    }
    func unnumberedIdentifier(generation: String?) throws -> ScanIdentifier {
        guard let row = cardsByID["lorcanajson:en:3551"] else { throw CatalogLookupError.catalogIncomplete(nil) }
        return try unnumberedIdentifier(for: row, generation: generation)
    }
    func unnumberedIdentifier(for row: Card, generation: String?) throws -> ScanIdentifier {
        guard let marker = row.unnumberedSetMarker, let title = row.recognitionTitles?.first else {
            throw CatalogLookupError.invalidAdapterOutcome
        }
        return try .init(game: game, namespace: "printed-unnumbered", fields: [.init(key: "title", value: title),
            .init(key: "language", value: "en"), .init(key: "printedSetMarker", value: marker)],
            displayIdentifier: "\(title) · EN · \(marker)",
            suppressionIdentity: "unnumbered:en:\(marker):" + CardNameSearch.normalize(title).replacingOccurrences(of: " ", with: "-"),
            catalogGeneration: generation)
    }
    private func recordIdentifier(_ row: Card, generation: String?) throws -> ScanIdentifier {
        try .init(game: game, namespace: "catalog-record", fields: [.init(key: "sourceID", value: row.id)],
            displayIdentifier: row.name, suppressionIdentity: "source-record:" + row.id, catalogGeneration: generation)
    }
    private func candidate(_ row: Card) -> PhysicalPrintingCandidate {
        .init(id: row.id, game: game, canonicalCardID: row.id, language: "en", catalogGeneration: generation,
              name: row.name, printedIdentifier: row.printedIdentifier, releaseLabel: row.setName,
              treatmentLabel: row.rarity, distributionLabel: row.distribution,
              thumbnailURL: row.thumbnailURL, artworkID: row.id,
              distinctionLabels: ["Source catalog record", row.layout])
    }
    private func resolution(_ row: Card) throws -> CardCatalog.CatalogResolution {
        let card = try ResolvedCatalogCard(game: game, physicalPrintingID: row.id, canonicalCardID: row.id,
            language: "en", name: row.name, setName: row.setName, setCode: row.setCode,
            cardNumber: row.footer?.collectorNumber ?? row.number, printedIdentifier: row.printedIdentifier,
            rarity: row.rarity, displayImageURL: row.imageURL, thumbnailImageURL: row.thumbnailURL,
            setReleaseOrder: Int(row.sourceSetCode) ?? 0,
            variantEvidence: .init(game: game, setID: row.setID.providerID,
                cardNumber: row.footer?.collectorNumber ?? row.number, catalogVariants: row.variants))
        return .init(card, retrievedAt: capturedAt, path: .cacheHit)
    }

    private struct Cursor: Codable { let generation, scope: String; let offset: Int }
    private func page<T: Sendable>(_ rows: [T], cursor: String?, scope: String) throws -> CatalogPage<T> {
        let fingerprint = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        var offset = 0
        if let cursor {
            guard cursor.count <= 512, let bytes = Data(base64Encoded: cursor), bytes.base64EncodedString() == cursor,
                  let parsed = try? JSONDecoder().decode(Cursor.self, from: bytes),
                  parsed.generation == generation, parsed.scope == fingerprint,
                  parsed.offset > 0, parsed.offset < rows.count, parsed.offset % 60 == 0 else { throw CatalogLookupError.staleCatalog }
            offset = parsed.offset
        }
        let end = min(offset + 60, rows.count)
        let next = end < rows.count ? try JSONEncoder().encode(Cursor(generation: generation, scope: fingerprint, offset: end)).base64EncodedString() : nil
        return .init(items: Array(rows[offset..<end]), nextCursor: next)
    }
    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: String(value.prefix(10)) + "T00:00:00Z")
    }

    func sealedSets(game: CardGame) async throws -> [SealedSetSummary] {
        guard game == self.game else { throw CardGameSupportError.unsupportedGame(game) }
        return Dictionary(grouping: products, by: \.setID).map { id, rows in
            .init(id: id, name: rows[0].setName, sealedCount: rows.count, game: game,
                  releaseDate: rows.compactMap { Self.date($0.releaseDate) }.min())
        }
    }
    func searchSealedProducts(game: CardGame, setID: String?, query: String?, offset: Int) async throws -> MarketCatalogPage<SealedProductSummary> {
        guard game == self.game, offset >= 0, setID == nil || products.contains(where: { $0.setID == setID }) else {
            throw BrowseCatalogError.unknownSet
        }
        let tokens = CardNameSearch.normalize(query ?? "").split(separator: " ").map(String.init)
        let rows = products.filter { product in
            (setID == nil || product.setID == setID) && tokens.allSatisfy {
                CardNameSearch.normalize(product.name + " " + product.setName).contains($0)
            }
        }.sorted { $0.id < $1.id }
        guard offset <= rows.count else { throw CatalogLookupError.staleCatalog }
        let end = min(offset + 60, rows.count)
        return .init(items: rows[offset..<end].map(\.summary), total: rows.count, offset: offset, limit: 60, hasMore: end < rows.count)
    }
}

struct LorcanaDiscoveryRecognizer: GameRecognitionAdapter {
    let catalog: LorcanaDiscoveryCatalog
    let game = CardGame.lorcana
    var customWords: [String] { catalog.registry.customWords + ["TFC"] + catalog.unnumberedCards.flatMap { $0.recognitionTitles ?? [] } }
    func needsFullCardText(afterFooterLines lines: [RecognizedLine]) -> Bool {
        let markers = Set(catalog.unnumberedCards.compactMap(\.unnumberedSetMarker))
        return validLines(lines).contains { line in
            markers.contains { marker in
                line.text.range(of: "\\AEN[\\t •·–—-]+\(marker)\\z", options: [.regularExpression, .caseInsensitive]) != nil
            }
        }
    }
    private func validLines(_ lines: [RecognizedLine]) -> [RecognizedLine] {
        lines.filter { line in
            line.text.utf16.count <= 1_024 && (line.boundingBox.map {
                $0.minX.isFinite && $0.minY.isFinite && $0.width.isFinite && $0.height.isFinite && $0.width > 0 && $0.height > 0
                    && CGRect(x: 0, y: 0, width: 1, height: 1).contains($0)
            } ?? true)
        }
    }
    func identify(_ lines: [RecognizedLine]) -> GameRecognitionOutcome {
        let outcome = LorcanaRecognitionAdapter(registry: catalog.registry).identify(lines)
        // The unnumbered token needs both its exact title and Quest/language
        // footer. Never use its name alone or assign an invented collector number.
        let valid = validLines(lines)
        let texts = Set(valid.map { CardNameSearch.normalize($0.text) })
        let rows = catalog.unnumberedCards.filter { row in
            guard let marker = row.unnumberedSetMarker,
                  valid.contains(where: { $0.text.range(of: "\\AEN[\\t •·–—-]+\(marker)\\z", options: [.regularExpression, .caseInsensitive]) != nil }) else { return false }
            return (row.recognitionTitles ?? []).contains { title in
                if texts.contains(CardNameSearch.normalize(title)) { return true }
                // Character names and versions are separate OCR lines. Require
                // both exact title components; never combine a partial title.
                let parts = title.components(separatedBy: " - ")
                return parts.count == 2 && parts.allSatisfy { texts.contains(CardNameSearch.normalize($0)) }
            }
        }
        if !rows.isEmpty {
            guard rows.count == 1 else { return .ambiguous }
            guard outcome == .nothing else { return .ambiguous }
            if let identifier = try? catalog.unnumberedIdentifier(for: rows[0], generation: catalog.generation) { return .identified(.init(identifier: identifier)) }
        }
        if outcome != .nothing, valid.contains(where: {
            $0.text.range(of: "\\AEN[\\t •·–—-]+Q[0-9]{1,2}\\z", options: [.regularExpression, .caseInsensitive]) != nil
        }) {
            // A numbered footer plus a separate unnumbered Quest footer is
            // conflicting card evidence even before the second title is read.
            return .ambiguous
        }
        if case let .identified(subject) = outcome,
           let identifier = try? catalog.identifierForRetry(subject.identifier) { return .identified(.init(identifier: identifier)) }
        return outcome
    }
}
