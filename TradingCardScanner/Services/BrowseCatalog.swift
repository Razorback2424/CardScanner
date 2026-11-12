import Foundation
import SwiftUI
import UIKit
import PokemonCatalogCore
import MagicCatalogCore

enum BrowseCatalogError: LocalizedError {
    case invalidURL
    case badResponse
    case unknownSet
    case providerCountMismatch(setID: String, expected: Int, received: Int?)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Could not build the catalog request."
        case .badResponse: return "The card catalog returned an unexpected response."
        case .unknownSet: return "The card's set could not be identified."
        case let .providerCountMismatch(setID, expected, received):
            let receivedText = received.map(String.init) ?? "no"
            return "The Pokémon set " + setID + " reported " + receivedText
                + " cards; expected " + String(expected) + "."
        }
    }
}

enum BrowseRequestBuilder {
    static func pokemonSearchURL(query: String, page: Int) -> URL? {
        var components = URLComponents(string: "https://api.tcgdex.net/v2/en/cards")
        components?.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "pagination:page", value: String(page)),
            URLQueryItem(name: "pagination:itemsPerPage", value: "60")
        ]
        return components?.url
    }

    static func scryfallSearchURL(query: String) -> URL? {
        var components = URLComponents(string: "https://api.scryfall.com/cards/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "unique", value: "prints"),
            URLQueryItem(name: "include_variations", value: "true"),
            URLQueryItem(name: "order", value: "released"),
            URLQueryItem(name: "dir", value: "desc")
        ]
        return components?.url
    }
}

struct BrowseCatalogUpdate: Sendable, Equatable {
    /// Nil retains the global-update contract used by older catalog providers.
    let game: CardGame?
    let revision: Int?
    let providerSetID: String?

    init(game: CardGame? = nil, revision: Int?, providerSetID: String?) {
        self.game = game; self.revision = revision; self.providerSetID = providerSetID
    }

    func affects(game: CardGame, providerSetID: String? = nil) -> Bool {
        guard self.game == nil || self.game == game else { return false }
        guard let changed = self.providerSetID, let providerSetID else { return true }
        return changed.caseInsensitiveCompare(providerSetID) == .orderedSame
    }
}

enum BrowseCatalogArtworkSelection {
    static func fallbackURLs(
        descriptor: PokemonCatalogSetDescriptor,
        snapshotURLs: [URL]?
    ) -> [URL]? {
        let published = descriptor.artworkFallbackURLs?.compactMap(URL.init(string:))
        return published?.isEmpty == false ? published : snapshotURLs
    }

    static func cardArtworkMap(
        descriptor: PokemonCatalogSetDescriptor
    ) -> [String: CatalogCardArtwork]? {
        var result: [String: CatalogCardArtwork] = [:]
        for artwork in descriptor.cardArtwork ?? [] {
            let key = artwork.localID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !key.isEmpty else { continue }
            result[key] = artwork
        }
        return result.isEmpty ? nil : result
    }
}

