import Combine
import Foundation
import SwiftData

struct ImportedCatalogMetadata: Sendable {
    let providerID: String
    let setCode: String
    let rarity: String?
    let imageURL: String?
    let thumbnailURL: String?
    let tcgplayerURL: String?
    let setReleaseOrder: Int
    let justTCGCardID: String?
    let justTCGVariantID: String?
    let justTCGAPIVersion: String?

    init(
        providerID: String,
        setCode: String,
        rarity: String?,
        imageURL: String?,
        thumbnailURL: String?,
        tcgplayerURL: String?,
        setReleaseOrder: Int,
        justTCGCardID: String? = nil,
        justTCGVariantID: String? = nil,
        justTCGAPIVersion: String? = nil
    ) {
        self.providerID = providerID
        self.setCode = setCode
        self.rarity = rarity
        self.imageURL = imageURL
        self.thumbnailURL = thumbnailURL
        self.tcgplayerURL = tcgplayerURL
        self.setReleaseOrder = setReleaseOrder
        self.justTCGCardID = justTCGCardID
        self.justTCGVariantID = justTCGVariantID
        self.justTCGAPIVersion = justTCGAPIVersion
    }
}

private struct ImportedCatalogRequest: Hashable, Sendable {
    let sourceProviderID: String
    let game: CardGame
    let name: String
    let setName: String
    let cardNumber: String
    let itemKind: CollectionItemKind
}

private struct ImportedCatalogResolution: Sendable {
    var matches: [String: ImportedCatalogMetadata] = [:]
    /// Sealed rows for which the vendor directory and every relevant product
    /// page completed successfully, but no unambiguous product existed.
    var definitiveSealedMisses: Set<String> = []
}

fileprivate struct ImportedCatalogRowIdentity: Sendable {
    let collectionKey: String
    let priceKey: String
    let providerID: String
    let catalogProviderID: String?
    let marketVariantID: String?
    let itemKind: CollectionItemKind
}

fileprivate struct ImportedCatalogNormalizationInputs: Sendable {
    let requests: [ImportedCatalogRequest]
    let rowIdentitiesByProviderID: [String: [ImportedCatalogRowIdentity]]
}

/// Imports stay local and immediate. This second layer quietly turns their
/// human-readable identity into provider metadata without involving pricing.
@MainActor
final class CollectionCatalogNormalizer: ObservableObject {
    typealias ContinuationCheck = @MainActor @Sendable () -> Bool

    enum Status: Equatable {
        case idle
        case normalizing(total: Int)
        case finished(matched: Int, unmatched: Int)
        case failed
    }

    @Published private(set) var status: Status = .idle

    private let resolver: ImportedCatalogBatchResolver
    private nonisolated static let retryInterval: TimeInterval = 8 * 60 * 60
    /// Bumped whenever the resolver learns to match something it previously
    /// could not, so existing collections re-run against the new rules instead
    /// of waiting out `retryInterval` on a stale result.
    ///
    /// 6: exact English Pokémon artwork fallback and Magic child-set routing.
    /// 7: distinguish definitive sealed misses from transient provider failures.
    /// 8: retry missing sealed artwork against TCGplayer's direct product CDN,
    /// and locally rewrite legacy gateway URLs without spending a request.
    /// 9: retry missing Pokémon artwork through exact TCGdex card details.
    nonisolated static let metadataVersion = 9
    private var requestsAnotherPass = false
    /// Input discovery now suspends at the model actor. Keep the same
    /// single-flight guarantee that the old synchronous discovery had, so a
    /// second view appearance cannot start a duplicate provider crawl while
    /// the first one is still reading the collection.
    private var isCollectingInputs = false

    init(
        tcgdex: any TCGdexCatalogSource = TCGdexService(),
        justTCG: JustTCGV1Client = JustTCGV1Client(transport: JustTCGTransport.shared)
    ) {
        self.resolver = ImportedCatalogBatchResolver(tcgdex: tcgdex, justTCG: justTCG)
    }

    /// Production callers use a context dedicated to catalog normalization.
    /// A network-paced task must not hold the UI context's pending mutations or
    /// let its save/rollback interact with a scanner transaction.
    func normalizeImportedCards(
        in container: ModelContainer,
        shouldContinue: ContinuationCheck? = nil
    ) async {
        let normalizationContext = ModelContext(container)
        await normalizeImportedCards(
            in: normalizationContext,
            shouldContinue: shouldContinue
        )
    }

