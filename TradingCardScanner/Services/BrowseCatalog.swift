import Foundation
import UIKit

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
            URLQueryItem(name: "order", value: "released"),
            URLQueryItem(name: "dir", value: "desc")
        ]
        return components?.url
    }
}

struct BrowseCatalogUpdate: Sendable, Equatable {
    let revision: Int?
    let providerSetID: String?
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
    private static let legacyReleaseOrderDefaultsKey = "pokemonCatalogReleaseOrder.v1"

    static func applyingSignedCardArtwork(
        _ summaries: [CatalogCardSummary],
        set: CatalogSet
    ) -> [CatalogCardSummary] {
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
        let task: Task<CatalogCardDetails, Error>
        var waiterIDs: Set<UUID>
    }

    private struct SortPriceSlot: Sendable {
        let id: String
        let price: Double?
        let resolved: Bool
    }

    private struct SortPriceGroupResult: Sendable {
        let slots: [SortPriceSlot]
    }

    private let scryfall = ScryfallService()
    private let cache: CatalogCacheStore
    private let pokemonTransport: any PokemonBrowseTransport
    private let checklistStore: PokemonChecklistStore
    private var setCache: [CardGame: [CatalogSet]] = [:]
    private var detailCache: [String: CatalogCardDetails] = [:]
    private var detailTasks: [String: DetailTaskState] = [:]
    private var pokemonSetDetails: [String: TCGdexSetCatalog] = [:]
    private var pokemonSetCardDetails: [String: [String: TCGdexCard]] = [:]
    private var pokemonSnapshotEntries: [PokemonChecklistSnapshotEntry] = []
    private var pokemonSnapshotLoaded = false
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
    private var refreshingSetDirectories: Set<CardGame> = []
    private var memoryWarningObserver: NSObjectProtocol?

    private let catalogCoordinator: PokemonCatalogCoordinator?
    private let magicCatalogCoordinator: MagicCatalogCoordinator?

    init(
        cache: CatalogCacheStore = .shared,
        pokemonTransport: any PokemonBrowseTransport = TCGdexBrowseTransport(),
        checklistStore: PokemonChecklistStore = .shared,
        catalogCoordinator: PokemonCatalogCoordinator? = nil,
        magicCatalogCoordinator: MagicCatalogCoordinator? = nil
    ) {
        // The old crawl-installed ordering map was unsigned and had no rollback
        // semantics. Remove it once on construction so upgrades cannot leave a
        // second ordering authority behind in UserDefaults.
        UserDefaults.standard.removeObject(forKey: Self.legacyReleaseOrderDefaultsKey)
        self.cache = cache
        self.pokemonTransport = pokemonTransport
        self.checklistStore = checklistStore
        self.catalogCoordinator = catalogCoordinator
        self.magicCatalogCoordinator = magicCatalogCoordinator
    }

    deinit {
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
        if let cached = setCache[game] { return cached }

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

        if let saved = await cache.sets(for: game) {
            setCache[game] = saved.value
            if !saved.isFresh { scheduleSetDirectoryRefresh(for: game) }
            return saved.value
        }
        return try await loadSetDirectory(for: game)
    }