actor BrowseCatalog: BrowseCatalogProviding {
    nonisolated let gameRegistry: CardGameRegistry
    private var gameBrowseAdapters: GameBrowseAdapterRegistry
    private let priceQuoteService: PriceQuoteService
    private var priceRetryDetailKeys: Set<String> = []
    private let gameActivationSources: [CardGame: any GameCatalogActivationSource]
    private var gameBrowseTasks: [CardGame: Task<Void, Never>] = [:]
    private var gameBrowseRevisions: [CardGame: Int] = [:]
    private var setArtworkTasks: [CatalogSetID: Task<CatalogSetArtwork, Error>] = [:]
    private var nextSetArtworkRequestAt = Date.distantPast
    private static let legacyReleaseOrderDefaultsKey = "pokemonCatalogReleaseOrder.v1"

    static func applyingSignedCardArtwork(
        _ summaries: [CatalogCardSummary],
        set: CatalogSet
    ) -> [CatalogCardSummary] {
        let augmented = PokemonReviewedEnergyCatalog.addingSummaries(summaries, set: set)
        // Older signed checklists contain generated Normal slots for these
        // reviewed Holofoil products. Correct presentation locally without
        // modifying the signed payload or its provider fingerprint.
        var seenReviewedIDs: Set<String> = []
        let corrected = augmented.compactMap { summary -> CatalogCardSummary? in
            guard summary.game == .pokemon, summary.pokemonPrintRun == nil,
                  PokemonTCGCSVMapping.byCardID[summary.providerID]?.setID == set.providerID else { return summary }
            if let deck = PokemonBattleDeckFinishCatalog.entry(for: summary),
               summary.masterSetVariant?.id == deck.variant.id { return summary }
            guard seenReviewedIDs.insert(summary.providerID).inserted else { return nil }
            var corrected = summary
            corrected.masterSetVariant = .holo
            corrected.isExpandedMasterSetVariant = false
            corrected.isSoleSlotForCard = true
            return corrected
        }
        let summaries = PokemonBattleDeckFinishCatalog.projecting(corrected)
        guard let artwork = set.cardArtwork, !artwork.isEmpty else { return summaries }
        return summaries.map { summary in
            guard summary.thumbnailURL == nil,
                  summary.imageURL == nil,
                  let value = artwork[
                    summary.collectorNumber
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .uppercased()
                  ],
                  let thumbnailURL = URL(string: value.thumbnailURL),
                  let imageURL = URL(string: value.imageURL) else {
                return summary
            }
            return summary.withArtwork(thumbnailURL: thumbnailURL, imageURL: imageURL)
        }
    }

    private struct DetailTaskState {
        let id: UUID
        let task: Task<CatalogCardDetails, Error>
        let ignoresCache: Bool
        var waiterIDs: Set<UUID>
    }

    private struct SortPriceSlot: Sendable {
        let id: String
        let resolution: CatalogSortPriceResolution
    }

    private struct SortPriceGroupResult: Sendable {
        let slots: [SortPriceSlot]
    }

    private struct PokemonBulkSnapshot {
        let value: PokemonBulkPriceMap
        let storedAt: Date

        var isFresh: Bool {
            let age = Date.now.timeIntervalSince(storedAt)
            return age >= 0 && age < 24 * 60 * 60
        }
    }

    private struct MagicCardsPageResult: Sendable {
        let page: CatalogPage<CatalogCardSummary>
        let prices: [String: CatalogCachedPrice]
    }

    private let scryfall: ScryfallService
    private let now: @Sendable () -> Date
    private let magicSession: URLSession
    private let cache: CatalogCacheStore
    private let pokemonTransport: any PokemonBrowseTransport
    private let pokemonPriceSource: (any PokemonBulkPriceSource)?
    private let tcgCSVSource: (any PokemonTCGCSVPriceSource)?
    private let pokemonDeckPrices: PokemonMarketPriceResolver?
    private var tcgCSVRetrySetIDs: Set<String> = []
    private let pokemonSecondarySetSource: (any PokemonSecondarySetSource)?
    private let checklistStore: PokemonChecklistStore
    private var setCache: [CardGame: [CatalogSet]] = [:]
    private var liveMagicDirectoryStoredAt: Date?
    private var detailCache: [String: CatalogCardDetails] = [:]
    private var detailTasks: [String: DetailTaskState] = [:]
    private var magicPageTasks: [String: Task<CatalogPage<CatalogCardSummary>, Error>] = [:]
    private var pokemonSetDetails: [String: TCGdexSetCatalog] = [:]
    private var pokemonSetTasks: [String: Task<TCGdexSetCatalog, Error>] = [:]
    private struct PokemonPayloadTaskState {
        let id: UUID
        let task: Task<TCGdexCard, Error>
        let ignoresCache: Bool
        var waiters: Set<UUID>
    }
    private var pokemonDetailPayloadTasks: [String: PokemonPayloadTaskState] = [:]
    private var pokemonSetCardDetails: [String: (cards: [String: TCGdexCard], retrievedAt: [String: Date])] = [:]
    private var pokemonSnapshotEntries: [PokemonChecklistSnapshotEntry] = []
    private var pokemonBundledRanks: [String: Int] = [:]
    private var pokemonSnapshotLoaded = false
    private var pokemonSnapshotGeneration = 0
    /// The read is shared across re-entrant actor calls. It is intentionally
    /// unstructured: cancelling one Browse caller must not cancel the snapshot
    /// load that another caller may still need.
    private var pokemonSnapshotLoadTask: Task<[PokemonChecklistSnapshotEntry], Never>?
    private var refreshTask: Task<Void, Never>?
    private var reconciliationTask: Task<Void, Never>?
    private var catalogAuthorityRefreshTask: Task<Void, Never>?
    private var magicCatalogAuthorityRefreshTask: Task<Void, Never>?
    private var refreshToken = UUID()
    private var catalogEventTask: Task<Void, Never>?
    private var magicCatalogEventTask: Task<Void, Never>?
    private var catalogRegistry = PokemonCatalogRegistry.bundledSeed
    private var catalogRevision: Int?
    private var magicCatalogRegistry = MagicCatalogRegistry.bundledSeed
    private var magicCatalogRevision: Int?
    private var updateContinuations: [UUID: AsyncStream<BrowseCatalogUpdate>.Continuation] = [:]
    /// `prepareCatalog` suspends before it can install `refreshTask`. This flag
    /// closes that actor-reentrancy window; the desired-state bit lets an
    /// active → inactive → active transition keep one pending preparation alive
    /// without starting a second crawl.
    private var isPreparingCatalog = false
    private var wantsCatalogRefresh = false
    private var sortPriceCache: [String: Double] = [:]
    private var resolvedSortPrices: Set<String> = []
    private var unresolvedSortPrices: Set<String> = []
    private var missingMappingSortPrices: Set<String> = []
    private var sortPriceResolutionGeneration = UUID()
    private var sortPriceCheckedAt: [String: Date] = [:]
    private var pokemonBulkPriceCache: [String: PokemonBulkSnapshot] = [:]
    private var refreshingSetDirectories: Set<CardGame> = []
    private var memoryWarningObserver: NSObjectProtocol?

    private let catalogCoordinator: PokemonCatalogCoordinator?
    private let magicCatalogCoordinator: MagicCatalogCoordinator?

    init(
        cache: CatalogCacheStore = .shared,
        pokemonTransport: any PokemonBrowseTransport = TCGdexBrowseTransport(),
        pokemonPriceSource: (any PokemonBulkPriceSource)? = nil,
        tcgCSVSource: (any PokemonTCGCSVPriceSource)? = nil,
        pokemonProductPriceSource: TCGCSVProductPriceSource? = nil,
        pokemonSecondarySetSource: (any PokemonSecondarySetSource)? = nil,
        checklistStore: PokemonChecklistStore = .shared,
        catalogCoordinator: PokemonCatalogCoordinator? = nil,
        magicCatalogCoordinator: MagicCatalogCoordinator? = nil,
        gameRegistry: CardGameRegistry = .standard,
        gameBrowseAdapters: GameBrowseAdapterRegistry = try! .init(adapters: []),
        priceQuoteService: PriceQuoteService = PriceQuoteService(),
        gameActivationSources: [any GameCatalogActivationSource] = [],
        magicSession: URLSession = .shared,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        // The old crawl-installed ordering map was unsigned and had no rollback
        // semantics. Remove it once on construction so upgrades cannot leave a
        // second ordering authority behind in UserDefaults.
        UserDefaults.standard.removeObject(forKey: Self.legacyReleaseOrderDefaultsKey)
        self.cache = cache
        self.gameRegistry = gameRegistry
        self.gameBrowseAdapters = gameBrowseAdapters
        self.priceQuoteService = priceQuoteService
        self.gameActivationSources = Dictionary(gameActivationSources.map { ($0.game, $0) },
                                               uniquingKeysWith: { first, _ in first })
        self.pokemonTransport = pokemonTransport
        // Recorded Browse transports should remain completely offline in tests
        // and previews. The production transport opts into the live bulk
        // source by default; custom callers can inject their own source.
        let effectivePriceSource = pokemonPriceSource
            ?? (pokemonTransport is TCGdexBrowseTransport ? PokemonTCGAPIService() : nil)
        self.pokemonPriceSource = effectivePriceSource
        self.tcgCSVSource = tcgCSVSource
            ?? (pokemonTransport is TCGdexBrowseTransport ? PokemonTCGCSVPriceService.shared : nil)
        self.pokemonDeckPrices = (pokemonProductPriceSource
            ?? (pokemonTransport is TCGdexBrowseTransport ? TCGCSVProductPriceSource.shared : nil))
            .map { PokemonMarketPriceResolver(productSource: $0) }
        self.pokemonSecondarySetSource = pokemonSecondarySetSource
            ?? (effectivePriceSource as? any PokemonSecondarySetSource)
        self.checklistStore = checklistStore
        self.catalogCoordinator = catalogCoordinator
        self.magicCatalogCoordinator = magicCatalogCoordinator
        self.magicSession = magicSession
        self.scryfall = ScryfallService(session: magicSession)
        self.now = now
    }

    deinit {
        for task in gameBrowseTasks.values { task.cancel() }
        for task in magicPageTasks.values { task.cancel() }
        catalogEventTask?.cancel()
        catalogAuthorityRefreshTask?.cancel()
        reconciliationTask?.cancel()
        magicCatalogEventTask?.cancel()
        magicCatalogAuthorityRefreshTask?.cancel()
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    func sets(for game: CardGame) async throws -> [CatalogSet] {
        await synchronizeGameBrowseAuthority(for: game)
        if let adapter = gameBrowseAdapters.adapter(for: game) {
            let sets = try await adapter.sets()
            try validateBrowseGeneration(adapter)
            return sets
        }
        installMemoryWarningObserverIfNeeded()
        if game == .pokemon {
            await synchronizeCatalogAuthority()
        }
        if game == .magic {
            await synchronizeMagicCatalogAuthority()
            if await usesRemoteMagicAuthority() {
                let sets = magicCatalogRegistry.browseSets
                setCache[game] = sets
                return sets
            }
        }
        if let cached = setCache[game] {
            if game == .magic {
                let age = now().timeIntervalSince(liveMagicDirectoryStoredAt ?? .distantPast)
                if age < 0 || age >= CatalogCacheStore.setDirectoryMaxAge {
                    scheduleSetDirectoryRefresh(for: game)
                }
            }
            return cached
        }

        if game == .pokemon {
            await loadPokemonSnapshotIfNeeded()
            if !pokemonSnapshotEntries.isEmpty {
                let sets = pokemonSets(from: pokemonSnapshotEntries)
                setCache[game] = sets
                return sets
            }
            // In production the signed registry and a verified checklist are
            // the only set-activation authorities. A raw directory (or an old
            // disposable page cache) must not make an unauthorized/pending set
            // look active. The legacy no-coordinator path remains for isolated
            // Browse transport tests and development fixtures.
            if catalogCoordinator != nil { return [] }
        }

        if let saved = await cache.sets(for: game, now: now()) {
            setCache[game] = saved.value
            if game == .magic { liveMagicDirectoryStoredAt = saved.isFresh ? saved.storedAt : nil }
            if !saved.isFresh { scheduleSetDirectoryRefresh(for: game) }
            return saved.value
        }
        return try await loadSetDirectory(for: game)
    }

    func invalidateSetCache(for game: CardGame) {
        guard game == .pokemon else {
            setCache[game] = nil
            if game == .magic { liveMagicDirectoryStoredAt = nil }
            if game == .magic, magicCatalogCoordinator != nil {
                Task { [cache] in await cache.removeSets(for: .magic) }
            }
            yieldUpdate(game: game, revision: nil, providerSetID: nil)
            return
        }
        resetPokemonSnapshotCache()
        yieldUpdate(game: .pokemon, revision: catalogRevision, providerSetID: nil)
    }

    func activeCatalogRevision() -> Int? {
        catalogRevision
    }

    func catalogUpdates() async -> AsyncStream<BrowseCatalogUpdate> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: BrowseCatalogUpdate.self)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeUpdateContinuation(id: id) }
        }
        updateContinuations[id] = continuation
        return stream
    }

    /// Starts the active-session refresh without making Browse wait for it.
    /// The snapshot is loaded synchronously first so the first Browse render
    /// can use local data, while the network work remains low priority.
    func prepareCatalog() async {
        installMemoryWarningObserverIfNeeded()
        wantsCatalogRefresh = true
        guard !isPreparingCatalog else { return }
        isPreparingCatalog = true
        defer { isPreparingCatalog = false }

        if let coordinator = catalogCoordinator {
            await startCatalogEventListenerIfNeeded(coordinator)
            await coordinator.loadPersistedOrBundled()
            await synchronizeCatalogAuthority()
        }

        if let magicCoordinator = magicCatalogCoordinator {
            await startMagicCatalogEventListenerIfNeeded(magicCoordinator)
            await magicCoordinator.loadPersistedOrBundled()
            await synchronizeMagicCatalogAuthority()
        }

        await loadPokemonSnapshotIfNeeded()
        if let coordinator = catalogCoordinator {
            startCatalogAuthorityRefreshIfNeeded(coordinator)
        }
        await startTargetedReconciliationIfNeeded()
        if let magicCoordinator = magicCatalogCoordinator {
            startMagicCatalogAuthorityRefreshIfNeeded(magicCoordinator)
        }
        if let existingTask = refreshTask {
            // Suspension cancels cooperatively. Keep the task reference until
            // it has unwound so an immediate inactive → active transition
            // cannot start a second crawl over the first one's writes.
            guard existingTask.isCancelled else { return }
            await existingTask.value
            refreshTask = nil
        }
        guard wantsCatalogRefresh else { return }
        guard await checklistStore.shouldRefresh() else { return }
        guard wantsCatalogRefresh else { return }
        let token = UUID()
        refreshToken = token
        refreshTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.refreshPokemonSnapshot()
            await self.finishRefreshTask(token: token)
        }
    }

    /// Test/support entry point for awaiting the same atomic operation that the
    /// active-session task runs. A failed refresh intentionally has no throw:
    /// the last complete snapshot remains the usable result.
    func refreshCatalogNow() async {
        await synchronizeCatalogAuthority()
        await synchronizeMagicCatalogAuthority()
        await loadPokemonSnapshotIfNeeded()
        await reconcilePokemonProviderContent()
        await refreshPokemonSnapshot()
    }

    func suspendCatalogRefresh() {
        wantsCatalogRefresh = false
        refreshToken = UUID()
        refreshTask?.cancel()
        reconciliationTask?.cancel()
    }

    private func finishRefreshTask(token: UUID) {
        guard refreshToken == token else { return }
        refreshTask = nil
    }

    private func loadSetDirectory(for game: CardGame) async throws -> [CatalogSet] {
        let loaded: [CatalogSet]
        switch game {
        case .pokemon: loaded = try await pokemonSets()
        case .magic: loaded = try await magicSets()
        default: throw CardGameSupportError.unsupportedGame(game)
        }
        if game == .magic, await usesRemoteMagicAuthority() {
            return magicCatalogRegistry.browseSets
        }
        let previous = setCache[game]
        let storedAt = now()
        setCache[game] = loaded
        if game == .magic { liveMagicDirectoryStoredAt = storedAt }
        await cache.storeSets(loaded, for: game, at: storedAt)
        if game == .magic, await usesRemoteMagicAuthority() {
            return magicCatalogRegistry.browseSets
        }
        if let previous, previous != loaded { yieldUpdate(game: game, revision: nil, providerSetID: nil) }
        return loaded
    }

    private func scheduleSetDirectoryRefresh(for game: CardGame) {
        guard refreshingSetDirectories.insert(game).inserted else { return }
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.loadSetDirectory(for: game)
            await self.finishSetDirectoryRefresh(for: game)
        }
    }

    private func finishSetDirectoryRefresh(for game: CardGame) {
        refreshingSetDirectories.remove(game)
    }

    private func startCatalogEventListenerIfNeeded(
        _ coordinator: PokemonCatalogCoordinator
    ) async {
        guard catalogEventTask == nil else { return }
        let events = await coordinator.activationEvents()
        catalogEventTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                await self?.applyCatalogRegistry(event.registry, revision: event.revision)
                await self?.startTargetedReconciliationIfNeeded()
            }
        }
    }

    private func startMagicCatalogEventListenerIfNeeded(
        _ coordinator: MagicCatalogCoordinator
    ) async {
        guard magicCatalogEventTask == nil else { return }
        let events = await coordinator.activationEvents()
        magicCatalogEventTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                await self?.applyMagicCatalogRegistry(event.registry, revision: event.revision)
            }
        }
    }

    /// Refresh the signed authority only after the local snapshot has had a
    /// chance to populate the first Browse render. The coordinator owns its
    /// own retry/backoff policy, so this task is intentionally independent of
    /// the view's initial preparation await.
    private func startCatalogAuthorityRefreshIfNeeded(
        _ coordinator: PokemonCatalogCoordinator
    ) {
        guard catalogAuthorityRefreshTask == nil else { return }
        catalogAuthorityRefreshTask = Task(priority: .utility) { [weak self, coordinator] in
            _ = await coordinator.refreshAutomatically()
            guard !Task.isCancelled else { return }
            await self?.finishCatalogAuthorityRefresh()
        }
    }

    private func finishCatalogAuthorityRefresh() {
        catalogAuthorityRefreshTask = nil
    }

    private func startMagicCatalogAuthorityRefreshIfNeeded(
        _ coordinator: MagicCatalogCoordinator
    ) {
        guard magicCatalogAuthorityRefreshTask == nil else { return }
        magicCatalogAuthorityRefreshTask = Task(priority: .utility) { [weak self, coordinator] in
            _ = await coordinator.refresh()
            guard !Task.isCancelled else { return }
            await self?.finishMagicCatalogAuthorityRefresh()
        }
    }

    private func finishMagicCatalogAuthorityRefresh() {
        magicCatalogAuthorityRefreshTask = nil
    }

    private func synchronizeCatalogAuthority() async {
        guard let coordinator = catalogCoordinator else { return }
        await coordinator.loadPersistedOrBundled()
        let active = await coordinator.activeCatalog
        applyCatalogRegistry(active.registry, revision: active.revision)
    }

    private func usesRemoteMagicAuthority() async -> Bool {
        guard let coordinator = magicCatalogCoordinator else { return false }
        return await coordinator.currentRolloutMode == .remoteAuthority
    }

    private func synchronizeMagicCatalogAuthority() async {
        guard let coordinator = magicCatalogCoordinator else { return }
        await coordinator.loadPersistedOrBundled()
        let nextRegistry = await coordinator.registry
        let nextRevision = await coordinator.revision
        applyMagicCatalogRegistry(nextRegistry, revision: nextRevision)
    }

    private func applyCatalogRegistry(
        _ registry: PokemonCatalogRegistry,
        revision: Int?
    ) {
        if let catalogRevision, (revision ?? 0) < catalogRevision { return }
        guard catalogRevision != revision
            || catalogRegistry.descriptors != registry.descriptors else { return }
        catalogRegistry = registry
        catalogRevision = revision
        resetPokemonSnapshotCache()
        yieldUpdate(game: .pokemon, revision: revision, providerSetID: nil)
    }

    private func startTargetedReconciliationIfNeeded() async {
        guard wantsCatalogRefresh else { return }
        let desired = await pendingProviderFingerprints()
        let targets = await checklistStore.synchronizeReconciliationTargets(
            desiredFingerprints: desired
        )
        if let existingTask = reconciliationTask {
            guard existingTask.isCancelled else { return }
            await existingTask.value
            reconciliationTask = nil
        }
        guard !targets.isEmpty else { return }

        reconciliationTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.reconcilePokemonProviderContent()
            await self.finishReconciliationTask()
        }
    }

    private func finishReconciliationTask() {
        guard reconciliationTask != nil else { return }
        reconciliationTask = nil
    }

    private func signedProviderFingerprints() -> [String: String] {
        Dictionary(
            catalogRegistry.descriptors.compactMap { descriptor in
                guard let fingerprint = descriptor.providerFingerprint else { return nil }
                return (descriptor.providerSetID.lowercased(), fingerprint)
            },
            uniquingKeysWith: { _, newest in newest }
        )
    }

    private func pendingProviderFingerprints() async -> [String: String] {
        let installed = await checklistStore.signedProviderFingerprints()
        return signedProviderFingerprints().filter { installed[$0.key] != $0.value }
    }

    /// Reconciliation is state-derived and may be called from either the
    /// foreground preparation path or the activation-event fast path. The
    /// durable queue is re-derived first so lost in-memory events self-heal.
    private func reconcilePokemonProviderContent() async {
        guard !Task.isCancelled else { return }
        let desired = await pendingProviderFingerprints()
        guard !desired.isEmpty else { return }
        _ = await checklistStore.synchronizeReconciliationTargets(
            desiredFingerprints: desired
        )

        while !Task.isCancelled {
            guard let target = await checklistStore.dueReconciliationTargets().first else {
                return
            }
            await reconcile(target)
        }
    }

    private func reconcile(_ target: PokemonChecklistReconciliationTarget) async {
        do {
            // Do not let a prior Browse read vouch for a newly signed target.
            pokemonSetDetails.removeValue(forKey: target.providerSetID.lowercased())
            pokemonSetCardDetails = pokemonSetCardDetails.filter {
                !$0.key.hasPrefix(target.providerSetID.lowercased() + "|")
            }
            let provider = try await pokemonSet(id: target.providerSetID)
            let baseSet = try reconciliationBaseSet(
                provider: provider,
                providerSetID: target.providerSetID
            )
            let details = try await pokemonCardDetails(for: provider)
            let built = try PokemonMasterSetChecklistBuilder.build(
                providerSet: provider,
                baseSet: baseSet,
                cardDetails: details.cards
            )
            guard !built.isEmpty,
                  built.allSatisfy({ $0.providerFingerprint == target.desiredFingerprint }) else {
                await checklistStore.markReconciliationFailure(
                    providerSetID: target.providerSetID,
                    desiredFingerprint: target.desiredFingerprint
                )
                return
            }

            let snapshot = PokemonChecklistSnapshot.from(builtSets: built)
            try await checklistStore.publish(snapshot)
            guard !Task.isCancelled else { return }
            let entries = await checklistStore.mergedEntries()
            let visibleEntries = await visibleSnapshotEntries(entries)
            pokemonSnapshotEntries = visibleEntries
            pokemonSnapshotLoaded = !visibleEntries.isEmpty
            setCache[.pokemon] = pokemonSets(from: visibleEntries)
            await checklistStore.markReconciliationSucceeded(
                providerSetID: target.providerSetID,
                desiredFingerprint: target.desiredFingerprint
            )
            yieldUpdate(game: .pokemon, revision: catalogRevision, providerSetID: target.providerSetID)
        } catch is CancellationError {
            return
        } catch {
            await checklistStore.markReconciliationFailure(
                providerSetID: target.providerSetID,
                desiredFingerprint: target.desiredFingerprint
            )
        }
    }

    private func reconciliationBaseSet(
        provider: TCGdexSetCatalog,
        providerSetID: String
    ) throws -> CatalogSet {
        if let existing = pokemonSnapshotEntries.first(where: {
            $0.providerID.caseInsensitiveCompare(providerSetID) == .orderedSame
                && $0.set.pokemonPrintRun == nil
        }) {
            return existing.set
        }
        guard let descriptor = catalogRegistry.descriptor(forProviderSetID: providerSetID) else {
            throw BrowseCatalogError.unknownSet
        }
        return PokemonMasterSetChecklistBuilder.signedBaseSet(provider: provider, descriptor: descriptor)
    }

    private func applyMagicCatalogRegistry(
        _ registry: MagicCatalogRegistry,
        revision: Int?
    ) {
        guard magicCatalogRevision != revision
            || magicCatalogRegistry.descriptors != registry.descriptors else { return }
        magicCatalogRegistry = registry
        magicCatalogRevision = revision
        setCache[.magic] = nil
        liveMagicDirectoryStoredAt = nil
        if magicCatalogCoordinator != nil {
            Task { [weak self, cache] in
                guard let self else { return }
                if await self.usesRemoteMagicAuthority() {
                    await cache.removeSets(for: .magic)
                }
            }
        }
        yieldUpdate(game: .magic, revision: revision, providerSetID: nil)
    }

    private func resetPokemonSnapshotCache() {
        pokemonSnapshotGeneration &+= 1
        setCache[.pokemon] = nil
        pokemonSnapshotLoaded = false
        pokemonSnapshotEntries = []
        pokemonSnapshotLoadTask?.cancel()
        pokemonSnapshotLoadTask = nil
        pokemonSetDetails.removeAll()
        pokemonSetCardDetails.removeAll()
        detailCache.removeAll()
    }

    private func removeUpdateContinuation(id: UUID) {
        updateContinuations.removeValue(forKey: id)
    }

    private func yieldUpdate(game: CardGame, revision: Int?, providerSetID: String?) {
        let update = BrowseCatalogUpdate(
            game: game,
            revision: revision,
            providerSetID: providerSetID
        )
        for continuation in updateContinuations.values {
            continuation.yield(update)
        }
    }

    private func visibleSnapshotEntries(
        _ entries: [PokemonChecklistSnapshotEntry]
    ) async -> [PokemonChecklistSnapshotEntry] {
        guard catalogCoordinator != nil else { return entries }
        let bundled = await checklistStore.bundledProviderIDs()
        return entries.filter {
            catalogRegistry.descriptor(forProviderSetID: $0.providerID) != nil || bundled.contains($0.providerID.lowercased())
        }
    }

    private func pokemonSetIsAuthorized(_ providerID: String) async -> Bool {
        if catalogCoordinator == nil || catalogRegistry.descriptor(forProviderSetID: providerID) != nil { return true }
        return await checklistStore.bundledProviderIDs().contains(providerID.lowercased())
    }

    private func pokemonSets(
        from entries: [PokemonChecklistSnapshotEntry]
    ) -> [CatalogSet] {
        let hasCompleteSignedOrder = entries.allSatisfy {
            catalogRegistry.releaseOrder(forProviderSetID: $0.providerID) != nil
        }
        return entries.map { entry in
            guard let descriptor = catalogRegistry.descriptor(forProviderSetID: entry.providerID) else {
                return entry.set.withSortRank(pokemonBundledRanks[entry.set.id] ?? entry.set.sortRank)
            }

            let baseName = descriptor.displayName ?? entry.set.name
            let displayName: String
            if let printRun = entry.set.pokemonPrintRun {
                displayName = baseName + " — " + printRun.label
            } else {
                displayName = baseName
            }

            let code = catalogRegistry.printedCode(forProviderSetID: entry.providerID)
                ?? (descriptor.recognitionKind == .notScannable ? "Not scannable" : "Code pending")
            return CatalogSet(
                catalogID: entry.set.catalogID,
                name: displayName,
                code: code,
                logoURL: descriptor.logoURL.flatMap(URL.init(string:)) ?? entry.set.logoURL,
                symbolURL: descriptor.symbolURL.flatMap(URL.init(string:)) ?? entry.set.symbolURL,
                cardCount: entry.set.cardCount,
                releaseDate: descriptor.releaseDate.flatMap(FlexibleDate.parse)
                    ?? entry.set.releaseDate,
                sortRank: hasCompleteSignedOrder ? descriptor.releaseOrder ?? entry.set.sortRank
                    : pokemonBundledRanks[entry.set.id] ?? entry.set.sortRank,
                bundledArtworkSourceID: descriptor.bundledArtworkSourceID
                    ?? entry.set.bundledArtworkSourceID,
                artworkFallbackURLs: BrowseCatalogArtworkSelection.fallbackURLs(
                    descriptor: descriptor,
                    snapshotURLs: entry.set.artworkFallbackURLs
                ),
                limitlessArtworkAuthorized: descriptor.recognitionKind == .expansion,
                cardArtwork: BrowseCatalogArtworkSelection.cardArtworkMap(descriptor: descriptor)
            )
        }
    }

    func artwork(for set: CatalogSet) async throws -> CatalogSetArtwork {
        if let hints = set.artworkFallbackURLs, !hints.isEmpty {
            return .init(cardURLs: hints, illustrationURLs: hints)
        }
        guard set.game == .magic else { return .init(cardURLs: [], illustrationURLs: []) }
        if let task = setArtworkTasks[set.catalogID] { return try await task.value }
        // One shared request per visible set. Cache the small URL list separately
        // from card pages so artwork never starts pricing/history work.
        let task = Task { try await self.loadMagicSetArtwork(for: set) }
        setArtworkTasks[set.catalogID] = task
        defer { setArtworkTasks[set.catalogID] = nil }
        return try await task.value
    }

    private func loadMagicSetArtwork(for set: CatalogSet) async throws -> CatalogSetArtwork {
        if let saved = await cache.setArtwork(for: set.catalogID), saved.isFresh {
            return saved.value
        }
        let key = CatalogCacheStore.cardPageKey(for: set, cursor: nil)
        if let page = await cache.cardPage(for: key) {
            let urls = CatalogSetArtworkSelection.urls(from: page.value.items)
            if !urls.isEmpty {
                let artwork = CatalogSetArtwork(cardURLs: urls, illustrationURLs: urls)
                await cache.storeSetArtwork(artwork, for: set.catalogID)
                return artwork
            }
        }
        do {
            guard let url = BrowseRequestBuilder.scryfallSearchURL(
                query: "e:\(set.providerID) lang:en game:paper"
            ) else { throw BrowseCatalogError.invalidURL }
            // Scrolling a lazy grid can expose several sets together. Space
            // artwork searches instead of sending a burst to the provider.
            let delay = max(nextSetArtworkRequestAt.timeIntervalSinceNow, 0)
            nextSetArtworkRequestAt = Date.now.addingTimeInterval(delay + 0.1)
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
            let (data, response) = try await magicSession.data(for: request(url, scryfall: true))
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                let artwork = CatalogSetArtwork(cardURLs: [], illustrationURLs: [])
                await cache.storeSetArtwork(artwork, for: set.catalogID)
                return artwork
            }
            try validate(response)
            let page = try JSONDecoder().decode(ScryfallBrowseCardPage.self, from: data)
            let members = page.data.filter { $0.setCode.caseInsensitiveCompare(set.providerID) == .orderedSame }
            var seen: Set<URL> = []
            let illustrations = Array(members
                .compactMap { $0.imageURIs?.artCrop ?? $0.cardFaces?.first?.imageURIs?.artCrop
                    ?? $0.displayImageURL ?? $0.thumbnailImageURL }
                .filter { seen.insert($0).inserted }.prefix(3))
            seen.removeAll()
            let cards = Array(members.compactMap { $0.displayImageURL ?? $0.thumbnailImageURL }
                .filter { seen.insert($0).inserted }.prefix(3))
            let artwork = CatalogSetArtwork(cardURLs: cards, illustrationURLs: illustrations)
            await cache.storeSetArtwork(artwork, for: set.catalogID)
            return artwork
        } catch {
            // Previously resolved art remains useful offline, even when stale.
            if let saved = await cache.setArtwork(for: set.catalogID) { return saved.value }
            throw error
        }
    }

    func completeLocalCards(in set: CatalogSet) async throws -> [CatalogCardSummary]? {
        await synchronizeGameBrowseAuthority(for: set.game)
        guard let adapter = gameBrowseAdapters.adapter(for: set.game) else { return nil }
        let cards = try await adapter.completeLocalCards(in: set)
        try validateBrowseGeneration(adapter)
        return cards
    }

    func cards(in set: CatalogSet, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        await synchronizeGameBrowseAuthority(for: set.game)
        if let adapter = gameBrowseAdapters.adapter(for: set.game) {
            let page = try await adapter.cards(in: set, cursor: cursor)
            try validateBrowseGeneration(adapter)
            return page
        }
        installMemoryWarningObserverIfNeeded()
        if set.game == .pokemon {
            await synchronizeCatalogAuthority()
        }
        switch set.game {
        case .pokemon:
            await loadPokemonSnapshotIfNeeded()
            guard await pokemonSetIsAuthorized(set.providerID) else { throw BrowseCatalogError.unknownSet }
            // Snapshot lookup deliberately precedes the ordinary page cache.
            // A bundled or protected checklist is the authoritative offline
            // source and must not be displaced by an older partial page.
            if let local = await checklistStore.mergedChecklist(for: set.catalogID) {
                return CatalogPage(
                    items: Self.applyingSignedCardArtwork(
                        PokemonChecklistReviewedProjection.addingAdditionalVariants(to: local, registry: catalogRegistry), set: set),
                    nextCursor: nil
                )
            }
            return CatalogPage(items: try await livePokemonSummaries(for: set), nextCursor: nil)
        case .magic:
            let cacheKey = CatalogCacheStore.cardPageKey(for: set, cursor: cursor)
            if let saved = await cache.cardPage(for: cacheKey) {
                let savedPrices = await cache.magicPrices(for: cacheKey)
                installMagicPrices(
                    savedPrices?.value,
                    for: saved.value.items, asOf: savedPrices?.storedAt ?? .distantPast
                )
                // A pre-Stage-2 page can still be fresh while having no
                // sibling price map. Refresh once so the new durable pricing
                // path is populated immediately after an app upgrade.
                let hasHistoryMetadata = savedPrices?.value.values.allSatisfy {
                    $0.historyMetadataVersion >= CatalogCachedPrice.currentHistoryMetadataVersion
                } == true
                if !saved.isFresh || savedPrices?.isFresh != true || !hasHistoryMetadata {
                    _ = startMagicPageLoad(set: set, cursor: cursor, cacheKey: cacheKey, publishUpdate: true)
                }
                return saved.value
            }
            do {
                let page = try await startMagicPageLoad(
                    set: set, cursor: cursor, cacheKey: cacheKey, publishUpdate: false
                ).value
                try Task.checkCancellation()
                return page
            } catch {
                try Task.checkCancellation()
                guard cursor == nil else { throw error }
                let legacyKey = CatalogCacheStore.legacyMagicInitialPageKey(for: set)
                guard let saved = await cache.cardPage(for: legacyKey) else { throw error }
                let savedPrices = await cache.magicPrices(for: legacyKey)
                installMagicPrices(
                    savedPrices?.value,
                    for: saved.value.items, asOf: savedPrices?.storedAt ?? .distantPast
                )
                // The legacy first page is still usable offline. Its cursor
                // belongs to the older query that omitted provider variations.
                return .init(items: saved.value.items, nextCursor: nil)
            }
        default: throw CardGameSupportError.unsupportedGame(set.game)
        }
    }

    private func startMagicPageLoad(
        set: CatalogSet, cursor: String?, cacheKey: String, publishUpdate: Bool
    ) -> Task<CatalogPage<CatalogCardSummary>, Error> {
        if let pending = magicPageTasks[cacheKey] { return pending }
        let task = Task { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.loadMagicPage(
                set: set, cursor: cursor, cacheKey: cacheKey, publishUpdate: publishUpdate
            )
        }
        magicPageTasks[cacheKey] = task
        return task
    }

    private func loadMagicPage(
        set: CatalogSet, cursor: String?, cacheKey: String, publishUpdate: Bool
    ) async throws -> CatalogPage<CatalogCardSummary> {
        defer { magicPageTasks[cacheKey] = nil }
        let loaded = try await magicCards(
            query: "e:\(set.providerID) lang:en game:paper", cursor: cursor
        )
        try Task.checkCancellation()
        await cache.storeMagicPrices(loaded.prices, for: cacheKey)
        await cache.storeCardPage(loaded.page, for: cacheKey)
        installMagicPrices(loaded.prices, for: loaded.page.items)
        if publishUpdate {
            yieldUpdate(game: .magic, revision: magicCatalogRevision, providerSetID: set.providerID)
        }
        return loaded.page
    }

    func searchCards(
        named query: String,
        game: CardGame,
        setIDs: Set<CatalogSetID>,
        cursor: String?
    ) async throws -> CatalogPage<CatalogCardSummary> {
        installMemoryWarningObserverIfNeeded()
        let providerQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = CardNameSearch.normalize(providerQuery)
        guard CatalogCardSearchQuery.isEligible(normalized, for: game) else {
            return CatalogPage(items: [], nextCursor: nil)
        }

        await synchronizeGameBrowseAuthority(for: game)
        if let adapter = gameBrowseAdapters.adapter(for: game) {
            let page = try await adapter.search(query: providerQuery, setIDs: setIDs, cursor: cursor)
            try validateBrowseGeneration(adapter)
            return page
        }

        switch game {
        case .pokemon:
            let selected = setIDs.filter { $0.game == .pokemon }
            let directory = try await sets(for: .pokemon)
            if pokemonSnapshotEntries.isEmpty, catalogCoordinator == nil, selected.isEmpty, normalized.count >= 2 {
                return try await searchPokemon(query: providerQuery, cursor: cursor)
            }
            let sets = CatalogSetOrdering.newestFirst(directory.filter { selected.isEmpty || selected.contains($0.catalogID) })
            let offset = max(0, Int(cursor ?? "") ?? 0)
            let revision = catalogRevision
            let page = try await checklistStore.search(normalized, sets: sets, offset: offset, limit: 60)
            try Task.checkCancellation()
            guard revision == catalogRevision else { throw CatalogLookupError.staleCatalog }
            let setsByID = Dictionary(sets.map { ($0.catalogID, $0) }, uniquingKeysWith: { first, _ in first })
            let items = page.items.compactMap { summary -> CatalogCardSummary? in
                guard let set = setsByID[summary.setID] else { return nil }
                var identity = Self.applyingSignedCardArtwork([summary], set: set).first ?? summary
                identity.masterSetVariant = nil
                return identity
            }
            return .init(items: items, nextCursor: page.nextCursor)

        case .magic:
            let selected = setIDs.filter { $0.game == .magic }.map(\.providerID).sorted()
            let setClause = selected.isEmpty
                ? ""
                : " (\(selected.map { "e:\($0)" }.joined(separator: " or ")))"
            return try await magicCards(
                query: "name:\"\(escapedScryfall(providerQuery))\" lang:en game:paper\(setClause)",
                cursor: cursor
            ).page
        default: throw CardGameSupportError.unsupportedGame(game)
        }
    }

    func details(for summary: CatalogCardSummary) async throws -> CatalogCardDetails {
        try await details(for: summary, refreshingPrices: false)
    }

    func installedDetails(for summary: CatalogCardSummary) async -> CatalogCardDetails? {
        guard summary.game == .pokemon else { return nil }
        await synchronizeCatalogAuthority()
        await loadPokemonSnapshotIfNeeded()
        guard await pokemonSetIsAuthorized(summary.setID.providerID) else { return nil }
        let registry = catalogRegistry
        let fingerprint = registry.descriptor(forProviderSetID: summary.setID.providerID)?.providerFingerprint
        guard let local = try? await checklistStore.loadedChecklist(for: summary.setID, registry: registry),
              let card = PokemonOfflineCardFactory.card(in: local, providerCardID: summary.providerID),
              !Task.isCancelled, registry.revision == catalogRegistry.revision,
              registry.descriptors == catalogRegistry.descriptors else { return nil }
        let set = pokemonSets(from: [local.entry])[0]
        let provisional = fingerprint != nil && local.entry.providerFingerprint != fingerprint
        return .init(card: .pokemon(card.applyingAdditionalVariants(from: registry), setCode: set.code), set: set,
            retrievedAt: local.entry.set.releaseDate ?? .distantPast,
            collectionWriteUnavailableReason: provisional ? "This printing is waiting for a catalog update." : nil)
    }

    func details(for summary: CatalogCardSummary, refreshingPrices: Bool) async throws -> CatalogCardDetails {
        await synchronizeGameBrowseAuthority(for: summary.game)
        if summary.game == .pokemon {
            await synchronizeCatalogAuthority()
            _ = try await authorizedPokemonDetailSet(for: summary)
        }
        if let adapter = gameBrowseAdapters.adapter(for: summary.game),
           summary.catalogGeneration != adapter.generation { throw CatalogLookupError.staleCatalog }
        installMemoryWarningObserverIfNeeded()
        let key = detailCacheKey(for: summary)
        let stale = detailCache[key]
        if !refreshingPrices, let cached = stale, Self.detailsAreFresh(cached, now: now()) {
            try Task.checkCancellation()
            return cached
        }

        let waiterID = UUID()
        if refreshingPrices, var state = detailTasks[key], !state.ignoresCache {
            state.waiterIDs.insert(waiterID)
            detailTasks[key] = state
            do { _ = try await awaitDetailTask(state.task) }
            catch {
                if error is CancellationError || Task.isCancelled {
                    releaseDetailWaiter(for: key, waiterID: waiterID)
                    throw CancellationError()
                }
            }
            releaseDetailWaiter(for: key, waiterID: waiterID)
            if detailTasks[key]?.id == state.id { detailTasks[key] = nil }
            try Task.checkCancellation()
            return try await details(for: summary, refreshingPrices: true)
        }
        let requestID: UUID
        let task: Task<CatalogCardDetails, Error>
        if var state = detailTasks[key] {
            state.waiterIDs.insert(waiterID)
            task = state.task
            requestID = state.id
            detailTasks[key] = state
        } else {
            requestID = UUID()
            let retryRequested = priceRetryDetailKeys.remove(key) != nil
            let ignoresCache = refreshingPrices || stale != nil || retryRequested
            let newTask = Task { [self] in
                try await loadDetails(for: summary, ignoringCache: ignoresCache)
            }
            detailTasks[key] = DetailTaskState(
                id: requestID,
                task: newTask,
                ignoresCache: ignoresCache,
                waiterIDs: [waiterID]
            )
            task = newTask
        }

        do {
            let details = try await awaitDetailTask(task)
            try Task.checkCancellation()
            if detailTasks[key]?.id == requestID { detailCache[key] = details }
            releaseDetailWaiter(for: key, waiterID: waiterID)
            return details
        } catch {
            releaseDetailWaiter(for: key, waiterID: waiterID)
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if let catalogError = error as? BrowseCatalogError {
                switch catalogError {
                case .unknownSet, .providerCountMismatch: throw error
                case .invalidURL, .badResponse: break
                }
            }
            if error is CatalogLookupError || error is CardGameSupportError { throw error }
            if let stale, detailCache[key]?.retrievedAt == stale.retrievedAt {
                return stale
            }
            throw error
        }
    }

    nonisolated static func detailsAreFresh(_ details: CatalogCardDetails, now: Date) -> Bool {
        let prices = details.card.marketPrices
        let maxAge: TimeInterval = prices.isEmpty || prices.contains(where: \.isGap)
            ? 6 * 60 * 60 : 24 * 60 * 60
        let age = now.timeIntervalSince(details.retrievedAt)
        return age >= 0 && age < maxAge
    }

    /// Awaiting a shared task must still respond to cancellation for this
    /// caller. The stream observer is cancelled per waiter; it never cancels
    /// the shared fetch, so another waiter can keep that fetch alive.
    private func awaitDetailTask<Value: Sendable>(
        _ task: Task<Value, Error>
    ) async throws -> Value {
        let stream = AsyncThrowingStream<Value, Error> { continuation in
            let observer = Task {
                do {
                    continuation.yield(try await task.value)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                observer.cancel()
            }
        }

        var iterator = stream.makeAsyncIterator()
        guard let details = try await iterator.next() else {
            throw CancellationError()
        }
        return details
    }

    private func releaseDetailWaiter(for key: String, waiterID: UUID) {
        guard var state = detailTasks[key],
              state.waiterIDs.remove(waiterID) != nil else {
            return
        }
        if state.waiterIDs.isEmpty {
            state.task.cancel()
            detailTasks[key] = nil
        } else {
            detailTasks[key] = state
        }
    }

    private func loadDetails(for summary: CatalogCardSummary, ignoringCache: Bool = false) async throws -> CatalogCardDetails {
        if let adapter = gameBrowseAdapters.adapter(for: summary.game) {
            let details = try await adapter.details(for: summary)
            try validateBrowseGeneration(adapter)
            return details
        }
        let details: CatalogCardDetails
        switch summary.game {
        case .pokemon:
            let revision = catalogRevision
            let registry = catalogRegistry
            let context = try await authorizedPokemonDetailSet(for: summary)
            if let card = PokemonReviewedEnergyCatalog.card(providerID: summary.providerID),
               card.set.id == summary.setID.providerID {
                return CatalogCardDetails(
                    card: .pokemon(card.applyingAdditionalVariants(from: catalogRegistry), setCode: context.code),
                    set: context, retrievedAt: now())
            }
            if summary.providerID.hasPrefix("tcgplayer:"),
               let card = PokemonReviewedArtworkCatalog.card(providerID: summary.providerID), card.set.id == summary.setID.providerID {
                return CatalogCardDetails(card: .pokemon(card.applyingAdditionalVariants(from: catalogRegistry), setCode: context.code),
                    set: context, retrievedAt: now())
            }
            let catalog = try await pokemonSet(id: summary.setID.providerID)
            guard let brief = catalog.cards.first(where: { $0.id == summary.providerID }) else { throw BrowseCatalogError.unknownSet }
            let set = PokemonMasterSetChecklistBuilder.enrichedSet(context, providerSet: catalog)
            var card = try await pokemonDetailPayload(id: summary.providerID, ignoringCache: ignoringCache)
            guard card.id == summary.providerID,
                  card.localId == brief.localId,
                  card.set.id.caseInsensitiveCompare(set.providerID) == .orderedSame else { throw BrowseCatalogError.unknownSet }
            if registry.descriptor(forProviderSetID: set.providerID)?.providerFingerprint != nil,
               let loaded = try await checklistStore.loadedChecklist(for: set.catalogID, registry: registry,
                    requiresExactFingerprint: true), loaded.source == .signed,
               let installed = PokemonOfflineCardFactory.card(in: loaded, providerCardID: card.id) {
                guard CardNameSearch.normalize(card.name) == CardNameSearch.normalize(installed.name) else {
                    throw CatalogLookupError.staleCatalog
                }
                card.projectedCatalogVariants = installed.projectedCatalogVariants
            }
            _ = try await authorizedPokemonDetailSet(for: summary)
            _ = try await pokemonSet(id: summary.setID.providerID)
            guard revision == catalogRevision else { throw CatalogLookupError.staleCatalog }
            details = CatalogCardDetails(card: .pokemon(card, setCode: set.code), set: set, retrievedAt: now())
        case .magic:
            let card = try await scryfall.fetchCard(id: summary.providerID, ignoringCache: ignoringCache)
            let retrievedAt = now()
            let directory = try await sets(for: .magic)
            let directorySet = directory.first { $0.catalogID == summary.setID }
            guard let set = directorySet else { throw BrowseCatalogError.unknownSet }
            details = CatalogCardDetails(card: .magic(card), set: set, retrievedAt: retrievedAt)
        default: throw CardGameSupportError.unsupportedGame(summary.game)
        }
        return details
    }

    private func addingTCGCSVPrices(to details: CatalogCardDetails) async -> CatalogCardDetails {
        guard let source = tcgCSVSource,
              case let .pokemon(payload, code) = details.card.legacyIdentity,
              PokemonTCGCSVMapping.byCardID[payload.id]?.setID == payload.set.id else { return details }
        var card = payload
        // A failed refresh must not erase a previously retrieved quote or its
        // provenance. A successful snapshot still replaces it, including gaps.
        guard let snapshot = try? await source.snapshot(setID: card.set.id, retry: false) else {
            return details
        }
        card.supplementalTCGCSV = snapshot
        return CatalogCardDetails(
            card: .pokemon(card, setCode: code), set: details.set,
            retrievedAt: details.retrievedAt
        )
    }

    private func detailCacheKey(for summary: CatalogCardSummary) -> String {
        [summary.game.rawValue, summary.providerID.lowercased(), summary.catalogGeneration,
         summary.setID.id].compactMap { $0 }.joined(separator: ":")
    }

    private func authorizedPokemonDetailSet(for summary: CatalogCardSummary) async throws -> CatalogSet {
        guard summary.setID.game == .pokemon, await pokemonSetIsAuthorized(summary.setID.providerID) else {
            throw BrowseCatalogError.unknownSet
        }
        await loadPokemonSnapshotIfNeeded()
        if let entry = pokemonSnapshotEntries.first(where: { $0.set.catalogID == summary.setID }) {
            guard let cards = await checklistStore.mergedChecklist(for: summary.setID),
                  PokemonReviewedEnergyCatalog.addingSummaries(cards, set: entry.set)
                    .contains(where: { $0.providerID == summary.providerID }) else { throw BrowseCatalogError.unknownSet }
            return pokemonSets(from: [entry])[0]
        }
        let provider = try await pokemonSet(id: summary.setID.providerID)
        guard provider.cards.contains(where: { $0.id == summary.providerID })
            || PokemonReviewedEnergyCatalog.card(providerID: summary.providerID)?.set.id == provider.id
            || PokemonReviewedArtworkCatalog.hasAnchor(for: summary.providerID, in: provider) else {
            throw BrowseCatalogError.unknownSet
        }
        if catalogRegistry.descriptor(forProviderSetID: provider.id) != nil {
            let base = try reconciliationBaseSet(provider: provider, providerSetID: provider.id)
            if summary.pokemonPrintRun == nil { return base }
            guard catalogCoordinator == nil else { throw BrowseCatalogError.unknownSet }
            return CatalogSet(catalogID: summary.setID, name: summary.setName, code: base.code,
                logoURL: base.logoURL, symbolURL: base.symbolURL, cardCount: base.cardCount,
                releaseDate: base.releaseDate, sortRank: base.sortRank)
        }
        return CatalogSet(catalogID: summary.setID, name: summary.setName, code: summary.setCode,
                          logoURL: nil, symbolURL: nil, cardCount: provider.cards.count,
                          releaseDate: provider.releaseDate.flatMap(FlexibleDate.parse), sortRank: 0)
    }

    private func pokemonDetailPayload(id: String, ignoringCache: Bool) async throws -> TCGdexCard {
        let waiter = UUID()
        if ignoringCache, var current = pokemonDetailPayloadTasks[id], !current.ignoresCache {
            current.waiters.insert(waiter)
            pokemonDetailPayloadTasks[id] = current
            do { _ = try await awaitDetailTask(current.task) }
            catch {
                if error is CancellationError || Task.isCancelled {
                    releasePokemonPayloadWaiter(id: id, requestID: current.id, waiter: waiter)
                    throw CancellationError()
                }
            }
            releasePokemonPayloadWaiter(id: id, requestID: current.id, waiter: waiter)
            if pokemonDetailPayloadTasks[id]?.id == current.id { pokemonDetailPayloadTasks[id] = nil }
            try Task.checkCancellation()
            return try await pokemonDetailPayload(id: id, ignoringCache: true)
        }
        var state = pokemonDetailPayloadTasks[id] ?? PokemonPayloadTaskState(
            id: UUID(), task: Task { try await pokemonTransport.fetchCard(id: id, ignoringCache: ignoringCache) },
            ignoresCache: ignoringCache, waiters: [])
        state.waiters.insert(waiter)
        pokemonDetailPayloadTasks[id] = state
        defer { releasePokemonPayloadWaiter(id: id, requestID: state.id, waiter: waiter) }
        return try await awaitDetailTask(state.task).applyingAdditionalVariants(from: catalogRegistry)
    }

    private func releasePokemonPayloadWaiter(id: String, requestID: UUID, waiter: UUID) {
        guard var current = pokemonDetailPayloadTasks[id], current.id == requestID else { return }
        current.waiters.remove(waiter)
        if current.waiters.isEmpty {
            current.task.cancel()
            pokemonDetailPayloadTasks[id] = nil
        } else { pokemonDetailPayloadTasks[id] = current }
    }

    func price(for summary: CatalogCardSummary, variant: PhysicalVariant) async throws -> PriceLookup {
        if let deck = PokemonBattleDeckFinishCatalog.entry(for: summary), deck.variant.id == variant.id {
            await synchronizeCatalogAuthority()
            _ = try await authorizedPokemonDetailSet(for: summary)
            let revision = catalogRevision
            let quote = try await pokemonDeckPrices?.quote(for: deck) ?? .unavailable(nil)
            try Task.checkCancellation()
            guard revision == catalogRevision else { throw CatalogLookupError.staleCatalog }
            return quote
        }
        let details = await addingTCGCSVPrices(to: try await details(for: summary))
        try Task.checkCancellation()
        let key = detailCacheKey(for: summary)
        if detailCache[key]?.retrievedAt == details.retrievedAt {
            detailCache[key] = details
        }
        if let adapter = gameBrowseAdapters.adapter(for: summary.game),
           let quote = try await adapter.price(for: summary, variant: variant) {
            try validateBrowseGeneration(adapter)
            if case let .price(price) = quote, !price.isUsableUSD { throw PriceQuoteError.providerUnavailable }
            return quote
        }
        if priceQuoteService.supportsStoredPrintingRefresh(for: summary.game) {
            let quote = try await priceQuoteService.refresh(card: details.card, variant: variant,
                                                           pokemonPrintRun: summary.pokemonPrintRun)
            await synchronizeGameBrowseAuthority(for: summary.game)
            guard gameBrowseAdapters.adapter(for: summary.game)?.generation == summary.catalogGeneration else {
                throw CatalogLookupError.staleCatalog
            }
            return quote
        }
        let lookup = CardPricing.price(for: details.card, variant: variant,
                                       magicTreatments: details.card.magicTreatments(for: variant),
                                       pokemonPrintRun: summary.pokemonPrintRun, at: details.retrievedAt)
        if case let .price(price) = lookup, price.currencyCode == "USD" { return lookup }
        // Reuse the set-wide source used by the grid, only for an exact ordinary finish.
        guard summary.game == .pokemon, summary.pokemonPrintRun == nil,
              let listing = PokemonBulkPriceMap.listingKey(for: variant),
              let source = pokemonPriceSource,
              let secondarySetID = try await resolvedPokemonSecondarySetID(for: summary) else { return lookup }
        let bulk = try await pokemonBulkPrices(for: summary.setID.providerID,
                                              secondarySetID: secondarySetID, source: source)
        guard let amount = bulk.price(for: summary.providerID, variant: variant) else { return lookup }
        let fetchedAt = pokemonBulkPriceCache[summary.setID.providerID.lowercased()]?.storedAt ?? details.retrievedAt
        return .price(.init(unitMarketPriceUSD: amount, currencyCode: "USD", source: .tcgplayer,
                            sourceVariantID: listing, sourceUpdatedAt: bulk.providerUpdatedAt(for: summary.providerID),
                            fetchedAt: fetchedAt))
    }

    private func validateBrowseGeneration(_ adapter: any GameBrowseAdapter) throws {
        guard gameBrowseAdapters.adapter(for: adapter.game)?.generation == adapter.generation else {
            throw CatalogLookupError.staleCatalog
        }
    }

    private func synchronizeGameBrowseAuthority(for game: CardGame) async {
        guard let source = gameActivationSources[game] else { return }
        if gameBrowseTasks[game] == nil {
            gameBrowseTasks[game] = Task { [weak self] in
                let events = await source.activationSnapshots()
                if let initial = await source.currentSnapshot(), !Task.isCancelled {
                    await self?.installBrowseSnapshot(initial, for: game)
                }
                for await snapshot in events {
                    guard !Task.isCancelled else { return }
                    await self?.installBrowseSnapshot(snapshot, for: game)
                }
            }
        }
        if let snapshot = await source.currentSnapshot() { installBrowseSnapshot(snapshot, for: game) }
    }

    private func installBrowseSnapshot(_ snapshot: GameCatalogSnapshot, for game: CardGame) {
        guard let adapter = snapshot.browse, adapter.game == game,
              snapshot.revision > (gameBrowseRevisions[game] ?? -1) else { return }
        gameBrowseRevisions[game] = snapshot.revision
        gameBrowseAdapters = gameBrowseAdapters.replacing(adapter)
        setCache[game] = nil
        detailCache = detailCache.filter { !$0.key.hasPrefix(game.rawValue + ":") }
        if priceQuoteService.supportsStoredPrintingRefresh(for: game) {
            sortPriceResolutionGeneration = UUID()
            sortPriceCache = sortPriceCache.filter { !$0.key.hasPrefix(game.rawValue + ":") }
            sortPriceCheckedAt = sortPriceCheckedAt.filter { !$0.key.hasPrefix(game.rawValue + ":") }
            resolvedSortPrices = resolvedSortPrices.filter { !$0.hasPrefix(game.rawValue + ":") }
            unresolvedSortPrices = unresolvedSortPrices.filter { !$0.hasPrefix(game.rawValue + ":") }
        }
        yieldUpdate(game: game, revision: snapshot.revision, providerSetID: nil)
    }

    private func installMagicPrices(
        _ cached: [String: CatalogCachedPrice]?,
        for cards: [CatalogCardSummary], asOf: Date = .now
    ) {
        guard let cached else { return }
        for card in cards {
            guard let entry = cached[card.id] else { continue }
            if case let .priced(value, date)? = CatalogSortPriceResolution.cachedPrice(entry.value, asOf: asOf) {
                if SortPriceHint(price: value, checkedAt: date).isFresh() {
                    resolvedSortPrices.insert(card.id)
                    unresolvedSortPrices.remove(card.id)
                } else {
                    resolvedSortPrices.remove(card.id)
                    unresolvedSortPrices.insert(card.id)
                }
                sortPriceCache[card.id] = value
                sortPriceCheckedAt[card.id] = date
            } else if entry.confirmsNoUSDQuote, asOf <= .now,
                      Date.now.timeIntervalSince(asOf) < 6 * 60 * 60 {
                resolvedSortPrices.insert(card.id)
                unresolvedSortPrices.remove(card.id)
                sortPriceCache.removeValue(forKey: card.id)
                sortPriceCheckedAt[card.id] = asOf
            } else {
                // Legacy nil amounts do not establish a provider answer.
                resolvedSortPrices.remove(card.id)
                unresolvedSortPrices.remove(card.id)
                sortPriceCache.removeValue(forKey: card.id)
            }
        }
    }

    func resetPriceResolution(for ids: [String]) async {
        sortPriceResolutionGeneration = UUID()
        var pokemonSetIDs: Set<String> = []
        for id in ids {
            missingMappingSortPrices.remove(id)
            resolvedSortPrices.remove(id)
            unresolvedSortPrices.remove(id)
            sortPriceCache.removeValue(forKey: id)
            sortPriceCheckedAt.removeValue(forKey: id)
            // Use the actual cache keys, including catalog generation and set scope.
            let matchingKeys = detailCache.filter { _, details in
                let matches = id.hasPrefix("\(details.card.game.rawValue):\(details.set.catalogID.providerID.lowercased()):")
                    && id.split(separator: ":").contains(Substring(details.card.providerID))
                return matches && (details.card.game == .pokemon
                    || details.card.marketPrices.isEmpty || details.card.marketPrices.contains(where: \.isGap))
            }.map(\.key)
            for key in matchingKeys {
                detailCache.removeValue(forKey: key)
                priceRetryDetailKeys.insert(key)
            }
            let components = id.split(separator: ":", maxSplits: 3)
            if components.count >= 3,
               components[0] == CardGame.pokemon.rawValue {
                pokemonSetIDs.insert(String(components[1]))
            }
        }
        for setID in pokemonSetIDs {
            pokemonBulkPriceCache.removeValue(forKey: setID.lowercased())
            tcgCSVRetrySetIDs.insert(setID.lowercased())
        }
        await cache.invalidatePokemonPricing(for: pokemonSetIDs)
    }

    nonisolated func sortPriceUpdates(
        for cards: [CatalogCardSummary]
    ) -> AsyncStream<CatalogPriceUpdate> {
        return AsyncStream { continuation in
            let producer = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                await self.installMemoryWarningObserverIfNeeded()
                await self.produceSortPriceUpdates(for: cards, continuation: continuation)
            }
            continuation.onTermination = { @Sendable _ in
                producer.cancel()
            }
        }
    }

    nonisolated func sortPrices(for cards: [CatalogCardSummary]) -> AsyncStream<[String: Double]> {
        AsyncStream { continuation in
            let producer = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                for await update in self.sortPriceUpdates(for: cards) {
                    continuation.yield(update.prices)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }

    private func produceSortPriceUpdates(
        for cards: [CatalogCardSummary],
        continuation: AsyncStream<CatalogPriceUpdate>.Continuation
    ) async {
        // Every early return below leaves the consumer suspended in `for await`
        // unless the stream is finished, which would strand the set screen in
        // its loading state. Finishing twice is a no-op, so own it here once.
        defer { continuation.finish() }

        let resolutionGeneration = sortPriceResolutionGeneration

        // A long-lived Browse actor must recheck prices that arrived after a
        // set opened. In particular, a negative result is never permanent.
        let now = Date.now
        for card in cards {
            guard let checkedAt = sortPriceCheckedAt[card.id] else { continue }
            let maxAge: TimeInterval = sortPriceCache[card.id] == nil
                ? 6 * 60 * 60 : 24 * 60 * 60
            let age = now.timeIntervalSince(checkedAt)
            guard age < 0 || age >= maxAge else { continue }
            resolvedSortPrices.remove(card.id)
            missingMappingSortPrices.remove(card.id)
        }

        let cardsBySet = Dictionary(grouping: cards, by: \.setID.id)
        var persistedPrices: [String: [String: SortPriceHint]] = [:]
        for (setID, setCards) in cardsBySet {
            // Mapping-owned prices must be revalidated against the current catalog.
            // The provider already caches its daily snapshots; bare sort hints lack mapping evidence.
            if let game = setCards.first?.game,
               priceQuoteService.supportsStoredPrintingRefresh(for: game) { continue }
            guard let cached = await cache.sortPrices(for: setID) else { continue }
            persistedPrices[setID] = cached.value
            let currentIDs = Set(setCards.map(\.id))
            for (id, hint) in cached.value where currentIDs.contains(id) {
                // A newer provider check may have disproved a persisted price.
                // Do not resurrect that old ordering hint on this screen.
                if resolvedSortPrices.contains(id),
                   let checkedAt = sortPriceCheckedAt[id], checkedAt >= hint.checkedAt,
                   sortPriceCache[id] == nil { continue }
                if let date = sortPriceCheckedAt[id], date > hint.checkedAt { continue }
                sortPriceCache[id] = hint.price
                sortPriceCheckedAt[id] = hint.checkedAt
                if hint.isFresh() {
                    resolvedSortPrices.insert(id)
                } else {
                    resolvedSortPrices.remove(id)
                }
            }
        }

        continuation.yield(currentPriceUpdate(for: cards))

        let pending = providerGroups(from: cards).filter { providerGroup in
            providerGroup.contains { !resolvedSortPrices.contains($0.id) }
        }
        await preparePokemonBulkPrices(for: pending.flatMap { $0 })
        var iterator = pending.makeIterator()
        var refreshedIDs: Set<String> = []
        var completedSinceEmit = 0
        var lastEmit = Date.now

        do {
            try await withThrowingTaskGroup(of: SortPriceGroupResult.self) { group in
                for _ in 0..<min(6, pending.count) {
                    guard let providerGroup = iterator.next() else { break }
                    group.addTask { try await self.sortPriceGroup(for: providerGroup) }
                }

                while let result = try await group.next() {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        return
                    }
                    guard resolutionGeneration == sortPriceResolutionGeneration else {
                        group.cancelAll()
                        return
                    }
                    for slot in result.slots {
                        refreshedIDs.insert(slot.id)
                        switch slot.resolution {
                        case let .priced(price, asOf):
                            missingMappingSortPrices.remove(slot.id)
                            if SortPriceHint(price: price, checkedAt: asOf).isFresh() {
                                resolvedSortPrices.insert(slot.id)
                                unresolvedSortPrices.remove(slot.id)
                            } else {
                                resolvedSortPrices.remove(slot.id)
                                unresolvedSortPrices.insert(slot.id)
                            }
                            sortPriceCache[slot.id] = price
                            sortPriceCheckedAt[slot.id] = asOf
                        case .noUSDQuote:
                            missingMappingSortPrices.remove(slot.id)
                            resolvedSortPrices.insert(slot.id)
                            unresolvedSortPrices.remove(slot.id)
                            sortPriceCache.removeValue(forKey: slot.id)
                            sortPriceCheckedAt[slot.id] = .now
                        case .mappingMissing:
                            missingMappingSortPrices.insert(slot.id)
                            resolvedSortPrices.insert(slot.id)
                            unresolvedSortPrices.remove(slot.id)
                            sortPriceCache.removeValue(forKey: slot.id)
                            sortPriceCheckedAt[slot.id] = .now
                        case .unresolved:
                            missingMappingSortPrices.remove(slot.id)
                            resolvedSortPrices.remove(slot.id)
                            unresolvedSortPrices.insert(slot.id)
                            // A failed check cannot disprove a saved ordering
                            // hint or renew its date. Only a resolved gap clears it.
                            if sortPriceCache[slot.id] == nil { sortPriceCheckedAt.removeValue(forKey: slot.id) }
                        }
                    }
                    completedSinceEmit += result.slots.count

                    let elapsed = Date.now.timeIntervalSince(lastEmit)
                    if completedSinceEmit >= 25 || elapsed >= 0.25 {
                        continuation.yield(currentPriceUpdate(for: cards))
                        completedSinceEmit = 0
                        lastEmit = Date.now
                    }

                    if Task.isCancelled {
                        group.cancelAll()
                    } else if let providerGroup = iterator.next() {
                        group.addTask { try await self.sortPriceGroup(for: providerGroup) }
                    }
                }
                if Task.isCancelled { group.cancelAll() }
            }
        } catch is CancellationError {
            return
        } catch {
            return
        }

        guard !Task.isCancelled,
              resolutionGeneration == sortPriceResolutionGeneration else { return }

        for (setID, setCards) in cardsBySet {
            if let game = setCards.first?.game,
               priceQuoteService.supportsStoredPrintingRefresh(for: game) { continue }
            guard setCards.contains(where: { refreshedIDs.contains($0.id) }) else { continue }
            // A request covers only the slots that were loaded, and the price
            // prefetch runs on the first page. Replacing the stored map would
            // shrink a fully priced set to one page on every cold open, which
            // is the relaunch cost this cache exists to remove. Merge instead:
            // this run's prices win, previously priced slots survive.
            var prices = persistedPrices[setID] ?? [:]
            for card in setCards {
                if let price = sortPriceCache[card.id], let date = sortPriceCheckedAt[card.id] {
                    prices[card.id] = SortPriceHint(price: price, checkedAt: date)
                } else if resolvedSortPrices.contains(card.id) {
                    prices.removeValue(forKey: card.id)
                }
            }
            // An empty map is meaningful when a prior price was disproved.
            // Envelope writes never renew individual slot evidence dates.
            await cache.storeSortPrices(prices, for: setID)
        }

        continuation.yield(currentPriceUpdate(for: cards))
    }

    private func providerGroups(from cards: [CatalogCardSummary]) -> [[CatalogCardSummary]] {
        var groups: [[CatalogCardSummary]] = []
        var indexes: [String: Int] = [:]
        for card in cards {
            let key: String
            if card.game == .pokemon {
                // Bulk pricing is prefetched once per set above. Keep the
                // fallback work one card per group so the outer six-wide task
                // pool can make progress when the bulk path is unavailable.
                key = "pokemon-card:\(card.id.lowercased())"
            } else {
                key = "\(card.game.rawValue):\(card.providerID.lowercased())"
            }
            if let index = indexes[key] {
                groups[index].append(card)
            } else {
                indexes[key] = groups.count
                groups.append([card])
            }
        }
        return groups
    }

    private func currentPriceUpdate(for cards: [CatalogCardSummary]) -> CatalogPriceUpdate {
        let cardIDs = Set(cards.map(\.id))
        return CatalogPriceUpdate(
            prices: Dictionary(
                cards.compactMap { card in
                    sortPriceCache[card.id].map { (card.id, $0) }
                },
                uniquingKeysWith: { first, _ in first }
            ),
            resolvedIDs: resolvedSortPrices.intersection(cardIDs),
            unresolvedIDs: unresolvedSortPrices.intersection(cardIDs),
            missingMappingIDs: missingMappingSortPrices.intersection(cardIDs)
        )
    }

    private func sortPriceGroup(for summaries: [CatalogCardSummary]) async throws -> SortPriceGroupResult {
        if summaries.first?.game == .pokemon {
            return await sortPokemonPriceGroup(for: summaries)
        }
        guard let representative = summaries.first(where: { $0.pokemonPrintRun == nil }) else {
            return SortPriceGroupResult(
                slots: summaries.map {
                    SortPriceSlot(id: $0.id, resolution: .noUSDQuote)
                }
            )
        }

        do {
            let details = try await details(for: representative)
            var slots: [SortPriceSlot] = []
            slots.reserveCapacity(summaries.count)
            for summary in summaries {
                guard summary.pokemonPrintRun == nil else {
                    // The aggregate card price is not edition-specific. Do
                    // not use it to sort virtual WotC runs as though it were.
                    slots.append(SortPriceSlot(id: summary.id, resolution: .noUSDQuote))
                    continue
                }
                slots.append(await sortPrice(for: summary, details: details))
            }
            return SortPriceGroupResult(
                slots: slots
            )
        } catch {
            if error is CancellationError || Task.isCancelled {
                throw CancellationError()
            }
            return SortPriceGroupResult(
                slots: summaries.map {
                    SortPriceSlot(
                        id: $0.id,
                        resolution: $0.pokemonPrintRun != nil
                            ? .noUSDQuote
                            : .unresolved
                    )
                }
            )
        }
    }

    private func sortPokemonPriceGroup(
        for summaries: [CatalogCardSummary]
    ) async -> SortPriceGroupResult {
        guard let setID = summaries.first?.setID.providerID,
              PokemonBattleDeckFinishCatalog.setIDs.contains(setID) else {
            return await sortPokemonCatalogPriceGroup(for: summaries)
        }
        var regular: [CatalogCardSummary] = []
        var slots: [SortPriceSlot] = []
        for summary in summaries {
            guard let variant = summary.masterSetVariant,
                  PokemonBattleDeckFinishCatalog.entry(for: summary)?.variant.id == variant.id else {
                regular.append(summary)
                continue
            }
            let lookup = try? await price(for: summary, variant: variant)
            slots.append(SortPriceSlot(id: summary.id, resolution: lookup.map(CatalogSortPriceResolution.exactLookup) ?? .unresolved))
        }
        if !regular.isEmpty {
            slots.append(contentsOf: await sortPokemonCatalogPriceGroup(for: regular).slots)
        }
        return SortPriceGroupResult(slots: slots)
    }

    private func sortPokemonCatalogPriceGroup(
        for summaries: [CatalogCardSummary]
    ) async -> SortPriceGroupResult {
        if let source = tcgCSVSource,
           let setID = summaries.first?.setID.providerID.lowercased(),
           PokemonTCGCSVMapping.groupID(for: setID) != nil {
            do {
                let retry = tcgCSVRetrySetIDs.remove(setID) != nil
                let snapshot = try await source.snapshot(setID: setID, retry: retry)
                try Task.checkCancellation()
                let checkedAt = now()
                return SortPriceGroupResult(slots: summaries.map { summary in
                    if let details = detailCache[detailCacheKey(for: summary)],
                       Self.detailsAreFresh(details, now: checkedAt) {
                        let detailed = details.card
                        let existing = CardPricing.price(
                            for: detailed, variant: summary.masterSetVariant ?? .holo,
                            magicTreatments: detailed.magicTreatments(for: summary.masterSetVariant),
                            pokemonPrintRun: summary.pokemonPrintRun, at: details.retrievedAt
                        )
                        if case let .price(price) = existing, price.source != .tcgCSV,
                           price.currencyCode == "USD", !price.isStale(now: checkedAt) {
                            return SortPriceSlot(id: summary.id, resolution: .priced(price.unitMarketPriceUSD, asOf: price.fetchedAt))
                        }
                    }
                    guard let lookup = snapshot.quote(
                        cardID: summary.providerID, variant: summary.masterSetVariant ?? .holo,
                        printRun: summary.pokemonPrintRun
                    ) else { return SortPriceSlot(id: summary.id, resolution: .unresolved) }
                    return SortPriceSlot(id: summary.id, resolution: CatalogSortPriceResolution.exactLookup(lookup))
                })
            } catch {
                return SortPriceGroupResult(slots: summaries.map {
                    SortPriceSlot(id: $0.id, resolution: .unresolved)
                })
            }
        }
        guard pokemonPriceSource != nil,
              let setID = summaries.first?.setID.providerID,
              let cachedBulk = pokemonBulkPriceCache[setID.lowercased()] else {
            let fallback = await fallbackSortPriceGroup(for: summaries)
            // A TCGdex-only miss is not proof that the set-wide USD source
            // lacks a quote, especially for a release absent from its catalog.
            guard pokemonPriceSource != nil else { return fallback }
            return SortPriceGroupResult(slots: fallback.slots.map { slot in
                SortPriceSlot(
                    id: slot.id,
                    resolution: slot.resolution == .noUSDQuote ? .unresolved : slot.resolution
                )
            })
        }

        var slots: [SortPriceSlot] = []
        slots.reserveCapacity(summaries.count)
        let bulk = cachedBulk.value
        for summary in summaries {
            // Virtual print runs are deliberately not allowed to inherit a
            // normal-set quote. They remain resolved-but-unpriced unless the
            // exact card path already has a run-specific answer.
            guard summary.pokemonPrintRun == nil else {
                slots.append(SortPriceSlot(id: summary.id, resolution: .noUSDQuote))
                continue
            }

            if let price = bulk.price(
                for: summary.providerID,
                variant: summary.masterSetVariant
            ) {
                slots.append(SortPriceSlot(id: summary.id, resolution: .priced(price, asOf: cachedBulk.storedAt)))
            } else {
                // A missing bulk value does not confirm that the exact finish
                // lacks a quote. Check the detailed card before resolving it.
                let fallback = await sortPrice(for: summary)
                slots.append(SortPriceSlot(
                    id: summary.id,
                    resolution: fallback.resolution == .noUSDQuote
                        && (!cachedBulk.isFresh || !bulk.covers(
                            providerID: summary.providerID,
                            variant: summary.masterSetVariant
                        ))
                        ? .unresolved : fallback.resolution
                ))
            }
        }
        return SortPriceGroupResult(slots: slots)
    }

    /// Resolve and fetch one bulk map per TCGdex set before the card-level
    /// worker pool starts. This keeps the set-wide optimization while allowing
    /// every uncovered card to use an independent fallback slot.
    private func preparePokemonBulkPrices(for cards: [CatalogCardSummary]) async {
        guard let source = pokemonPriceSource else { return }
        let cardsBySet = Dictionary(
            grouping: cards.filter { $0.game == .pokemon },
            by: { $0.setID.providerID.lowercased() }
        )

        for summaries in cardsBySet.values {
            guard let summary = summaries.first else { continue }
            if tcgCSVSource != nil,
               PokemonTCGCSVMapping.groupID(for: summary.setID.providerID) != nil { continue }
            do {
                guard let secondarySetID = try await resolvedPokemonSecondarySetID(
                    for: summary
                ) else { continue }
                _ = try await pokemonBulkPrices(
                    for: summary.setID.providerID,
                    secondarySetID: secondarySetID,
                    source: source
                )
            } catch is CancellationError {
                return
            } catch {
                // Bulk pricing is an optimization. Every card remains eligible
                // for the exact path below when set resolution or the set query
                // is unavailable.
                continue
            }
        }
    }

    private func fallbackSortPriceGroup(
        for summaries: [CatalogCardSummary]
    ) async -> SortPriceGroupResult {
        var slots: [SortPriceSlot] = []
        slots.reserveCapacity(summaries.count)
        for summary in summaries {
            slots.append(await sortPrice(for: summary))
        }
        return SortPriceGroupResult(slots: slots)
    }

    private func pokemonBulkPrices(
        for setID: String,
        secondarySetID: String,
        source: any PokemonBulkPriceSource
    ) async throws -> PokemonBulkPriceMap {
        let key = setID.lowercased()
        if let cached = pokemonBulkPriceCache[key], cached.isFresh {
            return cached.value
        }
        let persisted = await cache.pokemonBulkPrices(for: setID)
        if let persisted,
           persisted.isFresh,
           persisted.value.isStage4Compatible {
            pokemonBulkPriceCache[key] = PokemonBulkSnapshot(
                value: persisted.value,
                storedAt: persisted.storedAt
            )
            return persisted.value
        }

        do {
            let loaded = try await source.fetchBulkPrices(
                tcgdexSetID: setID,
                secondarySetID: secondarySetID
            )
            pokemonBulkPriceCache[key] = PokemonBulkSnapshot(value: loaded, storedAt: .now)
            await cache.storePokemonBulkPrices(loaded, for: setID)
            return loaded
        } catch {
            // A stale set snapshot is better than paying one request per card
            // while offline. The next successful fetch replaces it and resets
            // its age; this branch never turns stale data into a fresh claim.
            if let persisted {
                pokemonBulkPriceCache[key] = PokemonBulkSnapshot(
                    value: persisted.value,
                    storedAt: persisted.storedAt
                )
                return persisted.value
            }
            throw error
        }
    }

    private func resolvedPokemonSecondarySetID(
        for summary: CatalogCardSummary
    ) async throws -> String? {
        let tcgdexSetID = summary.setID.providerID
        let persistedMatch = await cache.pokemonBulkSetMatch(for: tcgdexSetID)
        if let persistedMatch, persistedMatch.isFresh {
            return persistedMatch.value.secondarySetID
        }

        // Recorded/offline Browse transports intentionally have no secondary
        // directory source. Their injected price source already speaks the
        // test's canonical set id, so retain that deterministic seam.
        guard let source = pokemonSecondarySetSource else {
            let match = PokemonBulkSetMatch(secondarySetID: tcgdexSetID)
            await cache.storePokemonBulkSetMatch(match, for: tcgdexSetID)
            return tcgdexSetID
        }

        let candidates: [PokemonCatalogSecondarySet]
        do {
            candidates = try await pokemonSecondarySets(from: source)
        } catch {
            if let persistedMatch {
                return persistedMatch.value.secondarySetID
            }
            throw error
        }
        let match: PokemonBulkSetMatch
        if let inputs = pokemonBulkSetMatchInputs(for: summary) {
            let outcome = PokemonCatalogSecondarySetMatcher.match(
                tcgdex: inputs.tcgdex,
                directoryRow: inputs.directoryRow,
                candidates: candidates
            )
            let secondarySetID: String?
            switch outcome {
            case let .matched(candidate): secondarySetID = candidate.id
            case .none, .ambiguous: secondarySetID = nil
            }
            match = PokemonBulkSetMatch(secondarySetID: secondarySetID)
        } else {
            match = PokemonBulkSetMatch(secondarySetID: nil)
        }
        await cache.storePokemonBulkSetMatch(match, for: tcgdexSetID)
        return match.secondarySetID
    }

    private func pokemonSecondarySets(
        from source: any PokemonSecondarySetSource
    ) async throws -> [PokemonCatalogSecondarySet] {
        let persisted = await cache.pokemonSecondarySets()
        if let persisted, persisted.isFresh {
            return persisted.value
        }

        do {
            let loaded = try await source.fetchSecondarySets()
            await cache.storePokemonSecondarySets(loaded)
            return loaded
        } catch {
            if let persisted {
                return persisted.value
            }
            throw error
        }
    }

    private func pokemonBulkSetMatchInputs(
        for summary: CatalogCardSummary
    ) -> (
        tcgdex: PokemonCatalogProviderSet,
        directoryRow: PokemonCatalogProviderDirectoryRow
    )? {
        let providerSetID = summary.setID.providerID
        let descriptor = catalogRegistry.descriptor(forProviderSetID: providerSetID)
        let snapshotEntry = pokemonSnapshotEntries.first {
            $0.providerID.caseInsensitiveCompare(providerSetID) == .orderedSame
        }
        let displayName = basePokemonSetName(
            descriptor?.displayName ?? snapshotEntry?.set.name ?? summary.setName
        )
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let releaseDate = descriptor?.releaseDate
        let code = descriptor?.printedCode
            ?? (summary.setCode == "Code pending" ? nil : summary.setCode)
        let officialCount = descriptor?.officialCount ?? snapshotEntry?.officialCount
        let count = officialCount.map {
            // The signed catalog carries the printed denominator. The matcher
            // uses the separate printedTotal signal rather than treating an
            // expanded master-set count as the provider's total.
            PokemonCatalogProviderCardCount(total: $0, official: $0)
        }
        let tcgdex = PokemonCatalogProviderSet(
            id: providerSetID,
            name: displayName,
            cards: [],
            releaseDate: releaseDate,
            tcgOnline: code,
            cardCount: count,
            abbreviation: PokemonCatalogProviderAbbreviation(official: code)
        )
        let directoryRow = PokemonCatalogProviderDirectoryRow(
            id: providerSetID,
            name: displayName,
            cardCount: count,
            releaseDate: releaseDate,
            tcgOnline: code
        )
        return (tcgdex, directoryRow)
    }

    private func basePokemonSetName(_ name: String) -> String {
        [" — 1st Edition", " — Shadowless", " — Unlimited"].reduce(name) { value, suffix in
            value.hasSuffix(suffix) ? String(value.dropLast(suffix.count)) : value
        }
    }

    private func sortPrice(for summary: CatalogCardSummary) async -> SortPriceSlot {
        guard summary.pokemonPrintRun == nil else {
            return SortPriceSlot(id: summary.id, resolution: .noUSDQuote)
        }
        do {
            let details = try await details(for: summary)
            return await sortPrice(for: summary, details: details)
        } catch {
            return SortPriceSlot(id: summary.id, resolution: .unresolved)
        }
    }

    private func sortPrice(
        for summary: CatalogCardSummary,
        details: CatalogCardDetails
    ) async -> SortPriceSlot {
        if priceQuoteService.supportsStoredPrintingRefresh(for: summary.game) {
            var lookups: [PriceLookup] = []
            var hasMissingMapping = false
            do {
                for variant in summary.masterSetVariant.map({ [$0] }) ?? details.card.variantEvidence.catalogVariants {
                    do { lookups.append(try await price(for: summary, variant: variant)) }
                    catch PriceQuoteError.mappingUnavailable { hasMissingMapping = true }
                }
                if hasMissingMapping, !lookups.contains(where: {
                    if case let .price(price) = $0 { return price.isUsableUSD }; return false
                }) { return SortPriceSlot(id: summary.id, resolution: .mappingMissing) }
                return SortPriceSlot(id: summary.id, resolution: CatalogSortPriceResolution.aggregate(lookups))
            } catch {
                return SortPriceSlot(id: summary.id, resolution: .unresolved)
            }
        }
        if let variant = summary.masterSetVariant {
            let lookup = CardPricing.price(
                for: details.card,
                variant: variant,
                magicTreatments: details.card.magicTreatments(for: variant),
                pokemonPrintRun: summary.pokemonPrintRun,
                at: details.retrievedAt
            )
            if case let .price(price) = lookup,
               price.currencyCode.caseInsensitiveCompare("USD") == .orderedSame {
                return SortPriceSlot(
                    id: summary.id,
                    resolution: .priced(price.unitMarketPriceUSD, asOf: price.fetchedAt)
                )
            }
            return SortPriceSlot(
                id: summary.id,
                resolution: CatalogSortPriceResolution.exactLookup(lookup)
            )
        }

        // An unqualified printing may expose several exact finishes. Sort by
        // the highest current USD quote without changing their identities.
        var lookups: [PriceLookup] = []
        for variant in details.card.variantEvidence.catalogVariants {
            let lookup = CardPricing.price(
                for: details.card,
                variant: variant,
                magicTreatments: details.card.magicTreatments(for: variant),
                pokemonPrintRun: summary.pokemonPrintRun,
                at: details.retrievedAt
            )
            lookups.append(lookup)
        }
        return SortPriceSlot(
            id: summary.id,
            resolution: CatalogSortPriceResolution.aggregate(lookups)
        )
    }

    private func pokemonSets() async throws -> [CatalogSet] {
        let rows = try await pokemonTransport.fetchSetDirectory()
        let baseSets = PokemonMasterSetChecklistBuilder.baseSets(
            from: rows,
            registry: catalogCoordinator == nil ? nil : catalogRegistry
        )
        // `uniquingKeysWith:` rather than `uniqueKeysWithValues:`. These rows
        // are a raw decode of the provider's set directory and are deduplicated
        // nowhere in between, so two ids differing only in case — or one
        // duplicated row, which providers do ship — would trap and take the app
        // down on data nobody here controls. First wins: the directory arrives
        // newest-first, and either count is equally defensible for a duplicate.
        let countsByID = Dictionary(
            rows.compactMap { row in row.cardCount.map { (row.id.lowercased(), $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let sets = baseSets.flatMap { set in
            PokemonMasterSetDefinition.virtualSets(
                set,
                cardCount: countsByID[set.providerID.lowercased()]
            )
        }
        // In the app path the signed registry and a verified checklist are the
        // only production set-activation authorities. A raw directory remains
        // available only to the legacy no-coordinator fixture path.
        if catalogCoordinator != nil { return [] }
        return sets
    }

    /// Browse keeps a few decoded provider responses outside the shared
    /// checklist store. Release those copies on the same memory-warning signal;
    /// checklist pages are bounded and evicted by `PokemonChecklistStore`.
    private func discardDecodedCaches() {
        pokemonSetDetails.removeAll()
        pokemonSetCardDetails.removeAll()
        detailCache.removeAll()
        let inactiveKeys = detailTasks.compactMap { key, state in
            state.waiterIDs.isEmpty ? key : nil
        }
        for key in inactiveKeys {
            detailTasks[key]?.task.cancel()
            detailTasks[key] = nil
        }
        sortPriceCache.removeAll()
        resolvedSortPrices.removeAll()
        unresolvedSortPrices.removeAll()
        missingMappingSortPrices.removeAll()
        sortPriceCheckedAt.removeAll()
        pokemonBulkPriceCache.removeAll()
    }

    private func installMemoryWarningObserverIfNeeded() {
        guard memoryWarningObserver == nil else { return }
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { await self?.discardDecodedCaches() }
        }
    }

    private func magicSets() async throws -> [CatalogSet] {
        if await usesRemoteMagicAuthority() {
            return magicCatalogRegistry.browseSets
        }
        guard let url = URL(string: "https://api.scryfall.com/sets") else { throw BrowseCatalogError.invalidURL }
        let (data, response) = try await magicSession.data(for: request(url, scryfall: true))
        try validate(response)
        let rows = try JSONDecoder().decode(ScryfallBrowseSetList.self, from: data).data.filter {
            MagicCatalogPolicy.isBrowseEligible(code: $0.code, setType: $0.setType ?? "", digital: $0.digital)
        }
        let sets = rows.sorted { ($0.releasedAt ?? "") > ($1.releasedAt ?? "") }.enumerated().map { index, row in
            CatalogSet(
                catalogID: CatalogSetID(game: .magic, providerID: row.code.lowercased()),
                name: row.name,
                code: row.code.uppercased(),
                logoURL: row.iconSVGURI,
                symbolURL: row.iconSVGURI,
                cardCount: row.cardCount,
                releaseDate: row.releasedAt.flatMap(FlexibleDate.parse),
                sortRank: rows.count - index
            )
        }
        if let coordinator = magicCatalogCoordinator,
           await coordinator.currentRolloutMode == .remoteValidationOnly,
           let liveScanner = try? await scryfall.fetchSupportedSets(),
           let liveRouting = try? await scryfall.fetchChildSets() {
            let mismatches = magicCatalogRegistry.legacyParityMismatches(
                scanner: liveScanner,
                browse: sets,
                routing: liveRouting
            )
            await coordinator.recordLegacyParity(mismatches)
        }
        return sets
    }

    private func searchPokemon(query: String, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        let page = Int(cursor ?? "1") ?? 1
        guard let url = BrowseRequestBuilder.pokemonSearchURL(query: query, page: page) else {
            throw BrowseCatalogError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(for: request(url))
        try validate(response)
        let cards = try JSONDecoder().decode([TCGdexCardBrief].self, from: data)
        let directory = try await sets(for: .pokemon)
        let summaries = cards.flatMap { card -> [CatalogCardSummary] in
            let matching = directory.filter { card.id.hasPrefix($0.providerID + "-") }
            guard let longestID = matching.map(\.providerID).max(by: { $0.count < $1.count }) else {
                return []
            }
            return matching
                .filter { $0.providerID == longestID }
                .map { set in
                    let summary = PokemonMasterSetChecklistBuilder.summary(card, set: set)
                    return Self.applyingSignedCardArtwork([summary], set: set).first ?? summary
                }
        }
        return CatalogPage(items: summaries, nextCursor: cards.count == 60 ? String(page + 1) : nil)
    }

    private func magicCards(
        query: String,
        cursor: String?
    ) async throws -> MagicCardsPageResult {
        let url: URL
        if let cursor {
            guard let next = URL(string: cursor), next.host == "api.scryfall.com" else {
                throw BrowseCatalogError.invalidURL
            }
            url = next
        } else {
            guard let built = BrowseRequestBuilder.scryfallSearchURL(query: query) else {
                throw BrowseCatalogError.invalidURL
            }
            url = built
        }
        let (data, response) = try await magicSession.data(for: request(url, scryfall: true))
        let retrievedAt = Date.now
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            return MagicCardsPageResult(
                page: CatalogPage(items: [], nextCursor: nil),
                prices: [:]
            )
        }
        try validate(response)
        let page = try JSONDecoder().decode(ScryfallBrowseCardPage.self, from: data)
        let directory = try await sets(for: .magic)
        var prices: [String: CatalogCachedPrice] = [:]
        let items = page.data.compactMap { card -> CatalogCardSummary? in
            let id = CatalogSetID(game: .magic, providerID: card.setCode.lowercased())
            guard let set = directory.first(where: { $0.catalogID == id }) else { return nil }
            let evidence = card.magicTreatmentEvidence
            let summary = CatalogCardSummary(
                game: .magic,
                providerID: card.id,
                setID: id,
                setName: set.name,
                setCode: set.code,
                name: card.name,
                collectorNumber: card.collectorNumber,
                thumbnailURL: card.thumbnailImageURL,
                imageURL: card.displayImageURL,
                magicTreatmentIDsRaw: MagicTreatmentKeyCodec.storedIDs(
                    from: evidence.treatments
                ),
                magicTreatmentQualifiers: evidence.qualifiers,
                magicFinishIDs: card.finishes
            )
            detailCache[detailCacheKey(for: summary)] = CatalogCardDetails(
                card: .magic(card), set: set, retrievedAt: retrievedAt
            )
            let amount = CardPricing.highestPublishedUSDPrice(for: .magic(card))
            prices[summary.id] = CatalogCachedPrice(
                value: amount,
                confirmsNoUSDQuote: amount == nil,
                providerUpdatedAt: nil
            )
            return summary
        }
        return MagicCardsPageResult(
            page: CatalogPage(
                items: items,
                nextCursor: page.hasMore ? page.nextPage?.absoluteString : nil
            ),
            prices: prices
        )
    }

    private func pokemonSet(id: String) async throws -> TCGdexSetCatalog {
        let key = id.lowercased()
        if let cached = pokemonSetDetails[key] {
            try await validatePokemonProviderSet(cached, requestedID: id)
            return cached
        }
        let task: Task<TCGdexSetCatalog, Error>
        if let pending = pokemonSetTasks[key] { task = pending }
        else {
            task = Task { try await pokemonTransport.fetchSet(id: id) }
            pokemonSetTasks[key] = task
        }
        defer { pokemonSetTasks[key] = nil }
        let loaded = try await awaitDetailTask(task)
        try await validatePokemonProviderSet(loaded, requestedID: id)
        pokemonSetDetails[key] = loaded
        return loaded
    }

    private func validatePokemonProviderSet(
        _ provider: TCGdexSetCatalog,
        requestedID: String
    ) async throws {
        guard provider.id.caseInsensitiveCompare(requestedID) == .orderedSame else {
            throw BrowseCatalogError.unknownSet
        }
        guard await pokemonSetIsAuthorized(requestedID) else {
            throw BrowseCatalogError.unknownSet
        }
        guard catalogCoordinator != nil,
              let descriptor = catalogRegistry.descriptor(forProviderSetID: requestedID),
              descriptor.recognitionKind == .expansion,
              let expected = descriptor.officialCount else { return }
        guard provider.cardCount?.official == expected else {
            throw BrowseCatalogError.providerCountMismatch(
                setID: requestedID,
                expected: expected,
                received: provider.cardCount?.official
            )
        }
    }

    private func livePokemonSummaries(for set: CatalogSet) async throws -> [CatalogCardSummary] {
        let provider = try await pokemonSet(id: set.providerID)
        let details = try await pokemonCardDetails(for: provider)
        let built = try PokemonMasterSetChecklistBuilder.build(
            providerSet: provider,
            baseSet: set,
            cardDetails: details.cards
        )
        var displayedCards: [CatalogCardSummary] = []
        for value in built {
            let summaries = Self.applyingSignedCardArtwork(value.cards, set: value.set)
            for summary in summaries {
                guard let card = details.cards[summary.providerID],
                      let retrievedAt = details.retrievedAt[summary.providerID] else { continue }
                detailCache[detailCacheKey(for: summary)] = CatalogCardDetails(
                    card: .pokemon(card.applyingAdditionalVariants(from: catalogRegistry), setCode: summary.setCode),
                    set: value.set,
                    retrievedAt: retrievedAt
                )
            }
            if value.set.id == set.id {
                displayedCards = summaries
            }
        }
        return PokemonChecklistReviewedProjection.addingAdditionalVariants(
            to: PokemonReviewedArtworkCatalog.projecting(displayedCards), registry: catalogRegistry)
    }

    private func pokemonCardDetails(
        for provider: TCGdexSetCatalog
    ) async throws -> (cards: [String: TCGdexCard], retrievedAt: [String: Date]) {
        // A changed provider card list must never reuse details fetched for the
        // previous list. This also lets an active refresh replace a stale card
        // without requiring a new catalog instance.
        let key = provider.id.lowercased()
            + "|"
            + PokemonMasterSetChecklistBuilder.providerProbeFingerprint(of: provider)
        if let cached = pokemonSetCardDetails[key] { return cached }

        var iterator = provider.cards.makeIterator()
        var details: [String: TCGdexCard] = [:]
        var retrievedAt: [String: Date] = [:]
        try await withThrowingTaskGroup(of: (String, TCGdexCard).self) { group in
            for _ in 0..<min(8, provider.cards.count) {
                guard let brief = iterator.next() else { break }
                group.addTask { (brief.id, try await self.pokemonTransport.fetchCard(id: brief.id)) }
            }
            while let value = try await group.next() {
                details[value.0] = value.1
                retrievedAt[value.0] = .now
                if let brief = iterator.next() {
                    group.addTask { (brief.id, try await self.pokemonTransport.fetchCard(id: brief.id)) }
                }
            }
        }
        guard details.count == provider.cards.count else {
            throw PokemonChecklistError.incompleteProviderSet(provider.id)
        }
        pokemonSetCardDetails[key] = (details, retrievedAt)
        return (details, retrievedAt)
    }

    private func loadPokemonSnapshotIfNeeded() async {
        while !pokemonSnapshotLoaded {
            let generation = pokemonSnapshotGeneration
            let registry = catalogRegistry
            let loadTask: Task<[PokemonChecklistSnapshotEntry], Never>
            if let existing = pokemonSnapshotLoadTask {
                loadTask = existing
            } else {
                let task = Task { [checklistStore] in await checklistStore.mergedEntries() }
                pokemonSnapshotLoadTask = task
                loadTask = task
            }

            var entries = await loadTask.value
            for index in entries.indices {
                let entry = entries[index]
                guard registry.descriptor(forProviderSetID: entry.providerID)?.additionalVariants?.isEmpty == false,
                      let cards = await checklistStore.mergedChecklist(for: entry.set.catalogID) else { continue }
                entries[index] = PokemonChecklistReviewedProjection.entry(entry, cards:
                    PokemonChecklistReviewedProjection.addingAdditionalVariants(to: cards, registry: registry))
            }
            let ranks = await checklistStore.bundledSetRanks()
            let visibleEntries = await visibleSnapshotEntries(entries)
            guard !Task.isCancelled else { return }
            guard generation == pokemonSnapshotGeneration else { continue }
            pokemonSnapshotLoadTask = nil
            guard !pokemonSnapshotLoaded else { return }
            pokemonBundledRanks = ranks
            pokemonSnapshotLoaded = !visibleEntries.isEmpty
            pokemonSnapshotEntries = visibleEntries
            if !visibleEntries.isEmpty { setCache[.pokemon] = pokemonSets(from: visibleEntries) }
            return
        }
    }

    /// How a crawl ended, which is what decides the next one's cadence.
    private enum PokemonSnapshotRefreshOutcome {
        /// Reached the end of the directory with nothing outstanding.
        case sweptCleanly
        /// Reached the end of the directory with sets still failing.
        case sweptWithFailures
        /// Could not start: the set directory itself was unreachable.
        case directoryUnavailable
        /// The user left. Per-set progress is already durable, and nothing was
        /// learned about the provider, so this must not arm any backoff.
        case cancelled
    }

    private func refreshPokemonSnapshot() async {
        switch await performPokemonSnapshotRefresh() {
        case .sweptCleanly:
            await checklistStore.markRefreshSucceeded()
        case .sweptWithFailures:
            await checklistStore.markRefreshSwept()
        case .directoryUnavailable:
            await checklistStore.markRefreshAttempted()
        case .cancelled:
            break
        }
    }

    private func performPokemonSnapshotRefresh() async -> PokemonSnapshotRefreshOutcome {
        do {
            let installed = await checklistStore.signedProviderFingerprints()
            let desired = signedProviderFingerprints()
            if !desired.isEmpty, desired.count == catalogRegistry.descriptors.count,
               desired.allSatisfy({ installed[$0.key] == $0.value }) { return .sweptCleanly }
            let rows = try await pokemonTransport.fetchSetDirectory()
            // Filter before deriving display metadata: provider-only discovery
            // rows never enter this refresh and must not report placeholder gaps.
            let authorizedRows = rows.filter {
                guard catalogCoordinator != nil else { return true }
                let id = $0.id.lowercased()
                guard let descriptor = catalogRegistry.descriptor(forProviderSetID: id) else { return false }
                return installed[id] == nil || installed[id] != descriptor.providerFingerprint
            }
            let authorizedSets = PokemonMasterSetChecklistBuilder.baseSets(
                from: authorizedRows,
                registry: catalogCoordinator == nil ? nil : catalogRegistry
            )
            let orderedSets = authorizedSets.sorted(by: refreshOrder)
            var workingEntries = pokemonSnapshotEntries
            // The cursor is an optimisation for an interrupted crawl, not a
            // permanent position. Once the last completed sweep has aged past
            // the refresh interval the whole directory is re-checked, so a set
            // that fails every time cannot hold the cursor at the end and stop
            // every other set from ever being looked at again.
            let needsFullSweep = await checklistStore.needsFullSweep()
            let resumeAfterProviderID = needsFullSweep
                ? nil
                : await checklistStore.refreshResumeAfterProviderID()
            let failedProviderIDs = await checklistStore.refreshFailedProviderIDs()
            let reconciliationProviderSetIDs = await checklistStore.reconciliationProviderSetIDs()
            let resumeIndex = resumeAfterProviderID.flatMap { resumeID in
                orderedSets.firstIndex {
                    $0.providerID.caseInsensitiveCompare(resumeID) == .orderedSame
                }
            }
            let firstIndex = resumeIndex.map { $0 + 1 } ?? 0
            let knownFailedIDs = Set(
                failedProviderIDs.filter { failedID in
                    !reconciliationProviderSetIDs.contains(failedID)
                        && orderedSets.contains {
                            $0.providerID.caseInsensitiveCompare(failedID) == .orderedSame
                        }
                }
            )
            var unresolvedFailureIDs = knownFailedIDs

            // Resume the ordinary cursor first. A failure from an earlier
            // portion of the directory is retried only after the resumed
            // work, so it cannot rewind the cursor or monopolize the next
            // crawl's first request.
            let setsToProcess: [CatalogSet] = orderedSets.enumerated().compactMap { pair in
                let index = pair.offset
                let set = pair.element
                guard index >= firstIndex,
                      !reconciliationProviderSetIDs.contains(set.providerID.lowercased()) else {
                    return nil
                }
                return set
            }
            let deferredRetrySets: [CatalogSet] = orderedSets.enumerated().compactMap { pair in
                let index = pair.offset
                let set = pair.element
                guard index < firstIndex,
                      !reconciliationProviderSetIDs.contains(set.providerID.lowercased()),
                      knownFailedIDs.contains(set.providerID.lowercased()) else {
                    return nil
                }
                return set
            }
            let deferredRetryIDs = Set(deferredRetrySets.map { $0.providerID.lowercased() })

            // Each iteration is its own commit. Set-level crawling is
            // intentionally sequential: it preserves deterministic release
            // ordering and makes each manifest update the only writer while
            // still keeping the card-detail stage 8-wide within a set. This is
            // the deliberate incrementality trade-off for refreshes.
            for baseSet in setsToProcess + deferredRetrySets {
                guard !Task.isCancelled else { return .cancelled }
                let isDeferredRetry = deferredRetryIDs.contains(baseSet.providerID.lowercased())
                do {
                    let provider = try await pokemonTransport.fetchSet(id: baseSet.providerID)
                    try await validatePokemonProviderSet(provider, requestedID: baseSet.providerID)
                    pokemonSetDetails[provider.id.lowercased()] = provider
                    let probeFingerprint = PokemonMasterSetChecklistBuilder.providerProbeFingerprint(of: provider)
                    let priorEntries = workingEntries.filter {
                        $0.providerID.caseInsensitiveCompare(baseSet.providerID) == .orderedSame
                            && $0.providerProbeFingerprint == probeFingerprint
                    }
                    let expectedSetCount = PokemonMasterSetDefinition.virtualSets(
                        baseSet,
                        cardCount: provider.cardCount
                    ).count
                    var priorChecklistsAreAvailable = priorEntries.count == expectedSetCount
                    if priorChecklistsAreAvailable {
                        for entry in priorEntries {
                            if !(await checklistStore.hasMergedChecklist(for: entry.set.catalogID)) {
                                priorChecklistsAreAvailable = false
                                break
                            }
                        }
                    }
                    if priorChecklistsAreAvailable {
                        unresolvedFailureIDs.remove(baseSet.providerID.lowercased())
                        await checklistStore.recordRefreshProgress(
                            after: baseSet.providerID,
                            advancesCursor: !isDeferredRetry
                        )
                        continue
                    }

                    let details = try await pokemonCardDetails(for: provider)
                    let providerSets = try PokemonMasterSetChecklistBuilder.build(
                        providerSet: provider,
                        baseSet: baseSet,
                        cardDetails: details.cards
                    )
                    guard !providerSets.isEmpty else {
                        unresolvedFailureIDs.remove(baseSet.providerID.lowercased())
                        await checklistStore.recordRefreshProgress(
                            after: baseSet.providerID,
                            advancesCursor: !isDeferredRetry
                        )
                        continue
                    }
                    let setSnapshot = PokemonChecklistSnapshot.from(builtSets: providerSets)

                    // This is the per-set commit point. The store writes all
                    // resource files before replacing its manifest.
                    try await checklistStore.publish(setSnapshot)
                    guard !Task.isCancelled else { return .cancelled }

                    workingEntries = await checklistStore.mergedEntries()
                    let visibleEntries = await visibleSnapshotEntries(workingEntries)
                    pokemonSnapshotEntries = visibleEntries
                    pokemonSnapshotLoaded = !visibleEntries.isEmpty
                    let sets = pokemonSets(from: visibleEntries)
                    setCache[.pokemon] = sets
                    yieldUpdate(game: .pokemon, revision: catalogRevision, providerSetID: baseSet.providerID)
                    unresolvedFailureIDs.remove(baseSet.providerID.lowercased())
                    await checklistStore.recordRefreshProgress(
                        after: baseSet.providerID,
                        advancesCursor: !isDeferredRetry
                    )
                } catch is CancellationError {
                    return .cancelled
                } catch {
                    // A refresh is opportunistic. One malformed or unavailable
                    // set must not prevent already completed sets from helping.
                    unresolvedFailureIDs.insert(baseSet.providerID.lowercased())
                    await checklistStore.recordRefreshProgress(
                        after: baseSet.providerID,
                        failed: true,
                        advancesCursor: !isDeferredRetry
                    )
                    continue
                }
            }
            guard !Task.isCancelled else { return .cancelled }
            return unresolvedFailureIDs.isEmpty ? .sweptCleanly : .sweptWithFailures
        } catch is CancellationError {
            return .cancelled
        } catch {
            // Directory failure is still all-or-nothing because there is no
            // trustworthy set ordering or universe to crawl without it.
            return .directoryUnavailable
        }
    }

    private func refreshOrder(_ lhs: CatalogSet, _ rhs: CatalogSet) -> Bool {
        let lhsOrder = catalogRegistry.releaseOrder(forProviderSetID: lhs.providerID)
        let rhsOrder = catalogRegistry.releaseOrder(forProviderSetID: rhs.providerID)
        switch (lhsOrder, rhsOrder) {
        case let (left?, right?):
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.sortRank > rhs.sortRank
        }
    }

    private func request(_ url: URL, scryfall: Bool = false) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .useProtocolCachePolicy
        if scryfall {
            request.setValue("TradingCardScanner/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        }
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BrowseCatalogError.badResponse
        }
    }

    private func assetURL(_ value: String?, suffix: String) -> URL? {
        value.flatMap { URL(string: $0 + suffix) }
    }

    private func escapedScryfall(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func deduplicated(_ values: [CatalogCardSummary]) -> [CatalogCardSummary] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }
    }
}

private struct SharedBrowseCatalogKey: EnvironmentKey {
    static let defaultValue: BrowseCatalog? = nil
}

extension EnvironmentValues {
    /// The app session's one Browse catalog, so detail routes reuse its warm
    /// caches instead of starting a catalog of their own.
    var sharedBrowseCatalog: BrowseCatalog? {
        get { self[SharedBrowseCatalogKey.self] }
        set { self[SharedBrowseCatalogKey.self] = newValue }
    }
}

/// App-private, local-only Browse cache.
///
/// The collection database is intentionally not used here: catalogue downloads
/// are disposable device state, not user inventory, and must never be uploaded
/// to CloudKit. Set directories are small and protected; viewed card/product
/// pages live under separate LRU byte caps.
actor CatalogCacheStore {
    struct Cached<Value: Sendable>: Sendable {
        let value: Value
        let storedAt: Date
        let isFresh: Bool
    }

    static let shared = CatalogCacheStore()

    static let setDirectoryMaxAge: TimeInterval = 24 * 60 * 60
    private static let sealedSetDirectoryMaxAge: TimeInterval = 7 * 24 * 60 * 60
    private static let sealedProductMaxAge: TimeInterval = 6 * 60 * 60
    private static let sealedPagePrefix = "sealed-v2|"
    private static let magicCardPageMaxAge: TimeInterval = 24 * 60 * 60
    private static let sortPriceMaxAge: TimeInterval = 24 * 60 * 60
    private static let bulkPriceMaxAge: TimeInterval = 24 * 60 * 60
    private static let pokemonSecondarySetsMaxAge: TimeInterval = 24 * 60 * 60
    private static let pokemonBulkSetMatchMaxAge: TimeInterval = 30 * 24 * 60 * 60
    private static let pokemonMissingBulkSetMatchMaxAge: TimeInterval = 6 * 60 * 60
    private static let cardPageLimit = 25 * 1_024 * 1_024
    private static let sealedPageLimit = 10 * 1_024 * 1_024

    private let root: URL

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            self.root = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("BrowseCatalogCache", isDirectory: true)
        }
    }

    func sets(for game: CardGame, now: Date = .now) -> Cached<[CatalogSet]>? {
        if let current = load([CatalogSet].self, from: setDirectoryURL(for: game), maxAge: Self.setDirectoryMaxAge, now: now) {
            return current
        }
        guard game == .magic, let legacy = load([CatalogSet].self, from: legacyMagicSetDirectoryURL,
                                                maxAge: Self.setDirectoryMaxAge, now: now) else { return nil }
        return Cached(value: legacy.value, storedAt: legacy.storedAt, isFresh: false)
    }

    func storeSets(_ sets: [CatalogSet], for game: CardGame, at date: Date = .now) {
        store(sets, at: setDirectoryURL(for: game), storedAt: date)
    }

    func setArtwork(for id: CatalogSetID) -> Cached<CatalogSetArtwork>? {
        load(CatalogSetArtwork.self, from: root.appendingPathComponent("SetArtwork")
            .appendingPathComponent(filename(for: "artwork-v2|" + id.id)), maxAge: 24 * 60 * 60)
    }

    func storeSetArtwork(_ artwork: CatalogSetArtwork, for id: CatalogSetID) {
        let directory = root.appendingPathComponent("SetArtwork", isDirectory: true)
        let bounded = CatalogSetArtwork(cardURLs: Array(artwork.cardURLs.prefix(3)),
                                        illustrationURLs: Array(artwork.illustrationURLs.prefix(3)))
        store(bounded, at: directory.appendingPathComponent(filename(for: "artwork-v2|" + id.id)))
        trim(directory, maximumBytes: 1 * 1_024 * 1_024)
    }

    func removeSets(for game: CardGame) {
        try? FileManager.default.removeItem(at: setDirectoryURL(for: game))
        if game == .magic { try? FileManager.default.removeItem(at: legacyMagicSetDirectoryURL) }
    }

    func cardPage(for key: String) -> Cached<CatalogPage<CatalogCardSummary>>? {
        let url = cardPagesDirectory.appendingPathComponent(filename(for: key))
        guard let cached = load(
            CatalogPage<CatalogCardSummary>.self,
            from: url,
            maxAge: Self.magicCardPageMaxAge
        ) else {
            return nil
        }
        touch(url)
        return cached
    }

    func storeCardPage(_ page: CatalogPage<CatalogCardSummary>, for key: String) {
        store(page, at: cardPagesDirectory.appendingPathComponent(filename(for: key)))
        trim(cardPagesDirectory, maximumBytes: Self.cardPageLimit)
    }

    /// The decoded Scryfall page contains exact-printing prices, but the
    /// summary page deliberately does not. Keep those ordering answers beside
    /// the page so reopening a disk-cached Magic set does not turn into one
    /// detail request per card.
    func magicPrices(for cardPageKey: String) -> Cached<[String: CatalogCachedPrice]>? {
        let url = magicPricesDirectory.appendingPathComponent(filename(for: cardPageKey))
        guard let cached = load(
            [String: CatalogCachedPrice].self,
            from: url,
            maxAge: Self.magicCardPageMaxAge
        ) else {
            return nil
        }
        touch(url)
        return cached
    }

    func storeMagicPrices(
        _ prices: [String: CatalogCachedPrice],
        for cardPageKey: String
    ) {
        store(
            prices,
            at: magicPricesDirectory.appendingPathComponent(filename(for: cardPageKey))
        )
        trim(magicPricesDirectory, maximumBytes: Self.cardPageLimit)
    }

    func pokemonBulkPrices(for setID: String) -> Cached<PokemonBulkPriceMap>? {
        let url = pokemonBulkPricesDirectory.appendingPathComponent(
            filename(for: "pokemon-bulk-prices|\(setID.lowercased())")
        )
        guard let cached = load(
            PokemonBulkPriceMap.self,
            from: url,
            maxAge: Self.bulkPriceMaxAge
        ) else {
            return nil
        }
        touch(url)
        return cached
    }

    func storePokemonBulkPrices(_ prices: PokemonBulkPriceMap, for setID: String) {
        store(
            prices,
            at: pokemonBulkPricesDirectory.appendingPathComponent(
                filename(for: "pokemon-bulk-prices|\(setID.lowercased())")
            )
        )
        trim(pokemonBulkPricesDirectory, maximumBytes: 10 * 1_024 * 1_024)
    }

    func invalidatePokemonPricing(for setIDs: Set<String>) {
        guard !setIDs.isEmpty else { return }
        for setID in setIDs {
            let normalized = setID.lowercased()
            let bulkURL = pokemonBulkPricesDirectory.appendingPathComponent(
                filename(for: "pokemon-bulk-prices|\(normalized)")
            )
            let matchURL = pokemonBulkSetMatchesDirectory.appendingPathComponent(
                filename(for: "pokemon-bulk-set-match|\(normalized)")
            )
            try? FileManager.default.removeItem(at: bulkURL)
            try? FileManager.default.removeItem(at: matchURL)
        }
        try? FileManager.default.removeItem(at: pokemonSecondarySetsURL)
    }

    func pokemonSecondarySets() -> Cached<[PokemonCatalogSecondarySet]>? {
        load(
            [PokemonCatalogSecondarySet].self,
            from: pokemonSecondarySetsURL,
            maxAge: Self.pokemonSecondarySetsMaxAge
        )
    }

    func storePokemonSecondarySets(_ sets: [PokemonCatalogSecondarySet]) {
        store(sets, at: pokemonSecondarySetsURL)
    }

    func pokemonBulkSetMatch(for setID: String) -> Cached<PokemonBulkSetMatch>? {
        let url = pokemonBulkSetMatchesDirectory.appendingPathComponent(
            filename(for: "pokemon-bulk-set-match|\(setID.lowercased())")
        )
        guard let cached = load(
            PokemonBulkSetMatch.self,
            from: url,
            maxAge: nil
        ) else {
            return nil
        }
        touch(url)
        let maxAge = cached.value.secondarySetID == nil
            ? Self.pokemonMissingBulkSetMatchMaxAge
            : Self.pokemonBulkSetMatchMaxAge
        let age = Date.now.timeIntervalSince(cached.storedAt)
        return Cached(
            value: cached.value,
            storedAt: cached.storedAt,
            isFresh: age >= 0 && age < maxAge
        )
    }

    func storePokemonBulkSetMatch(_ match: PokemonBulkSetMatch, for setID: String) {
        store(
            match,
            at: pokemonBulkSetMatchesDirectory.appendingPathComponent(
                filename(for: "pokemon-bulk-set-match|\(setID.lowercased())")
            )
        )
        trim(pokemonBulkSetMatchesDirectory, maximumBytes: 1 * 1_024 * 1_024)
    }

    /// Sort prices are disposable ordering hints. They are never used as
    /// observation history, a checked-at value, or a price record.
    func sortPrices(for setID: String) -> Cached<[String: SortPriceHint]>? {
        let url = sortPricesDirectory.appendingPathComponent(
            filename(for: "sortprices-v2|\(setID)")
        )
        guard let cached = load(
            [String: SortPriceHint].self,
            from: url,
            maxAge: Self.sortPriceMaxAge
        ) else {
            return nil
        }
        touch(url)
        return cached
    }

    func storeSortPrices(_ prices: [String: SortPriceHint], for setID: String) {
        store(
            prices,
            at: sortPricesDirectory.appendingPathComponent(
                filename(for: "sortprices-v2|\(setID)")
            )
        )
        trim(sortPricesDirectory, maximumBytes: 5 * 1_024 * 1_024)
    }

    func sealedSets(for game: CardGame) -> Cached<[SealedSetSummary]>? {
        load([SealedSetSummary].self, from: sealedSetDirectoryURL(for: game), maxAge: Self.sealedSetDirectoryMaxAge)
    }

    func storeSealedSets(_ sets: [SealedSetSummary], for game: CardGame) {
        store(sets, at: sealedSetDirectoryURL(for: game))
    }

    func sealedProductPage(for key: String) -> Cached<CatalogPage<SealedProductSummary>>? {
        let url = sealedPagesDirectory.appendingPathComponent(filename(for: key))
        if let cached = load(CatalogPage<SealedProductSummary>.self, from: url, maxAge: Self.sealedProductMaxAge) {
            touch(url)
            return cached
        }
        // Older pages advanced by visible row count. Keep their products
        // available offline, but refresh before trusting their continuation.
        guard key.hasPrefix(Self.sealedPagePrefix) else { return nil }
        let legacyKey = "sealed|" + key.dropFirst(Self.sealedPagePrefix.count)
        let legacyURL = sealedPagesDirectory.appendingPathComponent(filename(for: legacyKey))
        guard let legacy = load(CatalogPage<SealedProductSummary>.self, from: legacyURL,
                                maxAge: Self.sealedProductMaxAge) else { return nil }
        touch(legacyURL)
        return Cached(value: CatalogPage(items: legacy.value.items, nextCursor: nil),
                      storedAt: legacy.storedAt,
                      isFresh: legacy.value.nextCursor == nil && legacy.isFresh)
    }

    func storeSealedProductPage(_ page: CatalogPage<SealedProductSummary>, for key: String) {
        store(page, at: sealedPagesDirectory.appendingPathComponent(filename(for: key)))
        trim(sealedPagesDirectory, maximumBytes: Self.sealedPageLimit)
    }

    static func cardPageKey(for set: CatalogSet, cursor: String?) -> String {
        if set.game == .magic { return "magic-printings-v2|\(set.id)|\(cursor ?? "initial")" }
        return "cards|schema:\(PokemonChecklistSnapshotVersion.schema)|rules:\(PokemonChecklistSnapshotVersion.masterSetRules)|\(set.id)|\(cursor ?? "initial")"
    }

    static func legacyMagicInitialPageKey(for set: CatalogSet) -> String {
        "cards|schema:1|rules:1|\(set.id)|initial"
    }

    static func sealedPageKey(game: CardGame, setID: String?, query: String?, offset: Int) -> String {
        "\(sealedPagePrefix)\(game.rawValue)|\(setID ?? "all")|\(query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "")|\(offset)"
    }

    private var cardPagesDirectory: URL { root.appendingPathComponent("CardPages", isDirectory: true) }
    private var magicPricesDirectory: URL { root.appendingPathComponent("MagicPrices", isDirectory: true) }
    private var pokemonBulkPricesDirectory: URL { root.appendingPathComponent("PokemonBulkPrices", isDirectory: true) }
    private var pokemonSecondarySetsURL: URL { root.appendingPathComponent("PokemonSecondarySets.json") }
    private var pokemonBulkSetMatchesDirectory: URL {
        root.appendingPathComponent("PokemonBulkSetMatches", isDirectory: true)
    }
    private var sealedPagesDirectory: URL { root.appendingPathComponent("SealedPages", isDirectory: true) }
    private var sortPricesDirectory: URL { root.appendingPathComponent("SortPrices", isDirectory: true) }
    private var legacyMagicSetDirectoryURL: URL { root.appendingPathComponent("Sets-magic.json") }

    private func setDirectoryURL(for game: CardGame) -> URL {
        root.appendingPathComponent(game == .magic ? "Sets-magic-v2.json" : "Sets-\(game.rawValue).json")
    }

    private func sealedSetDirectoryURL(for game: CardGame) -> URL {
        root.appendingPathComponent("SealedSets-\(game.rawValue).json")
    }

    private func load<Value: Codable & Sendable>(
        _ type: Value.Type,
        from url: URL,
        maxAge: TimeInterval?,
        now: Date = .now
    ) -> Cached<Value>? {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(CacheEnvelope<Value>.self, from: data) else {
            return nil
        }
        let isFresh = maxAge.map {
            let age = now.timeIntervalSince(envelope.storedAt)
            return age >= 0 && age < $0
        } ?? true
        return Cached(value: envelope.value, storedAt: envelope.storedAt, isFresh: isFresh)
    }

    private func store<Value: Codable & Sendable>(_ value: Value, at url: URL, storedAt: Date = .now) {
        let directory = url.deletingLastPathComponent()
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil,
              let data = try? JSONEncoder().encode(CacheEnvelope(storedAt: storedAt, value: value)) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: url.path)
    }

    private func trim(_ directory: URL, maximumBytes: Int) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }

        let files = urls.compactMap { url -> (url: URL, size: Int, date: Date)? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.date < $1.date }

        var total = files.reduce(0) { $0 + $1.size }
        for file in files where total > maximumBytes {
            guard (try? FileManager.default.removeItem(at: file.url)) != nil else { continue }
            total -= file.size
        }
    }

    private func filename(for key: String) -> String {
        // Stable FNV-1a avoids putting long, provider-supplied cursors directly
        // into filesystem paths while keeping cache keys deterministic.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16) + ".json"
    }
}