    func normalizeImportedCards(
        in context: ModelContext,
        shouldContinue: ContinuationCheck? = nil
    ) async {
        guard shouldContinue?() ?? true else { return }
        if case .normalizing = status {
            requestsAnotherPass = true
            return
        }
        if isCollectingInputs {
            requestsAnotherPass = true
            return
        }

        let now = Date.now
        isCollectingInputs = true
        let inputActor = CollectionCatalogNormalizationInputActor(
            modelContainer: context.container
        )
        let inputs = await inputActor.inputs(now: now)
        isCollectingInputs = false
        guard shouldContinue?() ?? true else { return }
        let requests = inputs.requests

        guard !requests.isEmpty else {
            let shouldRunAnotherPass = requestsAnotherPass
            requestsAnotherPass = false
            if shouldRunAnotherPass {
                await normalizeImportedCards(
                    in: context,
                    shouldContinue: shouldContinue
                )
            }
            return
        }
        // The network phase keeps only collection keys and identity values.
        // The apply phase below re-fetches every row in a fresh serialized
        // context after provider work has completed.
        let container = context.container
        let rowIdentitiesByProviderID = inputs.rowIdentitiesByProviderID
        status = .normalizing(total: requests.count)

        let resolution = await resolver.resolve(Array(requests))
        let matches = resolution.matches
        guard !Task.isCancelled, shouldContinue?() ?? true else {
            requestsAnotherPass = false
            status = .idle
            return
        }

        let needsIdentityGate = requests.contains { request in
            guard let metadata = matches[request.sourceProviderID],
                  let marketVariantID = metadata.justTCGVariantID else { return false }
            guard let snapshots = rowIdentitiesByProviderID[request.sourceProviderID] else {
                return false
            }
            return snapshots.contains { row in
                row.itemKind != .rawCard && row.marketVariantID != marketVariantID
            }
        }
        func applyResolvedMetadata() throws {
            try CollectionWriteSerializer.perform(
                container: container,
                timeout: .mainThread
            ) { writeContext in
                    let priceLog = PriceObservationLog(context: writeContext)
                    for request in requests {
                        guard shouldContinue?() ?? true else {
                            throw CancellationError()
                        }
                        let snapshots = rowIdentitiesByProviderID[request.sourceProviderID] ?? []
                        let rowKeys = Array(Set(snapshots.map(\.collectionKey)))
                        guard !rowKeys.isEmpty else { continue }
                        let liveRows = try writeContext.fetch(
                            FetchDescriptor<CollectedCard>(
                                predicate: #Predicate { rowKeys.contains($0.collectionKey) }
                            )
                        )
                        let snapshotsByKey = Dictionary(
                            snapshots.map { ($0.collectionKey, $0) },
                            uniquingKeysWith: { first, _ in first }
                        )
                        let rows = liveRows.filter { row in
                            guard let snapshot = snapshotsByKey[row.collectionKey] else { return false }
                            return row.priceKey == snapshot.priceKey
                                && row.providerID == snapshot.providerID
                                && row.catalogProviderID == snapshot.catalogProviderID
                                && row.justTCGVariantID == snapshot.marketVariantID
                        }
                        if let metadata = matches[request.sourceProviderID] {
                            for row in rows {
                                let exactIdentityMatches: Bool
                                let preserveExistingMetadata: Bool
                                if let exactCatalogID = row.catalogProviderID {
                                    exactIdentityMatches = exactCatalogID == metadata.providerID
                                    preserveExistingMetadata = exactIdentityMatches
                                } else {
                                    exactIdentityMatches = row.providerID == metadata.providerID
                                        || row.providerID.hasPrefix("csv:")
                                    preserveExistingMetadata = row.providerID == metadata.providerID
                                }
                                guard exactIdentityMatches else { continue }
                                let previousVariantID = row.justTCGVariantID
                                let previousPriceKey = row.priceKey
                                if previousVariantID == nil,
                                   let currentVariantID = metadata.justTCGVariantID {
                                    let apiVersion = metadata.justTCGAPIVersion
                                        ?? (row.itemKind == .gradedCard ? "v2" : "v1")
                                    try PriceIdentityLineageMigration.promoteUnboundPriceIdentity(
                                        for: row,
                                        toMarketVariantID: currentVariantID,
                                        apiVersion: apiVersion,
                                        in: writeContext
                                    )
                                }
                                row.applyCatalogMetadata(
                                    metadata,
                                    fillMissingOnly: preserveExistingMetadata
                                )
                                let normalizedRow: CollectedCard
                                if row.itemKind == .sealedProduct,
                                   let productID = metadata.justTCGCardID,
                                   let marketVariantID = metadata.justTCGVariantID {
                                    let canonicalKey = CollectedCard.sealedCollectionKey(
                                        game: row.cardGame,
                                        productUUID: productID,
                                        variantUUID: marketVariantID,
                                        magicTreatments: row.magicTreatments
                                    )
                                    normalizedRow = try CollectionStore(context: writeContext).rekey(
                                        row,
                                        to: canonicalKey,
                                        magicTreatmentIDsRaw: row.magicTreatmentIDsRaw,
                                        magicTreatmentQualifiers: row.magicTreatmentQualifiers
                                    )
                                    normalizedRow.applyCatalogMetadata(
                                        metadata,
                                        fillMissingOnly: preserveExistingMetadata
                                    )
                                } else {
                                    normalizedRow = row
                                }
                                Self.recordCatalogMetadataCheck(on: normalizedRow, at: now)
                                if let previousVariantID,
                                   let currentVariantID = metadata.justTCGVariantID,
                                   previousVariantID != currentVariantID {
                                    _ = priceLog.recordInvalidation(
                                        instrumentKey: previousPriceKey,
                                        source: .justTCG,
                                        at: now
                                    )
                                }
                            }
                        } else {
                            let isDefinitiveSealedMiss = request.itemKind == .sealedProduct
                                && resolution.definitiveSealedMisses.contains(request.sourceProviderID)
                            for row in rows {
                                Self.recordCatalogMetadataCheck(
                                    on: row,
                                    at: now,
                                    version: isDefinitiveSealedMiss
                                        ? -Self.metadataVersion
                                        : Self.metadataVersion
                                )
                            }
                        }
                    }
                    if writeContext.hasChanges { try writeContext.save() }
                }
        }

        do {
            if needsIdentityGate {
                try await CollectionExclusiveWrites.withPriceIdentityExclusivity {
                    try applyResolvedMetadata()
                }
            } else {
                try applyResolvedMetadata()
            }
            guard shouldContinue?() ?? true else {
                requestsAnotherPass = false
                status = .idle
                return
            }
            status = .finished(
                matched: matches.count,
                unmatched: max(0, requests.count - matches.count)
            )
            let completedStatus = status
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard self?.status == completedStatus else { return }
                self?.status = .idle
            }
            if requestsAnotherPass {
                requestsAnotherPass = false
                await normalizeImportedCards(
                    in: ModelContext(container),
                    shouldContinue: shouldContinue
                )
            }
        } catch {
            requestsAnotherPass = false
            status = Task.isCancelled || !(shouldContinue?() ?? true) ? .idle : .failed
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard self?.status == .failed else { return }
                self?.status = .idle
            }
        }
    }

    /// Definitive sealed misses stay asleep until the resolver version changes.
    /// Transient failures never receive the current version stamp, so they
    /// remain eligible without turning a deterministic miss into an 8-hour
    /// metered request loop.
    nonisolated static func needsNormalization(_ card: CollectedCard, now: Date = .now) -> Bool {
        guard hasUnresolvedCatalogMetadata(card) else { return false }
        if card.itemKind == .sealedProduct,
           card.justTCGCardID == nil,
           card.justTCGVariantID == nil,
           card.catalogMetadataVersion < 0 {
            // The same resolver already completed this miss. A version bump
            // deliberately reopens it once against improved matching rules.
            return card.catalogMetadataVersion != -Self.metadataVersion
        }
        if card.catalogMetadataVersion < Self.metadataVersion { return true }
        guard let checkedAt = card.catalogMetadataCheckedAt else { return true }
        return now.timeIntervalSince(checkedAt) >= Self.retryInterval
    }

    /// Whether the normalizer still has something to repair on this row.
    ///
    /// This deliberately asks what the row is *missing* rather than where it
    /// came from. The gate used to require a synthetic `csv:` provider id,
    /// which silently assumed every imported row had one. It does not: a CSV
    /// that carries a real `provider_id` keeps that id verbatim, and only a
    /// row without one is given a synthetic `csv:` identity. Rows imported
    /// with real provider ids were therefore excluded from normalization
    /// permanently, so their rarity, artwork and catalog identity stayed
    /// empty for the life of the collection with no path back.
    ///
    /// Missing rarity alone is not actionable once an exact provider printing
    /// ID is attached. The Pokémon resolver cannot supply rarity, so treating
    /// it as unresolved would refetch the row every eight hours indefinitely.
    nonisolated static func hasUnresolvedCatalogMetadata(_ card: CollectedCard) -> Bool {
        if card.catalogProviderID == nil { return true }
        if card.imageURL == nil { return true }
        return false
    }

    nonisolated static func isDefinitiveSealedMiss(_ card: CollectedCard) -> Bool {
        card.itemKind == .sealedProduct
            && card.providerID.hasPrefix("csv:")
            && card.justTCGCardID == nil
            && card.justTCGVariantID == nil
            && card.catalogMetadataCheckedAt != nil
            && card.catalogMetadataVersion == -Self.metadataVersion
    }

    /// The sole writer for the catalog normalizer's retry watermark. Other
    /// services may discover metadata or sealed artwork, but they must report
    /// that observation through this method instead of mutating the gate.
    nonisolated static func recordCatalogMetadataCheck(
        on card: CollectedCard,
        at checkedAt: Date,
        version: Int = metadataVersion
    ) {
        card.catalogMetadataCheckedAt = checkedAt
        card.catalogMetadataVersion = version
    }

    /// Records a completed artwork lookup while the sealed row is still
    /// missing artwork. The caller invokes this before applying a returned
    /// image so the same helper remains valid for both a hit and a miss.
    nonisolated static func recordSealedArtworkCheck(
        on card: CollectedCard,
        at checkedAt: Date
    ) {
        guard card.itemKind == .sealedProduct, card.imageURL == nil else { return }
        recordCatalogMetadataCheck(on: card, at: checkedAt)
    }

    nonisolated static func migratedLegacySealedArtworkURL(from imageURL: String?) -> String? {
        JustTCGV1Client.migratedProductImageURL(from: imageURL)?.absoluteString
    }

}