    func invalidateSetCache(for game: CardGame) {
        guard game == .pokemon else {
            setCache[game] = nil
            if game == .magic, magicCatalogCoordinator != nil {
                Task { [cache] in await cache.removeSets(for: .magic) }
            }
            return
        }
        resetPokemonSnapshotCache()
        yieldUpdate(providerSetID: nil)
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
        }
        setCache[game] = loaded
        await cache.storeSets(loaded, for: game)
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
            _ = await coordinator.refresh()
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
        applyCatalogRegistry(
            await coordinator.registry,
            revision: await coordinator.revision
        )
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
        guard catalogRevision != revision
            || catalogRegistry.descriptors != registry.descriptors else { return }
        catalogRegistry = registry
        catalogRevision = revision
        resetPokemonSnapshotCache()
        yieldUpdate(providerSetID: nil)
    }

    private func startTargetedReconciliationIfNeeded() async {
        guard wantsCatalogRefresh else { return }
        let desired = signedProviderFingerprints()
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

    /// Reconciliation is state-derived and may be called from either the
    /// foreground preparation path or the activation-event fast path. The
    /// durable queue is re-derived first so lost in-memory events self-heal.
    private func reconcilePokemonProviderContent() async {
        guard !Task.isCancelled else { return }
        let desired = signedProviderFingerprints()
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
                cardDetails: details
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
            yieldUpdate(providerSetID: target.providerSetID)
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
        let code = descriptor.printedCode
            ?? descriptor.printedPrefix
            ?? providerSetID.uppercased()
        return CatalogSet(
            catalogID: CatalogSetID(game: .pokemon, providerID: providerSetID),
            name: descriptor.displayName ?? provider.name,
            code: code,
            logoURL: descriptor.logoURL.flatMap(URL.init(string:))
                ?? provider.logo.flatMap { URL(string: $0 + ".png") },
            symbolURL: descriptor.symbolURL.flatMap(URL.init(string:))
                ?? provider.symbol.flatMap { URL(string: $0 + ".png") },
            cardCount: provider.cardCount.map {
                PokemonMasterSetDefinition.masterCount(
                    cardCount: $0,
                    setName: provider.name,
                    printRun: nil
                )
            },
            releaseDate: descriptor.releaseDate.flatMap(FlexibleDate.parse),
            sortRank: descriptor.releaseOrder ?? 0,
            artworkFallbackURLs: descriptor.artworkFallbackURLs?.compactMap(URL.init(string:)),
            limitlessArtworkAuthorized: descriptor.recognitionKind == .expansion,
            cardArtwork: BrowseCatalogArtworkSelection.cardArtworkMap(descriptor: descriptor)
        )
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
        if magicCatalogCoordinator != nil {
            Task { [weak self, cache] in
                guard let self else { return }
                if await self.usesRemoteMagicAuthority() {
                    await cache.removeSets(for: .magic)
                }
            }
        }
        yieldUpdate(providerSetID: nil)
    }

    private func resetPokemonSnapshotCache() {
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

    private func yieldUpdate(providerSetID: String?) {
        let update = BrowseCatalogUpdate(
            revision: catalogRevision,
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
        let bundledIDs = await checklistStore.bundledProviderIDs()
        return entries.filter { entry in
            catalogRegistry.descriptor(forProviderSetID: entry.providerID) != nil
                || bundledIDs.contains(entry.providerID.lowercased())
        }
    }

    private func pokemonSets(
        from entries: [PokemonChecklistSnapshotEntry]
    ) -> [CatalogSet] {
        entries.map { entry in
            guard let descriptor = catalogRegistry.descriptor(forProviderSetID: entry.providerID) else {
                return entry.set
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
                sortRank: descriptor.releaseOrder ?? entry.set.sortRank,
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

    func cards(in set: CatalogSet, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
        installMemoryWarningObserverIfNeeded()
        if set.game == .pokemon {
            await synchronizeCatalogAuthority()
        }
        let page: CatalogPage<CatalogCardSummary>
        switch set.game {
        case .pokemon:
            await loadPokemonSnapshotIfNeeded()
            // Snapshot lookup deliberately precedes the ordinary page cache.
            // A bundled or protected checklist is the authoritative offline
            // source and must not be displaced by an older partial page.
            if let local = await checklistStore.mergedChecklist(for: set.catalogID) {
                return CatalogPage(
                    items: Self.applyingSignedCardArtwork(local, set: set),
                    nextCursor: nil
                )
            }
            let summaries = try await livePokemonSummaries(for: set)
            page = CatalogPage(items: summaries, nextCursor: nil)
        case .magic:
            let cacheKey = CatalogCacheStore.cardPageKey(for: set, cursor: cursor)
            if let saved = await cache.cardPage(for: cacheKey) {
                if saved.isFresh { return saved.value }
                do {
                    let refreshed = try await magicCards(
                        query: "e:\(set.providerID) lang:en game:paper",
                        cursor: cursor
                    )
                    await cache.storeCardPage(refreshed, for: cacheKey)
                    return refreshed
                } catch {
                    // A stale page is still useful offline. Keep it visible
                    // when revalidation cannot reach Scryfall, while the next
                    // visit will try again because the stored timestamp stays
                    // old until a successful refresh replaces it.
                    return saved.value
                }
            }
            page = try await magicCards(query: "e:\(set.providerID) lang:en game:paper", cursor: cursor)
            await cache.storeCardPage(page, for: cacheKey)
            return page
        }
        let cacheKey = CatalogCacheStore.cardPageKey(for: set, cursor: cursor)
        await cache.storeCardPage(page, for: cacheKey)
        return page
    }

    func searchCards(
        named query: String,
        game: CardGame,
        setIDs: Set<CatalogSetID>,
        cursor: String?
    ) async throws -> CatalogPage<CatalogCardSummary> {
        installMemoryWarningObserverIfNeeded()
        let normalized = CardNameSearch.normalize(query)
        guard normalized.count >= 2 else { return CatalogPage(items: [], nextCursor: nil) }

        switch game {
        case .pokemon:
            let selected = setIDs.filter { $0.game == .pokemon }
            if !selected.isEmpty {
                let directory = try await sets(for: .pokemon)
                var results: [CatalogCardSummary] = []
                for id in selected {
                    guard let set = directory.first(where: { $0.catalogID == id }) else { continue }
                    let page = try await cards(in: set, cursor: nil)
                    results.append(contentsOf: page.items.filter {
                        CardNameSearch.normalize($0.name).contains(normalized)
                    })
                }
                return CatalogPage(items: deduplicated(results), nextCursor: nil)
            }
            return try await searchPokemon(query: normalized, cursor: cursor)

        case .magic:
            let selected = setIDs.filter { $0.game == .magic }.map(\.providerID).sorted()
            let setClause = selected.isEmpty
                ? ""
                : " (\(selected.map { "e:\($0)" }.joined(separator: " or ")))"
            return try await magicCards(
                query: "name:\"\(escapedScryfall(query))\" lang:en game:paper\(setClause)",
                cursor: cursor
            )
        }
    }

    func details(for summary: CatalogCardSummary) async throws -> CatalogCardDetails {
        installMemoryWarningObserverIfNeeded()
        let key = detailCacheKey(for: summary)
        if let cached = detailCache[key] { return cached }

        let waiterID = UUID()
        let task: Task<CatalogCardDetails, Error>
        if var state = detailTasks[key] {
            state.waiterIDs.insert(waiterID)
            task = state.task
            detailTasks[key] = state
        } else {
            let newTask = Task { [self] in
                try await loadDetails(for: summary)
            }
            detailTasks[key] = DetailTaskState(
                task: newTask,
                waiterIDs: [waiterID]
            )
            task = newTask
        }

        do {
            let details = try await awaitDetailTask(task)
            detailCache[key] = details
            releaseDetailWaiter(for: key, waiterID: waiterID)
            return details
        } catch {
            releaseDetailWaiter(for: key, waiterID: waiterID)
            throw error
        }
    }

    /// Awaiting a shared task must still respond to cancellation for this
    /// caller. The stream observer is cancelled per waiter; it never cancels
    /// the shared fetch, so another waiter can keep that fetch alive.
    private func awaitDetailTask(
        _ task: Task<CatalogCardDetails, Error>
    ) async throws -> CatalogCardDetails {
        let stream = AsyncThrowingStream<CatalogCardDetails, Error> { continuation in
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

    private func loadDetails(for summary: CatalogCardSummary) async throws -> CatalogCardDetails {
        let details: CatalogCardDetails
        switch summary.game {
        case .pokemon:
            let catalog = try await pokemonSet(id: summary.setID.providerID)
            let directory = try await sets(for: .pokemon)
            let directorySet = directory.first { $0.catalogID == summary.setID }
            guard let directorySet else { throw BrowseCatalogError.unknownSet }
            let set = PokemonMasterSetChecklistBuilder.enrichedSet(directorySet, providerSet: catalog)
            let card = try await pokemonTransport.fetchCard(id: summary.providerID)
            details = CatalogCardDetails(card: .pokemon(card, setCode: set.code), set: set)
        case .magic:
            let card = try await scryfall.fetchCard(id: summary.providerID)
            let directory = try await sets(for: .magic)
            let directorySet = directory.first { $0.catalogID == summary.setID }
            guard let set = directorySet else { throw BrowseCatalogError.unknownSet }
            details = CatalogCardDetails(card: .magic(card), set: set)
        }
        return details
    }

    private func detailCacheKey(for summary: CatalogCardSummary) -> String {
        "\(summary.game.rawValue):\(summary.providerID.lowercased())"
    }

    nonisolated func sortPrices(for cards: [CatalogCardSummary]) -> AsyncStream<[String: Double]> {
        return AsyncStream { continuation in
            let producer = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                await self.installMemoryWarningObserverIfNeeded()
                await self.produceSortPrices(for: cards, continuation: continuation)
            }
            continuation.onTermination = { @Sendable _ in
                producer.cancel()
            }
        }
    }

    private func produceSortPrices(
        for cards: [CatalogCardSummary],
        continuation: AsyncStream<[String: Double]>.Continuation
    ) async {
        // Every early return below leaves the consumer suspended in `for await`
        // unless the stream is finished, which would strand the set screen in
        // its loading state. Finishing twice is a no-op, so own it here once.
        defer { continuation.finish() }

        let cardsBySet = Dictionary(grouping: cards, by: \.setID.id)
        var freshPersistedPrices: [String: [String: Double]] = [:]
        for (setID, setCards) in cardsBySet {
            guard let cached = await cache.sortPrices(for: setID) else { continue }
            // Only a fresh envelope is worth carrying forward on the write
            // below; re-storing a stale map would reset its age without
            // re-pricing the slots this request never looked at.
            if cached.isFresh { freshPersistedPrices[setID] = cached.value }
            let currentIDs = Set(setCards.map(\.id))
            for (id, price) in cached.value where currentIDs.contains(id) {
                sortPriceCache[id] = price
                if cached.isFresh { resolvedSortPrices.insert(id) }
            }
        }

        continuation.yield(currentSortPrices(for: cards))

        let pending = providerGroups(from: cards).filter { providerGroup in
            providerGroup.contains { !resolvedSortPrices.contains($0.id) }
        }
        var iterator = pending.makeIterator()
        var resolvedSinceEmit = 0
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
                    for slot in result.slots {
                        if slot.resolved { resolvedSortPrices.insert(slot.id) }
                        if let price = slot.price { sortPriceCache[slot.id] = price }
                    }
                    resolvedSinceEmit += result.slots.filter(\.resolved).count

                    let elapsed = Date.now.timeIntervalSince(lastEmit)
                    if resolvedSinceEmit >= 25 || elapsed >= 0.25 {
                        continuation.yield(currentSortPrices(for: cards))
                        resolvedSinceEmit = 0
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

        guard !Task.isCancelled else { return }

        for (setID, setCards) in cardsBySet {
            // A request covers only the slots that were loaded, and the price
            // prefetch runs on the first page. Replacing the stored map would
            // shrink a fully priced set to one page on every cold open, which
            // is the relaunch cost this cache exists to remove. Merge instead:
            // this run's prices win, previously priced slots survive.
            var prices = freshPersistedPrices[setID] ?? [:]
            for card in setCards {
                guard let price = sortPriceCache[card.id] else { continue }
                prices[card.id] = price
            }
            guard !prices.isEmpty else { continue }
            await cache.storeSortPrices(prices, for: setID)
        }

        continuation.yield(currentSortPrices(for: cards))
    }

    private func providerGroups(from cards: [CatalogCardSummary]) -> [[CatalogCardSummary]] {
        var groups: [[CatalogCardSummary]] = []
        var indexes: [String: Int] = [:]
        for card in cards {
            let key = "\(card.game.rawValue):\(card.providerID.lowercased())"
            if let index = indexes[key] {
                groups[index].append(card)
            } else {
                indexes[key] = groups.count
                groups.append([card])
            }
        }
        return groups
    }

    private func currentSortPrices(for cards: [CatalogCardSummary]) -> [String: Double] {
        Dictionary(
            cards.compactMap { card in sortPriceCache[card.id].map { (card.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func sortPriceGroup(for summaries: [CatalogCardSummary]) async throws -> SortPriceGroupResult {
        guard let representative = summaries.first(where: { $0.pokemonPrintRun == nil }) else {
            return SortPriceGroupResult(
                slots: summaries.map { SortPriceSlot(id: $0.id, price: nil, resolved: true) }
            )
        }

        do {
            let details = try await details(for: representative)
            return SortPriceGroupResult(
                slots: summaries.map { summary in
                    guard summary.pokemonPrintRun == nil else {
                        // The aggregate card price is not edition-specific. Do
                        // not use it to sort virtual WotC runs as though it were.
                        return SortPriceSlot(id: summary.id, price: nil, resolved: true)
                    }
                    return sortPrice(for: summary, details: details)
                }
            )
        } catch {
            if error is CancellationError || Task.isCancelled {
                throw CancellationError()
            }
            return SortPriceGroupResult(
                slots: summaries.map {
                    SortPriceSlot(
                        id: $0.id,
                        price: nil,
                        resolved: $0.pokemonPrintRun != nil ? true : false
                    )
                }
            )
        }
    }

    private func sortPrice(for summary: CatalogCardSummary) async -> SortPriceSlot {
        guard summary.pokemonPrintRun == nil else {
            return SortPriceSlot(id: summary.id, price: nil, resolved: true)
        }
        do {
            let details = try await details(for: summary)
            return sortPrice(for: summary, details: details)
        } catch {
            return SortPriceSlot(id: summary.id, price: nil, resolved: false)
        }
    }

    private func sortPrice(
        for summary: CatalogCardSummary,
        details: CatalogCardDetails
    ) -> SortPriceSlot {
        if let variant = summary.masterSetVariant {
            let lookup = CardPricing.price(
                for: details.card,
                variant: variant,
                magicTreatments: details.card.magicTreatments(for: variant),
                pokemonPrintRun: summary.pokemonPrintRun
            )
            if case let .price(price) = lookup,
               price.currencyCode.caseInsensitiveCompare("USD") == .orderedSame {
                return SortPriceSlot(id: summary.id, price: price.unitMarketPriceUSD, resolved: true)
            }
            return SortPriceSlot(id: summary.id, price: nil, resolved: true)
        }
        return SortPriceSlot(
            id: summary.id,
            price: CardPricing.highestPublishedUSDPrice(for: details.card),
            resolved: true
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
        let (data, response) = try await URLSession.shared.data(for: request(url, scryfall: true))
        try validate(response)
        let excluded: Set<String> = ["token", "memorabilia", "minigame", "art_series"]
        let rows = try JSONDecoder().decode(ScryfallBrowseSetList.self, from: data).data.filter {
            !$0.digital && !excluded.contains($0.setType ?? "")
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

    private func magicCards(query: String, cursor: String?) async throws -> CatalogPage<CatalogCardSummary> {
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
        let (data, response) = try await URLSession.shared.data(for: request(url, scryfall: true))
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            return CatalogPage(items: [], nextCursor: nil)
        }
        try validate(response)
        let page = try JSONDecoder().decode(ScryfallBrowseCardPage.self, from: data)
        let directory = try await sets(for: .magic)
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
                magicTreatmentQualifiers: evidence.qualifiers
            )
            detailCache[detailCacheKey(for: summary)] = CatalogCardDetails(card: .magic(card), set: set)
            return summary
        }
        return CatalogPage(items: items, nextCursor: page.hasMore ? page.nextPage?.absoluteString : nil)
    }

    private func pokemonSet(id: String) async throws -> TCGdexSetCatalog {
        let key = id.lowercased()
        if let cached = pokemonSetDetails[key] { return cached }
        let loaded = try await pokemonTransport.fetchSet(id: id)
        try validatePokemonProviderSet(loaded, requestedID: id)
        pokemonSetDetails[key] = loaded
        return loaded
    }

    private func validatePokemonProviderSet(
        _ provider: TCGdexSetCatalog,
        requestedID: String
    ) throws {
        guard provider.id.caseInsensitiveCompare(requestedID) == .orderedSame else {
            throw BrowseCatalogError.unknownSet
        }
        guard catalogCoordinator == nil
            || catalogRegistry.descriptor(forProviderSetID: requestedID) != nil else {
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
            cardDetails: details
        )
        var displayedCards: [CatalogCardSummary] = []
        for value in built {
            let summaries = Self.applyingSignedCardArtwork(value.cards, set: value.set)
            for summary in summaries {
                guard let card = details[summary.providerID] else { continue }
                detailCache[detailCacheKey(for: summary)] = CatalogCardDetails(
                    card: .pokemon(card, setCode: summary.setCode),
                    set: value.set
                )
            }
            if value.set.id == set.id {
                displayedCards = summaries
            }
        }
        return displayedCards
    }

    private func pokemonCardDetails(
        for provider: TCGdexSetCatalog
    ) async throws -> [String: TCGdexCard] {
        // A changed provider card list must never reuse details fetched for the
        // previous list. This also lets an active refresh replace a stale card
        // without requiring a new catalog instance.
        let key = provider.id.lowercased()
            + "|"
            + PokemonMasterSetChecklistBuilder.providerProbeFingerprint(of: provider)
        if let cached = pokemonSetCardDetails[key] { return cached }

        var iterator = provider.cards.makeIterator()
        var details: [String: TCGdexCard] = [:]
        try await withThrowingTaskGroup(of: (String, TCGdexCard).self) { group in
            for _ in 0..<min(8, provider.cards.count) {
                guard let brief = iterator.next() else { break }
                group.addTask { (brief.id, try await self.pokemonTransport.fetchCard(id: brief.id)) }
            }
            while let value = try await group.next() {
                details[value.0] = value.1
                if let brief = iterator.next() {
                    group.addTask { (brief.id, try await self.pokemonTransport.fetchCard(id: brief.id)) }
                }
            }
        }
        guard details.count == provider.cards.count else {
            throw PokemonChecklistError.incompleteProviderSet(provider.id)
        }
        pokemonSetCardDetails[key] = details
        return details
    }

    private func loadPokemonSnapshotIfNeeded() async {
        guard !pokemonSnapshotLoaded else { return }
        let loadTask: Task<[PokemonChecklistSnapshotEntry], Never>
        if let existing = pokemonSnapshotLoadTask {
            loadTask = existing
        } else {
            let checklistStore = checklistStore
            let task = Task<[PokemonChecklistSnapshotEntry], Never> {
                await checklistStore.mergedEntries()
            }
            pokemonSnapshotLoadTask = task
            loadTask = task
        }

        let entries = await loadTask.value
        // Do not turn a cancelled or unsuccessful request into a completed
        // latch. A nil result must remain retryable if both snapshot sources
        // were temporarily unavailable.
        guard !Task.isCancelled else { return }
        pokemonSnapshotLoadTask = nil
        let visibleEntries = await visibleSnapshotEntries(entries)
        pokemonSnapshotLoaded = !visibleEntries.isEmpty
        pokemonSnapshotEntries = visibleEntries
        if !visibleEntries.isEmpty {
            let sets = pokemonSets(from: visibleEntries)
            setCache[.pokemon] = sets
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
            let rows = try await pokemonTransport.fetchSetDirectory()
            let baseSets = PokemonMasterSetChecklistBuilder.baseSets(
                from: rows,
                registry: catalogCoordinator == nil ? nil : catalogRegistry
            )
            let authorizedSets: [CatalogSet]
            if catalogCoordinator == nil {
                authorizedSets = baseSets
            } else {
                authorizedSets = baseSets.filter {
                    catalogRegistry.descriptor(forProviderSetID: $0.providerID) != nil
                }
            }
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
                    try validatePokemonProviderSet(provider, requestedID: baseSet.providerID)
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
                        cardDetails: details
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
                    yieldUpdate(providerSetID: baseSet.providerID)
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

    private static let setDirectoryMaxAge: TimeInterval = 24 * 60 * 60
    private static let sealedSetDirectoryMaxAge: TimeInterval = 7 * 24 * 60 * 60
    private static let sealedProductMaxAge: TimeInterval = 6 * 60 * 60
    private static let magicCardPageMaxAge: TimeInterval = 24 * 60 * 60
    private static let sortPriceMaxAge: TimeInterval = 24 * 60 * 60
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

    func sets(for game: CardGame) -> Cached<[CatalogSet]>? {
        load([CatalogSet].self, from: setDirectoryURL(for: game), maxAge: Self.setDirectoryMaxAge)
    }

    func storeSets(_ sets: [CatalogSet], for game: CardGame) {
        store(sets, at: setDirectoryURL(for: game))
    }

    func removeSets(for game: CardGame) {
        try? FileManager.default.removeItem(at: setDirectoryURL(for: game))
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

    /// Sort prices are disposable ordering hints. They are never used as
    /// observation history, a checked-at value, or a price record.
    func sortPrices(for setID: String) -> Cached<[String: Double]>? {
        let url = sortPricesDirectory.appendingPathComponent(
            filename(for: "sortprices|\(setID)")
        )
        guard let cached = load(
            [String: Double].self,
            from: url,
            maxAge: Self.sortPriceMaxAge
        ) else {
            return nil
        }
        touch(url)
        return cached
    }

    func storeSortPrices(_ prices: [String: Double], for setID: String) {
        store(
            prices,
            at: sortPricesDirectory.appendingPathComponent(
                filename(for: "sortprices|\(setID)")
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
        guard let cached = load(CatalogPage<SealedProductSummary>.self, from: url, maxAge: Self.sealedProductMaxAge) else {
            return nil
        }
        touch(url)
        return cached
    }

    func storeSealedProductPage(_ page: CatalogPage<SealedProductSummary>, for key: String) {
        store(page, at: sealedPagesDirectory.appendingPathComponent(filename(for: key)))
        trim(sealedPagesDirectory, maximumBytes: Self.sealedPageLimit)
    }

    static func cardPageKey(for set: CatalogSet, cursor: String?) -> String {
        "cards|schema:\(PokemonChecklistSnapshotVersion.schema)|rules:\(PokemonChecklistSnapshotVersion.masterSetRules)|\(set.id)|\(cursor ?? "initial")"
    }

    static func sealedPageKey(game: CardGame, setID: String?, query: String?, offset: Int) -> String {
        "sealed|\(game.rawValue)|\(setID ?? "all")|\(query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "")|\(offset)"
    }

    private var cardPagesDirectory: URL { root.appendingPathComponent("CardPages", isDirectory: true) }
    private var sealedPagesDirectory: URL { root.appendingPathComponent("SealedPages", isDirectory: true) }
    private var sortPricesDirectory: URL { root.appendingPathComponent("SortPrices", isDirectory: true) }

    private func setDirectoryURL(for game: CardGame) -> URL {
        root.appendingPathComponent("Sets-\(game.rawValue).json")
    }

    private func sealedSetDirectoryURL(for game: CardGame) -> URL {
        root.appendingPathComponent("SealedSets-\(game.rawValue).json")
    }

    private func load<Value: Codable & Sendable>(
        _ type: Value.Type,
        from url: URL,
        maxAge: TimeInterval?
    ) -> Cached<Value>? {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(CacheEnvelope<Value>.self, from: data) else {
            return nil
        }
        let isFresh = maxAge.map {
            let age = Date.now.timeIntervalSince(envelope.storedAt)
            return age >= 0 && age < $0
        } ?? true
        return Cached(value: envelope.value, storedAt: envelope.storedAt, isFresh: isFresh)
    }

    private func store<Value: Codable & Sendable>(_ value: Value, at url: URL) {
        let directory = url.deletingLastPathComponent()
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil,
              let data = try? JSONEncoder().encode(CacheEnvelope(storedAt: .now, value: value)) else {
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
        card: TCGdexCardBrief,
        setProviderID: String,
        printRun: PokemonPrintRun?
    ) -> Bool {
        // Every English Base Set Machamp is stamped. There is no distinct
        // Unlimited printing, so it cannot complete the Unlimited run.
        setProviderID.caseInsensitiveCompare("base1") == .orderedSame
            && printRun == .unlimited
            && CatalogIdentityNormalization.localNumber(card.localId) == "8"
    }

    /// The required physical slots for one numbered card. Edition is carried
    /// separately by the virtual set, so the legacy first-edition pseudo-finish
    /// never becomes a second slot. Named parallel patterns are marked as the
    /// expanded tier; the standard tier remains normal, holo and reverse.
    static func requiredVariants(
        for card: TCGdexCard
    ) -> [(variant: PhysicalVariant, isExpanded: Bool, isSole: Bool)] {
        var variants = card.catalogVariants.filter {
            $0.id != PhysicalVariant.firstEdition.id
        }

        // Some early cards publish only the edition flag. They still represent
        // one pack-pulled base slot within that edition.
        if variants.isEmpty {
            variants = [.normal]
        }

        var seen = Set<String>()
        let slots = variants.filter { seen.insert($0.id).inserted }
        return slots.map { variant in
            let isStandard = [
                PhysicalVariant.normal.id,
                PhysicalVariant.holo.id,
                PhysicalVariant.reverse.id
            ].contains(variant.id)
            return (variant, !isStandard, slots.count == 1)
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