private struct CacheEnvelope<Value: Codable>: Codable {
    let storedAt: Date
    let value: Value
}

enum PokemonMasterSetDefinition {
    /// The English sets that were actually printed in two runs, by TCGdex set id.
    ///
    /// Keyed by id rather than by name because names vary between TCGdex and the
    /// printed product — "Expedition" and "Expedition Base Set" needed two
    /// entries in the name-matched version — while ids do not.
    ///
    /// This is a closed historical fact, not a heuristic to keep current: the
    /// 1st Edition stamp ran from Base Set to Neo Destiny and was never used
    /// again, so nothing will ever join this list. Verified against TCGdex's own
    /// `cardCount.firstEd`, which is non-zero for these ten sets and
    /// zero for Base Set 2, Legendary Collection and the whole e-card era.
    ///
    /// The e-card sets used to be listed here, which invented a "Skyridge — 1st
    /// Edition" master set that never existed, split the real set's completion
    /// across two impossible halves, and then asked the price vendor for a
    /// printing no marketplace carries.
    private static let firstEditionSetIDs: Set<String> = [
        "base1", "base2", "base3", "base5",
        "gym1", "gym2",
        "neo1", "neo2", "neo3", "neo4"
    ]

    /// Base Set alone had a third run: the shadowless print that sits between
    /// 1st Edition and the shadowed Unlimited cards.
    private static let shadowlessSetID = "base1"