/// Reads and repairs the normalizer's durable inputs away from the main actor.
/// Only value requests and row identities cross back to the UI-owned
/// normalizer, so no SwiftData model or persistent identifier is retained
/// across the provider suspension.
@ModelActor
actor CollectionCatalogNormalizationInputActor {
    fileprivate func inputs(now: Date) -> ImportedCatalogNormalizationInputs {
        let readContext = ModelContext(modelContext.container)
        var allCards = (try? readContext.fetch(FetchDescriptor<CollectedCard>())) ?? []
        let repairs = allCards.compactMap { card -> (key: String, oldURL: String, newURL: String, updateThumbnail: Bool)? in
            guard card.itemKind == .sealedProduct,
                  let oldURL = card.imageURL,
                  let newURL = CollectionCatalogNormalizer
                    .migratedLegacySealedArtworkURL(from: oldURL) else {
                return nil
            }
            return (card.collectionKey, oldURL, newURL, card.thumbnailURL != nil)
        }
        if !repairs.isEmpty {
            do {
                try CollectionWriteSerializer.perform(
                    container: modelContext.container,
                    timeout: .wait
                ) { context in
                    let keys = Array(Set(repairs.map(\.key)))
                    let rows = try context.fetch(
                        FetchDescriptor<CollectedCard>(
                            predicate: #Predicate { keys.contains($0.collectionKey) }
                        )
                    )
                    let repairsByKey = Dictionary(
                        repairs.map { ($0.key, $0) },
                        uniquingKeysWith: { first, _ in first }
                    )
                    for row in rows {
                        guard let repair = repairsByKey[row.collectionKey],
                              row.itemKind == .sealedProduct,
                              row.imageURL == repair.oldURL else { continue }
                        row.imageURL = repair.newURL
                        if repair.updateThumbnail { row.thumbnailURL = repair.newURL }
                    }
                    if context.hasChanges { try context.save() }
                }
                readContext.rollback()
                allCards = try readContext.fetch(FetchDescriptor<CollectedCard>())
            } catch {
                // The later normalization attempt can retry this idempotent
                // value patch; a failed stale context never saves the row.
                readContext.rollback()
            }
        }

        let candidates = allCards.filter {
            CollectionCatalogNormalizer.needsNormalization($0, now: now)
        }
        let requests = Dictionary(
            candidates.map { card in
                (
                    card.providerID,
                    ImportedCatalogRequest(
                        sourceProviderID: card.providerID,
                        game: card.cardGame,
                        name: card.name,
                        setName: card.setName,
                        cardNumber: card.cardNumber,
                        itemKind: card.itemKind
                    )
                )
            },
            uniquingKeysWith: { first, _ in first }
        ).values.sorted { $0.sourceProviderID < $1.sourceProviderID }
        let rowIdentitiesByProviderID = candidates.reduce(
            into: [String: [ImportedCatalogRowIdentity]]()
        ) { result, card in
            result[card.providerID, default: []].append(
                ImportedCatalogRowIdentity(
                    collectionKey: card.collectionKey,
                    priceKey: card.priceKey,
                    providerID: card.providerID,
                    catalogProviderID: card.catalogProviderID,
                    marketVariantID: card.justTCGVariantID,
                    itemKind: card.itemKind
                )
            )
        }
        return ImportedCatalogNormalizationInputs(
            requests: requests,
            rowIdentitiesByProviderID: rowIdentitiesByProviderID
        )
    }
}