    static func virtualSets(
        _ set: CatalogSet,
        cardCount: TCGdexCardCount? = nil
    ) -> [CatalogSet] {
        guard set.game == .pokemon else { return [set] }
        let runs = printRuns(forSetProviderID: set.providerID)
        guard !runs.isEmpty else {
            // One run, so no qualifier: the set stands as itself rather than
            // being relabelled "— Unlimited" against nothing.
            return [set]
        }
        return runs.map { run in
            CatalogSet(
                catalogID: CatalogSetID(
                    game: .pokemon,
                    providerID: set.providerID,
                    pokemonPrintRun: run
                ),
                name: "\(set.name) — \(run.label)",
                code: set.code,
                logoURL: set.logoURL,
                symbolURL: set.symbolURL,
                cardCount: cardCount.map {
                    masterCount(cardCount: $0, setName: set.name, printRun: run)
                } ?? set.cardCount.map {
                    adjustedCount($0, setName: set.name, printRun: run)
                },
                releaseDate: set.releaseDate,
                sortRank: set.sortRank,
                bundledArtworkSourceID: set.bundledArtworkSourceID,
                artworkFallbackURLs: set.artworkFallbackURLs,
                limitlessArtworkAuthorized: set.limitlessArtworkAuthorized,
                cardArtwork: set.cardArtwork
            )
        }
    }