/// Stateless and Sendable so the two provider-specific strategies can run in
/// parallel without sharing mutable lookup state.
private struct ImportedCatalogBatchResolver: Sendable {
    private let tcgdex: any TCGdexCatalogSource
    private let pokemonArtwork = PokemonTCGAPIService()
    private let scryfall = ScryfallService()
    private let justTCG: JustTCGV1Client
    private static let pokemonConcurrency = 4

    init(
        tcgdex: any TCGdexCatalogSource = TCGdexService(),
        justTCG: JustTCGV1Client = JustTCGV1Client(transport: JustTCGTransport.shared)
    ) {
        self.tcgdex = tcgdex
        self.justTCG = justTCG
    }

    func resolve(_ requests: [ImportedCatalogRequest]) async -> ImportedCatalogResolution {
        // Sealed identity is the only artwork pass here that consumes the
        // metered JustTCG allowance. Finish it first so raw-card catalog work
        // can never race it for the requests intentionally reserved above the
        // background ceiling.
        var resolution = await resolveSealed(requests.filter { $0.itemKind == .sealedProduct })
        var result = resolution.matches
        let cards = requests.filter { $0.itemKind != .sealedProduct }
        async let pokemon = resolvePokemon(cards.filter { $0.game == .pokemon })
        async let magic = resolveMagic(cards.filter { $0.game == .magic })
        result.merge(await pokemon, uniquingKeysWith: { first, _ in first })
        result.merge(await magic, uniquingKeysWith: { first, _ in first })
        let missingArtwork = requests.filter { request in
            guard request.game == .pokemon, request.itemKind == .rawCard else { return false }
            guard CatalogIdentityNormalization.japaneseSetID(forImportedName: request.setName) == nil
            else { return false }
            return result[request.sourceProviderID]?.imageURL == nil
        }
        guard !missingArtwork.isEmpty else {
            resolution.matches = result
            return resolution
        }

        var cursor = 0
        await withTaskGroup(of: (String, PokemonTCGAPICard)?.self) { group in
            let initial = min(Self.pokemonConcurrency, missingArtwork.count)
            for _ in 0..<initial {
                let request = missingArtwork[cursor]
                cursor += 1
                group.addTask { [pokemonArtwork] in
                    guard let card = try? await pokemonArtwork.fetchArtwork(
                        name: request.name,
                        setName: request.setName,
                        cardNumber: request.cardNumber
                    ) else { return nil }
                    return (request.sourceProviderID, card)
                }
            }
            while let match = await group.next() {
                if let (sourceID, card) = match {
                    if let existing = result[sourceID] {
                        result[sourceID] = ImportedCatalogMetadata(
                            providerID: existing.providerID,
                            setCode: existing.setCode,
                            rarity: existing.rarity,
                            imageURL: card.images.large.absoluteString,
                            thumbnailURL: card.images.small.absoluteString,
                            tcgplayerURL: existing.tcgplayerURL,
                            setReleaseOrder: existing.setReleaseOrder,
                            justTCGCardID: existing.justTCGCardID,
                            justTCGVariantID: existing.justTCGVariantID,
                            justTCGAPIVersion: existing.justTCGAPIVersion
                        )
                    } else {
                        result[sourceID] = ImportedCatalogMetadata(
                            providerID: card.id,
                            setCode: "",
                            rarity: nil,
                            imageURL: card.images.large.absoluteString,
                            thumbnailURL: card.images.small.absoluteString,
                            tcgplayerURL: nil,
                            setReleaseOrder: 0
                        )
                    }
                }
                if cursor < missingArtwork.count, !Task.isCancelled {
                    let request = missingArtwork[cursor]
                    cursor += 1
                    group.addTask { [pokemonArtwork] in
                        guard let card = try? await pokemonArtwork.fetchArtwork(
                            name: request.name,
                            setName: request.setName,
                            cardNumber: request.cardNumber
                        ) else { return nil }
                        return (request.sourceProviderID, card)
                    }
                }
            }
        }
        resolution.matches = result
        return resolution
    }