    /// Whether this set was printed in more than one run.
    ///
    /// Public so the collection can repair rows tagged with a run their set
    /// never had, from when the e-card sets were split.
    static func hasSeparatePrintRuns(setProviderID: String) -> Bool {
        !printRuns(forSetProviderID: setProviderID).isEmpty
    }

    /// The single source of truth for every UI that must ask which physical run
    /// a card belongs to. An empty result means there is no question to ask.
    static func printRuns(forSetProviderID setProviderID: String) -> [PokemonPrintRun] {
        let id = setProviderID.lowercased()
        if id == shadowlessSetID {
            return [.firstEdition, .shadowless, .unlimited]
        }
        if firstEditionSetIDs.contains(id) {
            return [.firstEdition, .unlimited]
        }
        return []
    }

    static func printRuns(for card: IdentifiedCard) -> [PokemonPrintRun] {
        guard case let .pokemon(payload, _) = card.legacyIdentity else { return [] }
        return printRuns(forSetProviderID: payload.set.id).filter {
            !excludes(localID: payload.localId, setProviderID: payload.set.id, printRun: $0)
        }
    }

    static func includesInSetDirectory(_ set: TCGdexBrowseSet) -> Bool {
        let name = CatalogIdentityNormalization.canonicalText(set.name)
        let id = set.id.lowercased()
        if ["basep", "swshp", "svp", "rc", "sp", "wp"].contains(id) { return false }
        let excludedPhrases = [
            "black star promo", "promos", "promo cards", "pop series",
            "jumbo", "miscellaneous cards", "battle academy", "deck exclusives",
            "trainer kit", "mcdonald s", "southern islands", "box topper"
        ]
        return !excludedPhrases.contains { name.contains($0) }
    }