    /// Imported sealed products have names and sets but no marketplace UUID.
    /// Resolve a whole set at once so several boxes cost one catalogue request
    /// instead of one request each.
    private func resolveSealed(
        _ requests: [ImportedCatalogRequest]
    ) async -> ImportedCatalogResolution {
        guard !requests.isEmpty, PriceVendorCredentials.hasKey else { return .init() }
        var resolution = ImportedCatalogResolution()

        for game in CardGame.allCases {
            let gameRequests = requests.filter { $0.game == game }
            guard !gameRequests.isEmpty else { continue }
            let sets: [SealedSetSummary]
            do {
                sets = try await justTCG.sealedSets(game: game)
            } catch {
                // No current-version stamp: connectivity, quota and provider
                // failures are retryable and must not masquerade as no match.
                continue
            }
            guard !Task.isCancelled else { return resolution }

            var requestsBySetID: [String: [ImportedCatalogRequest]] = [:]
            for request in gameRequests {
                let importedSet = CatalogIdentityNormalization.canonicalSetName(
                    request.setName,
                    game: game
                )
                guard let set = sets.first(where: {
                    CatalogIdentityNormalization.canonicalSetName($0.name, game: game) == importedSet
                }) else {
                    resolution.definitiveSealedMisses.insert(request.sourceProviderID)
                    continue
                }
                requestsBySetID[set.id, default: []].append(request)
            }

            for (setID, setRequests) in requestsBySetID.sorted(by: { $0.key < $1.key }) {
                var products: [SealedProductSummary] = []
                var offset = 0
                var completedCatalog = true
                repeat {
                    let page: MarketCatalogPage<SealedProductSummary>
                    do {
                        page = try await justTCG.searchSealedProducts(
                            game: game,
                            setID: setID,
                            query: nil,
                            offset: offset
                        )
                    } catch {
                        completedCatalog = false
                        break
                    }
                    products += page.items
                    guard page.hasMore, !page.items.isEmpty else { break }
                    offset += page.items.count
                } while !Task.isCancelled

                guard completedCatalog, !Task.isCancelled else { continue }

                for request in setRequests {
                    guard let product = Self.matchingSealedProduct(
                        named: request.name,
                        in: products
                    ) else {
                        resolution.definitiveSealedMisses.insert(request.sourceProviderID)
                        continue
                    }
                    resolution.matches[request.sourceProviderID] = ImportedCatalogMetadata(
                        providerID: product.id,
                        setCode: "",
                        rarity: nil,
                        imageURL: product.imageURL?.absoluteString,
                        thumbnailURL: product.imageURL?.absoluteString,
                        tcgplayerURL: nil,
                        setReleaseOrder: 0,
                        justTCGCardID: product.id,
                        justTCGVariantID: product.variantID,
                        justTCGAPIVersion: JustTCGV1Client.apiVersion
                    )
                }
            }
        }
        return resolution
    }

    private static func matchingSealedProduct(
        named importedName: String,
        in products: [SealedProductSummary]
    ) -> SealedProductSummary? {
        let normalized = CatalogIdentityNormalization.canonicalText(importedName)
        let exact = products.filter {
            CatalogIdentityNormalization.canonicalText($0.name) == normalized
        }
        if exact.count == 1 { return exact[0] }

        // Parenthetical retailer/exclusive labels sometimes differ between
        // exports. Accept a relaxed match only when it is unambiguous.
        let relaxed = products.filter {
            CatalogIdentityNormalization.namesMatch(imported: importedName, catalog: $0.name)
        }
        return relaxed.count == 1 ? relaxed[0] : nil
    }

    private func resolvePokemon(
        _ requests: [ImportedCatalogRequest]
    ) async -> [String: ImportedCatalogMetadata] {
        guard !requests.isEmpty,
              let directory = try? await tcgdex.fetchSetDirectory(locale: .en) else {
            return [:]
        }

        var requestsBySetID: [String: [ImportedCatalogRequest]] = [:]
        var japaneseRequestsBySetID: [String: [ImportedCatalogRequest]] = [:]
        for request in requests {
            // Japanese-exclusive sets are absent from the English edition
            // entirely, so they are routed by an explicit name map rather than
            // by directory search — there is nothing there to find.
            if let japaneseSetID = CatalogIdentityNormalization.japaneseSetID(
                forImportedName: request.setName
            ) {
                japaneseRequestsBySetID[japaneseSetID, default: []].append(request)
                continue
            }
            guard let set = CatalogIdentityNormalization.matchingSet(
                named: request.setName,
                in: directory,
                game: .pokemon
            ) else { continue }
            requestsBySetID[set.id, default: []].append(request)
        }

        let groups = requestsBySetID.sorted { $0.key < $1.key }
            .map { (setID: $0.key, requests: $0.value, locale: TCGdexLocale.en) }
            + japaneseRequestsBySetID.sorted { $0.key < $1.key }
                .map { (setID: $0.key, requests: $0.value, locale: TCGdexLocale.ja) }
        let registry = PokemonCatalogRegistry.bundledSeed
        var result: [String: ImportedCatalogMetadata] = [:]
        var cursor = 0

        await withTaskGroup(of: [String: ImportedCatalogMetadata].self) { group in
            let initial = min(Self.pokemonConcurrency, groups.count)
            for _ in 0..<initial {
                let next = groups[cursor]
                cursor += 1
                group.addTask { [tcgdex] in
                    await Self.resolvePokemonSet(
                        id: next.setID,
                        requests: next.requests,
                        locale: next.locale,
                        service: tcgdex,
                        registry: registry
                    )
                }
            }

            while let matches = await group.next() {
                result.merge(matches, uniquingKeysWith: { first, _ in first })
                if cursor < groups.count, !Task.isCancelled {
                    let next = groups[cursor]
                    cursor += 1
                    group.addTask { [tcgdex] in
                        await Self.resolvePokemonSet(
                            id: next.setID,
                            requests: next.requests,
                            locale: next.locale,
                            service: tcgdex,
                            registry: registry
                        )
                    }
                }
            }
        }
        return result
    }

    private nonisolated static func resolvePokemonSet(
        id: String,
        requests: [ImportedCatalogRequest],
        locale: TCGdexLocale = .en,
        service: any TCGdexCatalogSource,
        registry: PokemonCatalogRegistry
    ) async -> [String: ImportedCatalogMetadata] {
        guard let set = try? await service.fetchSet(id: id, locale: locale) else { return [:] }
        let cardsByNumber = Dictionary(grouping: set.cards) {
            CatalogIdentityNormalization.localNumber($0.localId)
        }
        let printedCode: String
        if let registryCode = registry.printedCode(forProviderSetID: set.id) {
            printedCode = registryCode
        } else {
            PokemonCatalogDiagnostics.recordPersistedPlaceholderCode(providerSetID: set.id)
            printedCode = set.id.uppercased()
        }
        let releaseOrder = registry.releaseOrder(forProviderSetID: set.id) ?? 0

        var resolvedBriefs: [(ImportedCatalogRequest, TCGdexCardBrief)] = []
        for request in requests {
            let number = CatalogIdentityNormalization.localNumber(request.cardNumber)
            guard let candidates = cardsByNumber[number] else { continue }
            // The Japanese edition names cards in Japanese while imports carry
            // the English name, so a name check there would reject every card.
            // Set plus number is already a unique identity, and it is the whole
            // of what the import can be trusted to state for these sets.
            let card: TCGdexCardBrief?
            if locale == .ja {
                card = candidates.count == 1 ? candidates[0] : nil
            } else {
                card = candidates.first {
                    CatalogIdentityNormalization.namesMatch(imported: request.name, catalog: $0.name)
                }
            }
            guard let card else { continue }
            resolvedBriefs.append((request, card))
        }
        var result: [String: ImportedCatalogMetadata] = [:]
        var cursor = 0
        await withTaskGroup(of: (String, ImportedCatalogMetadata?).self) { group in
            let initial = min(Self.pokemonConcurrency, resolvedBriefs.count)
            for _ in 0..<initial {
                let (request, brief) = resolvedBriefs[cursor]
                cursor += 1
                group.addTask {
                    (
                        request.sourceProviderID,
                        await Self.pokemonMetadata(
                            request: request,
                            brief: brief,
                            setID: set.id,
                            locale: locale,
                            printedCode: printedCode,
                            releaseOrder: releaseOrder,
                            service: service
                        )
                    )
                }
            }
            while let (sourceID, metadata) = await group.next() {
                if let metadata { result[sourceID] = metadata }
                guard cursor < resolvedBriefs.count, !Task.isCancelled else { continue }
                let (request, brief) = resolvedBriefs[cursor]
                cursor += 1
                group.addTask {
                    (
                        request.sourceProviderID,
                        await Self.pokemonMetadata(
                            request: request,
                            brief: brief,
                            setID: set.id,
                            locale: locale,
                            printedCode: printedCode,
                            releaseOrder: releaseOrder,
                            service: service
                        )
                    )
                }
            }
        }
        return result
    }

    private nonisolated static func pokemonMetadata(
        request: ImportedCatalogRequest,
        brief: TCGdexCardBrief,
        setID: String,
        locale: TCGdexLocale,
        printedCode: String,
        releaseOrder: Int,
        service: any TCGdexCatalogSource
    ) async -> ImportedCatalogMetadata {
        var imageURL = usableTCGdexImageURL(brief.image) ? brief.image : nil
        if imageURL == nil,
           let exact = try? await service.fetchCard(
               setID: setID,
               localID: brief.localId,
               locale: locale,
               ignoringCache: true
           ),
           exact.id.caseInsensitiveCompare(brief.id) == .orderedSame,
           exact.set.id.caseInsensitiveCompare(setID) == .orderedSame,
           CatalogIdentityNormalization.localNumber(exact.localId)
                == CatalogIdentityNormalization.localNumber(brief.localId),
           CatalogIdentityNormalization.namesMatch(
                imported: brief.name,
                catalog: exact.name
           ),
           usableTCGdexImageURL(exact.image) {
            imageURL = exact.image
        }

        return ImportedCatalogMetadata(
            providerID: brief.id,
            setCode: printedCode,
            rarity: nil,
            imageURL: imageURL,
            thumbnailURL: imageURL.map { $0 + "/low.png" },
            tcgplayerURL: nil,
            setReleaseOrder: releaseOrder
        )
    }

    private nonisolated static func usableTCGdexImageURL(_ value: String?) -> Bool {
        guard let value,
              let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "assets.tcgdex.net",
              !url.path.isEmpty else { return false }
        return true
    }