    /// TCGdex publishes variation counts directly. Normal plus holo is the
    /// pack-pulled base run (including secrets); reverse is the additional full
    /// parallel. `total` is the fallback when an older set response omits the
    /// variation breakdown.
    static func masterCount(
        cardCount: TCGdexCardCount,
        setName: String,
        printRun: PokemonPrintRun?
    ) -> Int {
        let publishedBase: Int
        let breakdown = (cardCount.normal ?? 0)
            + (cardCount.holo ?? 0)
            + (cardCount.reverse ?? 0)
        publishedBase = breakdown > 0
            ? (cardCount.normal ?? 0) + (cardCount.holo ?? 0)
            : cardCount.total
        let base = printRun == .firstEdition
            ? (cardCount.firstEd ?? publishedBase)
            : publishedBase
        return adjustedCount(
            base + (cardCount.reverse ?? 0),
            setName: setName,
            printRun: printRun
        )
    }

    static func excludes(
        localID: String,
        setProviderID: String,
        printRun: PokemonPrintRun?
    ) -> Bool {
        // Every English Base Set Machamp is stamped. There is no distinct
        // Unlimited printing, so it cannot complete the Unlimited run.
        setProviderID.caseInsensitiveCompare("base1") == .orderedSame
            && printRun == .unlimited
            && CatalogIdentityNormalization.localNumber(localID) == "8"
    }