    private func resolveMagic(
        _ requests: [ImportedCatalogRequest]
    ) async -> [String: ImportedCatalogMetadata] {
        guard !requests.isEmpty else { return [:] }
        async let setDirectory = scryfall.fetchSetDirectory()
        async let childDirectory = scryfall.fetchChildSets()
        guard let directory = try? await setDirectory else {
            return [:]
        }
        let childSets = (try? await childDirectory) ?? [:]

        struct LookupKey: Hashable {
            let set: String
            /// Empty for sets matched by card name instead of by number.
            let number: String
            let name: String
        }

        var requestsByLookup: [LookupKey: [ImportedCatalogRequest]] = [:]
        for request in requests {
            guard let set = CatalogIdentityNormalization.matchingSets(
                named: request.setName,
                cardName: request.name,
                in: directory,
                game: .magic
            ).first else { continue }
            let parentSetID = set.id.lowercased()
            let setID: String
            if CatalogIdentityNormalization.isTokenName(request.name),
               let child = ScryfallService.childSet(
                   for: .token,
                   parentCode: parentSetID,
                   in: childSets
               ) {
                setID = child.code.lowercased()
            } else {
                setID = parentSetID
            }
            let key: LookupKey
            if CatalogIdentityNormalization.matchesByCardName(setID: setID) {
                key = LookupKey(set: setID, number: "", name: request.name)
            } else {
                key = LookupKey(
                    set: setID,
                    number: CatalogIdentityNormalization.localNumber(request.cardNumber),
                    name: ""
                )
                guard !key.number.isEmpty else { continue }
            }
            requestsByLookup[key, default: []].append(request)
        }

        let lookups = requestsByLookup.keys.sorted {
            if $0.set != $1.set { return $0.set < $1.set }
            return $0.number == $1.number ? $0.name < $1.name : $0.number < $1.number
        }
        var result: [String: ImportedCatalogMetadata] = [:]

        for start in stride(from: 0, to: lookups.count, by: 75) {
            guard !Task.isCancelled else { break }
            let batch = Array(lookups[start..<min(start + 75, lookups.count)])
            let identifiers = batch.map { key in
                key.number.isEmpty
                    ? ScryfallCardIdentifier(set: key.set, name: key.name)
                    : ScryfallCardIdentifier(set: key.set, collectorNumber: key.number)
            }
            guard let cards = try? await scryfall.fetchCards(identifiers: identifiers) else {
                continue
            }

            // A response is indexed both ways, because one batch can mix
            // number-keyed and name-keyed lookups.
            var cardsByLookup: [LookupKey: [ScryfallCard]] = [:]
            for card in cards {
                let setID = card.setCode.lowercased()
                let numberKey = LookupKey(
                    set: setID,
                    number: CatalogIdentityNormalization.localNumber(card.collectorNumber),
                    name: ""
                )
                cardsByLookup[numberKey, default: []].append(card)
                let nameKey = LookupKey(set: setID, number: "", name: card.name)
                cardsByLookup[nameKey, default: []].append(card)
            }
            for key in batch {
                var candidates = cardsByLookup[key]
                // Name-keyed lookups echo Scryfall's own spelling, which may
                // differ from the request's; fall back to matching within the
                // set rather than losing the card over punctuation.
                if candidates == nil, key.number.isEmpty {
                    candidates = cards.filter {
                        $0.setCode.lowercased() == key.set
                            && CatalogIdentityNormalization.namesMatch(
                                imported: key.name,
                                catalog: $0.name
                            )
                    }
                }
                guard let candidates, !candidates.isEmpty else { continue }
                for request in requestsByLookup[key] ?? [] {
                    guard let card = candidates.first(where: {
                        CatalogIdentityNormalization.namesMatch(imported: request.name, catalog: $0.name)
                    }) else { continue }
                    result[request.sourceProviderID] = ImportedCatalogMetadata(
                        providerID: card.id,
                        setCode: card.setCode.uppercased(),
                        rarity: card.rarity,
                        imageURL: card.displayImageURL?.absoluteString,
                        thumbnailURL: card.thumbnailImageURL?.absoluteString,
                        tcgplayerURL: card.purchaseURIs?.tcgplayer?.absoluteString,
                        setReleaseOrder: card.releaseDate.map {
                            Int($0.timeIntervalSince1970 / 86_400)
                        } ?? 0
                    )
                }
            }

            if start + 75 < lookups.count {
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        return result
    }
}

enum CatalogIdentityNormalization {
    static func matchingSet(
        named importedName: String,
        in directory: [CatalogSetReference],
        game: CardGame
    ) -> CatalogSetReference? {
        matchingSets(named: importedName, cardName: "", in: directory, game: game).first
    }

    static func matchingSets(
        named importedName: String,
        cardName: String,
        in directory: [CatalogSetReference],
        game: CardGame
    ) -> [CatalogSetReference] {
        let imported = canonicalSetName(importedName, game: game)
        var candidates = [imported]
        if game == .magic, isTokenName(cardName) {
            candidates.insert(imported + " tokens", at: 0)
        }
        return candidates.flatMap { candidate in
            directory.filter { canonicalSetName($0.name, game: game) == candidate }
        }
    }

    /// Japanese-exclusive sets, keyed by the English name marketplaces export
    /// them under, mapped to their TCGdex `ja` set id.
    ///
    /// TCGdex's English edition does not carry these sets at all, so no amount
    /// of name normalization will find them — the mapping has to be stated. Each
    /// entry below was confirmed against the `ja` edition by matching the set's
    /// official card count to the denominator printed on the imported cards.
    ///
    /// These resolve to real cards with artwork and numbering, and to a
    /// Cardmarket price in euros where Cardmarket lists them. They carry no
    /// TCGplayer figure, because these printings are not TCGplayer products.
    static let japaneseSetIDsByImportedName: [String: String] = [
        "inferno x": "M2",                  // インフェルノX, 80 official
        "terastal festival ex": "SV8a",     // テラスタルフェスex, 187 official
        "mega brave": "M1L",                // メガブレイブ, 63 official
        "mega symphonia": "M1S",            // メガシンフォニア, 63 official
        "mega dream ex": "M2a",             // MEGAドリームex, 193 official
        "ruler of the black flame": "SV3",  // 黒炎の支配者, 108 official
        "paradigm trigger": "S12",          // パラダイムトリガー, 98 official
        "night wanderer": "SV6a",           // ナイトワンダラー, 64 official
        "stellar miracle": "SV7",           // ステラミラクル, 102 official
        "wild force": "SV5K",               // ワイルドフォース, 71 official
        "future flash": "SV4M"              // 未来の一閃, 66 official
    ]

    static func japaneseSetID(forImportedName name: String) -> String? {
        japaneseSetIDsByImportedName[canonicalText(name)]
    }

    /// Which edition a resolved catalog id has to be fetched from.
    ///
    /// A card id carries its set id — `M2-001` — and a Japanese-exclusive set is
    /// 404 on the English endpoint. Without this, resolving one of these cards
    /// would trade a set that could not be found for a card that could not be
    /// fetched, and the collection would still report it as unreachable.
    ///
    /// Derived from the same map that routes the lookup, so the two cannot drift
    /// apart as sets are added.
    static func locale(forCatalogCardID id: String) -> TCGdexLocale {
        guard let separator = id.lastIndex(of: "-") else { return .en }
        let setID = String(id[id.startIndex..<separator])
        let isJapanese = japaneseSetIDsByImportedName.values.contains {
            $0.caseInsensitiveCompare(setID) == .orderedSame
        }
        return isJapanese ? .ja : .en
    }

    /// Sets whose Scryfall collector numbers are not the numbers printed on the
    /// card, so identity has to come from the name instead.
    ///
    /// The List reprints cards from across Magic's history and files each under
    /// its original set's code — `MM2-48`, `M15-94` — while every marketplace
    /// export writes the plain number. Matching those by number finds nothing,
    /// every time, which is why 100% of imported List cards went unpriced.
    static func matchesByCardName(setID: String) -> Bool {
        ["plst", "ulst"].contains(setID.lowercased())
    }

    static func canonicalSetName(_ value: String, game: CardGame) -> String {
        var normalized = canonicalText(value)
        if game == .pokemon {
            if normalized.hasPrefix("sv ") { normalized.removeFirst(3) }
            if normalized.hasSuffix(" base set") { normalized.removeLast(9) }
            normalized = normalized.replacingOccurrences(of: " black star promos", with: " promo")
            if normalized.hasSuffix(" promos") { normalized.removeLast() }
            switch normalized {
            case "svp promo": normalized = "scarlet and violet promo"
            case "swsh promo": normalized = "sword and shield promo"
            case "mep promo": normalized = "mega evolution promo"
            case "base set unlimited": normalized = "base set"
            case "mee mega evolution energies": normalized = "mega evolution energy"
            default: break
            }
            if normalized.hasPrefix("ex ") { normalized.removeFirst(3) }
            normalized = normalized.replacingOccurrences(
                of: "mcdonald s promos",
                with: "mcdonald s collection"
            )
        } else {
            normalized = normalized.replacingOccurrences(of: "universes beyond ", with: "")
            if normalized.hasPrefix("magic the gathering ") {
                normalized.removeFirst("magic the gathering ".count)
            }
            if normalized.hasPrefix("commander ") {
                normalized.removeFirst("commander ".count)
                normalized += " commander"
            }
            if normalized.hasPrefix("art series ") {
                normalized.removeFirst("art series ".count)
                normalized += " art series"
            }
            if normalized.hasSuffix(" art series"),
               normalized.hasPrefix("the lord of the rings ") {
                normalized.removeFirst("the lord of the rings ".count)
            }
            normalized = normalized.replacingOccurrences(of: " eternal legal", with: " eternal")
            if normalized == "stellar sights" { normalized = "edge of eternities stellar sights" }
            if normalized == "secret lair drop series" { normalized = "secret lair drop" }
            if normalized == "marvel eternal" { normalized = "marvel s spider man eternal" }
        }
        return normalized.trimmingCharacters(in: .whitespaces)
    }

    static func namesMatch(imported: String, catalog: String) -> Bool {
        let importedName = canonicalCardName(imported)
        let catalogName = canonicalCardName(catalog)
        guard !importedName.isEmpty, !catalogName.isEmpty else { return false }
        return importedName == catalogName
            || importedName.hasPrefix(catalogName + " ")
            || catalogName.hasPrefix(importedName + " ")
            || importedName.contains(" " + catalogName + " ")
            || importedName.hasSuffix(" " + catalogName)
            || catalogName.contains(" " + importedName + " ")
            || catalogName.hasSuffix(" " + importedName)
    }

    private static func canonicalCardName(_ value: String) -> String {
        var normalized = canonicalText(value)
        if let artCard = normalized.range(of: " art card") {
            normalized = String(normalized[..<artCard.lowerBound])
        }
        switch normalized {
        case "buddypoffin", "buddy poffin":
            return "buddy buddy poffin"
        default:
            return normalized
        }
    }

    static func isTokenName(_ value: String) -> Bool {
        let normalized = canonicalText(value)
        return normalized == "helper card"
            || normalized.hasSuffix(" token")
            || normalized.contains(" token ")
    }

    static func canonicalText(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).replacingOccurrences(of: "&", with: " and ")
        let scalars = folded.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
        }
        return String(scalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func localNumber(_ value: String) -> String {
        let beforeTotal = value.split(separator: "/", maxSplits: 1).first.map(String.init) ?? value
        let trimmed = beforeTotal.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(trimmed).map(String.init) ?? trimmed
    }
}