    /// The required physical slots for one numbered card. Edition is carried
    /// separately by the virtual set, so the legacy first-edition pseudo-finish
    /// never becomes a second slot. Master includes booster-pack parallels;
    /// Grand Master adds cataloged promotional/product-exclusive printings.
    static func requiredVariants(
        for card: TCGdexCard
    ) -> [(variant: PhysicalVariant, isExpanded: Bool, isSole: Bool)] {
        let variants = PokemonVariantRules.apply(to: VariantEvidence(
            game: .pokemon, setID: card.set.id, cardNumber: card.localId,
            catalogVariants: card.catalogVariants
        )).variants.filter {
            $0.id != PhysicalVariant.firstEdition.id
        }
        // Preserve retained memberships that still need product review in the
        // checklist. The resolver separately exposes supported choices only.
        let retained = PokemonFinishMinimumCatalog.minimum(cardID: card.id) == nil ? variants
            : PokemonFinishMinimumCatalog.retainingMinimum(cardID: card.id, variants: card.catalogVariants)
        return requiredSlots(for: retained, setProviderID: card.set.id)
    }

    static func requiredSlots(for variants: [PhysicalVariant], setProviderID: String? = nil) -> [(variant: PhysicalVariant, isExpanded: Bool, isSole: Bool)] {
        var seen = Set<String>()
        // Oversized objects can be collected from a scan, but do not add a
        // standard-size Master/Grand Master checklist requirement.
        let slots = variants.filter { $0 != .jumbo && seen.insert($0.id).inserted }
        return slots.map { variant in
            return (variant, !isPackVariant(variant, setProviderID: setProviderID), slots.count == 1)
        }
    }

    /// A finish name alone cannot establish pack provenance for arbitrary new
    /// patterns. Unknown patterns stay in Grand Master until reviewed. Stamped
    /// versions have their own IDs and never inherit their base finish's scope.
    static func isPackVariant(_ variant: PhysicalVariant, setProviderID: String? = nil) -> Bool {
        if isPackReversePattern(variant, setProviderID: setProviderID) { return true }
        // Pokémon GO's numbered Bidoof includes both ordinary Reverse and the
        // peelable Ditto object. Qualified identity must not demote pack cards.
        if setProviderID?.lowercased() == "swsh10.5",
           [PokemonReviewedPhysicalObjects.plainReverse, PokemonReviewedPhysicalObjects.peelableDitto].contains(variant) {
            return true
        }
        switch variant.id {
        case "normal", "holo", "reverse", "pokeBall", "masterBall",
             "duskBall", "friendBall", "quickBall", "loveBall": return true
        case "energy": return ["ex5", "ex6", "me02.5"].contains(setProviderID?.lowercased() ?? "")
        case "team-rocket": return setProviderID?.lowercased() == "me02.5"
        case "tinsel": return ["sv10.5b", "sv10.5w", "sve"].contains(setProviderID?.lowercased() ?? "")
        default: return false
        }
    }

    static func isPackReversePattern(_ variant: PhysicalVariant, setProviderID: String?) -> Bool {
        let setID = setProviderID?.lowercased() ?? ""
        if variant.id == "energy", ["ex5", "ex6"].contains(setID) { return true }
        guard (7...16).contains(Int(setID.replacingOccurrences(of: "ex", with: "")) ?? 0),
              setID.hasPrefix("ex"), let stamp = PokemonCatalogStampVariant.decode(variant.id) else { return false }
        return stamp.stamps == ["set-logo"] && stamp.subtype == nil
    }

    /// Gold/rainbow often describe the already-numbered holo rare rather than
    /// a second object. The 151 Mew gold object also represents the UPC metal
    /// card and must remain separate. Collection IDs are never rewritten.
    static func rarityFinishAliasesHolo(_ variantID: String?, cardID: String) -> Bool {
        let setID = cardID.split(separator: "-").first.map(String.init) ?? ""
        return rarityFinishAliasSetIDs.contains(setID)
            && ["gold", "rainbow"].contains(variantID ?? "") && cardID != "sv03.5-205"
    }

    private static let rarityFinishAliasSetIDs: Set<String> = [
        "me02", "me04", "sv03.5", "sv05", "sv06", "sv06.5", "sv07", "sv08", "sv08.5", "sv09", "sv10",
        "swsh2", "swsh3", "swsh4", "swsh4.5", "swsh5", "swsh6", "swsh7", "swsh8", "swsh9",
        "swsh10", "swsh10.5", "swsh10tg", "swsh11", "swsh11tg", "swsh12", "swsh12tg"
    ]

    static func checklist(_ cards: [CatalogCardSummary]) -> [CatalogCardSummary] {
        let groups = Dictionary(grouping: cards, by: { $0.providerID })
        return cards.compactMap { original in
            guard original.game == .pokemon, let variant = original.masterSetVariant else { return original }
            let siblings = groups[original.providerID] ?? []
            let certified = PokemonFinishCoverage.variants(cardID: original.providerID) != nil
            if !certified, variant == .reverse, siblings.contains(where: {
                $0.masterSetVariant.map { isPackReversePattern($0, setProviderID: original.setID.providerID) } == true
            }) { return nil }
            if !certified, rarityFinishAliasesHolo(variant.id, cardID: original.providerID),
               siblings.contains(where: { $0.masterSetVariant == .holo }) { return nil }
            var card = original
            card.isExpandedMasterSetVariant = !(isPackVariant(variant, setProviderID: card.setID.providerID)
                || rarityFinishAliasesHolo(variant.id, cardID: card.providerID))
            // This non-holo Lugia is a stamped product printing, not a pack ex.
            if card.providerID == "sv08.5-082", variant == .normal { card.isExpandedMasterSetVariant = true }
            let retained = certified ? siblings : siblings.filter {
                let rarityAlias = rarityFinishAliasesHolo($0.masterSetVariant?.id, cardID: original.providerID)
                    && siblings.contains(where: { $0.masterSetVariant == .holo })
                let reverseAlias = $0.masterSetVariant == .reverse && siblings.contains(where: {
                    $0.masterSetVariant.map { isPackReversePattern($0, setProviderID: original.setID.providerID) } == true
                })
                return !rarityAlias && !reverseAlias
            }
            card.isSoleSlotForCard = retained.count == 1
            return card
        }
    }

    private static func adjustedCount(
        _ count: Int,
        setName: String,
        printRun: PokemonPrintRun?
    ) -> Int {
        // Base Set Unlimited is one card short: every English Machamp is
        // stamped, so there is no Unlimited printing of it to collect.
        CatalogIdentityNormalization.canonicalText(setName) == "base set"
            && printRun == .unlimited
            ? max(count - 1, 0)
            : count
    }
}

struct TCGdexBrowseSet: Decodable {
    let id: String
    let name: String
    let logo: String?
    let symbol: String?
    let cardCount: TCGdexCardCount?
    let tcgOnline: String?
}

private struct ScryfallBrowseSetList: Decodable { let data: [ScryfallBrowseSet] }
private struct ScryfallBrowseSet: Decodable {
    let code: String
    let name: String
    let digital: Bool
    let setType: String?
    let releasedAt: String?
    let cardCount: Int?
    let iconSVGURI: URL?

    enum CodingKeys: String, CodingKey {
        case code, name, digital
        case setType = "set_type"
        case releasedAt = "released_at"
        case cardCount = "card_count"
        case iconSVGURI = "icon_svg_uri"
    }
}

private struct ScryfallBrowseCardPage: Decodable {
    let data: [ScryfallCard]
    let hasMore: Bool
    let nextPage: URL?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}
