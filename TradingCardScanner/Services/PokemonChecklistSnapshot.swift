import Foundation
import UIKit

/// The on-device format for the Pokémon Browse snapshot. The manifest is kept
/// separate from the checklist files so a refresh can write every new file and
/// publish the manifest last. A reader therefore sees either the old complete
/// snapshot or the new complete snapshot, never a half-built set.
enum PokemonChecklistSnapshotVersion {
    static let schema = 1
    static let masterSetRules = 1
}

struct PokemonChecklistSnapshotManifest: Codable, Sendable, Equatable {
    let schemaVersion: Int
    let rulesVersion: Int
    let generatedAt: Date
    let directoryFingerprint: String
    let entries: [PokemonChecklistSnapshotEntry]

    var isSupported: Bool {
        schemaVersion == PokemonChecklistSnapshotVersion.schema
            && rulesVersion == PokemonChecklistSnapshotVersion.masterSetRules
    }
}

struct PokemonChecklistSnapshotEntry: Codable, Sendable, Equatable {
    let set: CatalogSet
    let providerID: String
    let providerFingerprint: String
    /// The provider's printed denominator. This is intentionally separate from
    /// `set.cardCount`, which is the expanded master-set count used by Browse.
    /// Older manifests omit it and historical matching falls back to the
    /// authoritative modern set map when one exists.
    let officialCount: Int?
    /// Relative to the bundled snapshot directory or the protected overlay
    /// directory. Keeping this in the manifest makes resource names opaque to
    /// the provider and lets a future schema change use a new path safely.
    let resource: String

    init(
        set: CatalogSet,
        providerID: String,
        providerFingerprint: String,
        officialCount: Int? = nil,
        resource: String
    ) {
        self.set = set
        self.providerID = providerID
        self.providerFingerprint = providerFingerprint
        self.officialCount = officialCount
        self.resource = resource
    }
}

struct PokemonChecklistSnapshot: Sendable, Equatable, Codable {
    let manifest: PokemonChecklistSnapshotManifest
    let checklists: [String: [CatalogCardSummary]]

    var sets: [CatalogSet] {
        manifest.entries.compactMap { checklists[$0.set.id] == nil ? nil : $0.set }
    }

    func entry(for setID: CatalogSetID) -> PokemonChecklistSnapshotEntry? {
        manifest.entries.first { $0.set.catalogID == setID }
    }

    func checklist(for setID: CatalogSetID) -> [CatalogCardSummary]? {
        checklists[setID.id]
    }

    func entry(forProviderID providerID: String) -> PokemonChecklistSnapshotEntry? {
        manifest.entries.first {
            $0.providerID.caseInsensitiveCompare(providerID) == .orderedSame
        }
    }

    /// Downloaded overlays are complete snapshots in their own store. The
    /// merge still accepts a partial overlay so old development builds can be
    /// upgraded without throwing away a valid bundled checklist.
    static func merged(
        bundled: PokemonChecklistSnapshot?,
        downloaded: PokemonChecklistSnapshot?
    ) -> PokemonChecklistSnapshot? {
        let sources = [bundled, downloaded].compactMap { $0 }
        guard let first = sources.first else { return nil }

        var entriesByID: [String: PokemonChecklistSnapshotEntry] = [:]
        var checklists: [String: [CatalogCardSummary]] = [:]
        var order: [String] = []
        for snapshot in sources {
            guard snapshot.manifest.isSupported else { continue }
            for entry in snapshot.manifest.entries {
                if entriesByID[entry.set.id] == nil { order.append(entry.set.id) }
                entriesByID[entry.set.id] = entry
                if let cards = snapshot.checklists[entry.set.id] {
                    checklists[entry.set.id] = cards
                }
            }
        }

        let entries = order.compactMap { entriesByID[$0] }
        guard !entries.isEmpty else { return nil }
        let manifest = PokemonChecklistSnapshotManifest(
            schemaVersion: first.manifest.schemaVersion,
            rulesVersion: first.manifest.rulesVersion,
            generatedAt: sources.last?.manifest.generatedAt ?? first.manifest.generatedAt,
            directoryFingerprint: sources.last?.manifest.directoryFingerprint
                ?? first.manifest.directoryFingerprint,
            entries: entries
        )
        return PokemonChecklistSnapshot(manifest: manifest, checklists: checklists)
    }

    static func from(
        builtSets: [PokemonMasterSetChecklistBuilder.BuiltSet],
        generatedAt: Date = .now
    ) -> PokemonChecklistSnapshot {
        let entries = builtSets.map { value in
            PokemonChecklistSnapshotEntry(
                set: value.set,
                providerID: value.set.providerID,
                providerFingerprint: value.providerFingerprint,
                officialCount: value.officialCount,
                resource: "sets/\(StableCatalogFingerprint.string(value.set.id + value.providerFingerprint)).json"
            )
        }
        let manifest = PokemonChecklistSnapshotManifest(
            schemaVersion: PokemonChecklistSnapshotVersion.schema,
            rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
            generatedAt: generatedAt,
            directoryFingerprint: PokemonMasterSetChecklistBuilder.directoryFingerprint(entries),
            entries: entries
        )
        return PokemonChecklistSnapshot(
            manifest: manifest,
            checklists: Dictionary(uniqueKeysWithValues: builtSets.map { ($0.set.id, $0.cards) })
        )
    }
}

/// Shared expansion logic for the live catalog and the release snapshot
/// generator. The provider set is fetched once, each provider card is fetched
/// once, and all virtual print runs are then projections of this same input.
enum PokemonMasterSetChecklistBuilder {
    struct BuiltSet: Sendable, Equatable {
        let set: CatalogSet
        let cards: [CatalogCardSummary]
        let providerFingerprint: String
        let officialCount: Int?
    }

    static func baseSets(
        from rows: [TCGdexBrowseSet],
        excluding pocketIDs: Set<String>
    ) -> [CatalogSet] {
        let baseSets = rows.enumerated().compactMap { pair -> CatalogSet? in
            let index = pair.offset
            let row = pair.element
            guard !pocketIDs.contains(row.id.lowercased()),
                  PokemonMasterSetDefinition.includesInSetDirectory(row) else {
                return nil
            }
            return CatalogSet(
                catalogID: CatalogSetID(game: .pokemon, providerID: row.id),
                name: row.name,
                code: row.tcgOnline?.uppercased()
                    ?? SetCodeMap.printedCode(forTCGdexSetID: row.id)
                    ?? row.id.uppercased(),
                logoURL: assetURL(row.logo, suffix: ".png"),
                symbolURL: assetURL(row.symbol, suffix: ".png"),
                cardCount: row.cardCount.map {
                    PokemonMasterSetDefinition.masterCount(
                        cardCount: $0,
                        setName: row.name,
                        printRun: nil
                    )
                },
                releaseDate: nil,
                sortRank: rows.count - index
            )
        }
        return baseSets
    }

    static func build(
        providerSet: TCGdexSetCatalog,
        baseSet: CatalogSet,
        cardDetails: [String: TCGdexCard]
    ) throws -> [BuiltSet] {
        let enriched = enrichedSet(baseSet, providerSet: providerSet)
        let virtualSets = PokemonMasterSetDefinition.virtualSets(
            enriched,
            cardCount: providerSet.cardCount
        )

        let orderedCards = providerSet.cards
            .compactMap { brief -> (TCGdexCardBrief, TCGdexCard)? in
                guard let details = cardDetails[brief.id] else { return nil }
                return (brief, details)
            }
        guard orderedCards.count == providerSet.cards.count else {
            throw PokemonChecklistError.incompleteProviderSet(providerSet.id)
        }

        // The set endpoint's card list is the provider/card fingerprint used
        // for refresh eligibility. Detailed cards are intentionally fetched
        // only after this fingerprint says the checklist is missing or stale.
        let providerFingerprint = fingerprint(of: providerSet)
        return virtualSets.map { set in
            let summaries = orderedCards
                .filter {
                    !PokemonMasterSetDefinition.excludes(
                        card: $0.0,
                        setProviderID: set.providerID,
                        printRun: set.pokemonPrintRun
                    )
                }
                .flatMap { brief, card in
                    let base = summary(brief, set: set)
                    return PokemonMasterSetDefinition.requiredVariants(for: card).map {
                        requirement in
                        var value = base
                        value.masterSetVariant = requirement.variant
                        value.isExpandedMasterSetVariant = requirement.isExpanded
                        value.isSoleSlotForCard = requirement.isSole
                        return value
                    }
                }
            return BuiltSet(
                set: set,
                cards: summaries,
                providerFingerprint: providerFingerprint,
                officialCount: providerSet.cardCount?.official
            )
        }
    }

    static func fingerprint(of providerSet: TCGdexSetCatalog) -> String {
        var value = [
            providerSet.id,
            providerSet.name,
            providerSet.logo ?? "",
            providerSet.symbol ?? "",
            providerSet.tcgOnline ?? "",
            providerSet.releaseDate ?? ""
        ]
        if let count = providerSet.cardCount {
            value += [
                String(count.total), String(count.official), String(count.normal ?? -1),
                String(count.reverse ?? -1), String(count.holo ?? -1), String(count.firstEd ?? -1)
            ]
        }
        value += providerSet.cards.flatMap { [$0.id, $0.localId, $0.name, $0.image ?? ""] }
        return StableCatalogFingerprint.string(value.joined(separator: "\u{1F}"))
    }

    static func fingerprint(
        of providerSet: TCGdexSetCatalog,
        cardDetails: [String: TCGdexCard]
    ) -> String {
        var value = [fingerprint(of: providerSet)]
        for brief in providerSet.cards {
            guard let card = cardDetails[brief.id] else { continue }
            value += [card.id, card.localId, card.name, card.image ?? ""]
            if let variants = card.variants {
                value += [
                    String(variants.firstEdition), String(variants.holo),
                    String(variants.normal), String(variants.reverse), String(variants.wPromo ?? false)
                ]
            }
            for detailed in card.variantsDetailed ?? [] {
                value += [
                    detailed.type ?? "", detailed.subtype ?? "",
                    detailed.stamp?.sorted().joined(separator: ",") ?? "",
                    detailed.foil ?? "", detailed.size ?? "", detailed.variantId ?? "",
                    detailed.languages?.sorted().joined(separator: ",") ?? ""
                ]
            }
        }
        return StableCatalogFingerprint.string(value.joined(separator: "\u{1F}"))
    }

    static func directoryFingerprint(_ entries: [PokemonChecklistSnapshotEntry]) -> String {
        StableCatalogFingerprint.string(
            entries
                .sorted { $0.set.id < $1.set.id }
                .map { "\($0.set.id)=\($0.providerFingerprint)" }
                .joined(separator: "\u{1F}")
        )
    }

    static func enrichedSet(
        _ set: CatalogSet,
        providerSet: TCGdexSetCatalog
    ) -> CatalogSet {
        CatalogSet(
            catalogID: set.catalogID,
            name: set.name,
            code: providerSet.tcgOnline?.uppercased() ?? set.code,
            logoURL: assetURL(providerSet.logo, suffix: ".png") ?? set.logoURL,
            symbolURL: assetURL(providerSet.symbol, suffix: ".png") ?? set.symbolURL,
            cardCount: providerSet.cardCount.map {
                PokemonMasterSetDefinition.masterCount(
                    cardCount: $0,
                    setName: providerSet.name,
                    printRun: set.pokemonPrintRun
                )
            } ?? set.cardCount,
            releaseDate: providerSet.releaseDate.flatMap(FlexibleDate.parse),
            sortRank: set.sortRank
        )
    }

    static func summary(
        _ card: TCGdexCardBrief,
        set: CatalogSet
    ) -> CatalogCardSummary {
        let base = card.image.flatMap { URL(string: $0) }
        return CatalogCardSummary(
            game: .pokemon,
            providerID: card.id,
            setID: set.catalogID,
            setName: set.name,
            setCode: set.code,
            name: card.name,
            collectorNumber: card.localId,
            thumbnailURL: base.flatMap { URL(string: $0.absoluteString + "/low.png") },
            imageURL: base.flatMap { URL(string: $0.absoluteString + "/high.png") }
        )
    }

    private static func assetURL(_ value: String?, suffix: String) -> URL? {
        value.flatMap { URL(string: $0 + suffix) }
    }
}

enum PokemonChecklistError: LocalizedError, Sendable {
    case incompleteProviderSet(String)
    case missingModernSetCoverage([String])
    case malformedSnapshot

    var errorDescription: String? {
        switch self {
        case let .incompleteProviderSet(id):
            return "The Pokémon set \(id) did not contain all of its card details."
        case let .missingModernSetCoverage(ids):
            return "The Pokémon checklist is missing modern sets: \(ids.sorted().joined(separator: ", "))."
        case .malformedSnapshot:
            return "The bundled Pokémon checklist is unavailable."
        }
    }
}

enum StableCatalogFingerprint {
    static func string(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

/// The network-facing seam used by BrowseCatalog and by the developer-only
/// snapshot generator. Tests can supply a fake without URL loading or sleeps.
protocol PokemonBrowseTransport: Sendable {
    func fetchSetDirectory() async throws -> [TCGdexBrowseSet]
    func fetchPocketSetIDs() async throws -> Set<String>
    func fetchSet(id: String) async throws -> TCGdexSetCatalog
    func fetchCard(id: String) async throws -> TCGdexCard
}

struct TCGdexBrowseTransport: PokemonBrowseTransport, Sendable {
    private let service = TCGdexService()

    func fetchSetDirectory() async throws -> [TCGdexBrowseSet] {
        guard let url = URL(string: "https://api.tcgdex.net/v2/en/sets?sort:field=releaseDate&sort:order=DESC") else {
            throw BrowseCatalogError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BrowseCatalogError.badResponse
        }
        return try JSONDecoder().decode([TCGdexBrowseSet].self, from: data)
    }

    func fetchPocketSetIDs() async throws -> Set<String> {
        guard let url = URL(string: "https://api.tcgdex.net/v2/en/series/tcgp") else {
            throw BrowseCatalogError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BrowseCatalogError.badResponse
        }
        return Set(try JSONDecoder().decode(PokemonBrowseSeriesSets.self, from: data).sets.map { $0.id.lowercased() })
    }

    func fetchSet(id: String) async throws -> TCGdexSetCatalog {
        try await service.fetchSet(id: id)
    }

    func fetchCard(id: String) async throws -> TCGdexCard {
        try await service.fetchCard(id: id)
    }
}

private struct PokemonBrowseSeriesSets: Decodable {
    struct Brief: Decodable { let id: String }
    let sets: [Brief]
}

/// Protected checklist persistence. This is deliberately not part of the LRU
/// page cache: a user who opened many card pages must not lose offline set
/// readiness as a side effect.
private struct PokemonChecklistRefreshState: Codable, Equatable, Sendable {
    /// The last crawl that reached the end of the directory with no failures.
    /// Governs the ordinary 24-hour cadence.
    let lastSuccessfulAt: Date?
    /// The last crawl that reached the end of the directory at all, clean or
    /// not. Kept separate from `lastSuccessfulAt` so an unfetchable set can
    /// never pin the resume cursor and freeze the whole catalog: once this is
    /// older than the refresh interval, the next crawl sweeps from the start
    /// regardless of what is still failing.
    let lastSweepAt: Date?
    /// The last crawl that ended in a state worth backing off from — a
    /// provider failure or an unreachable set directory. Deliberately *not*
    /// written by ordinary progress or by cancellation: a user switching apps
    /// mid-crawl has learned nothing about the provider and must not be made
    /// to wait out a failure backoff.
    let lastAttemptAt: Date?
    let resumeAfterProviderID: String?
    let failedProviderIDs: [String]

    init(
        lastSuccessfulAt: Date?,
        lastSweepAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        resumeAfterProviderID: String?,
        failedProviderIDs: [String] = []
    ) {
        self.lastSuccessfulAt = lastSuccessfulAt
        self.lastSweepAt = lastSweepAt
        self.lastAttemptAt = lastAttemptAt
        self.resumeAfterProviderID = resumeAfterProviderID
        self.failedProviderIDs = failedProviderIDs
    }

    private enum CodingKeys: String, CodingKey {
        case lastSuccessfulAt
        case lastSweepAt
        case lastAttemptAt
        case resumeAfterProviderID
        case failedProviderIDs
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        lastSuccessfulAt = try values.decodeIfPresent(Date.self, forKey: .lastSuccessfulAt)
        // A state written before this field existed had no way to complete a
        // sweep other than cleanly, so the successful timestamp is the honest
        // migration value.
        lastSweepAt = try values.decodeIfPresent(Date.self, forKey: .lastSweepAt)
            ?? lastSuccessfulAt
        lastAttemptAt = try values.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
        resumeAfterProviderID = try values.decodeIfPresent(
            String.self,
            forKey: .resumeAfterProviderID
        )
        failedProviderIDs = try values.decodeIfPresent(
            [String].self,
            forKey: .failedProviderIDs
        ) ?? []
    }
}

actor PokemonChecklistStore {
    private enum ChecklistLoadOutcome {
        case loaded([CatalogCardSummary])
        case undecodable
        case unreadable
    }

    static let shared = PokemonChecklistStore()

    private let root: URL
    private let bundledRoot: URL?
    private let refreshStateURL: URL
    private var downloadedManifestCache: PokemonChecklistSnapshotManifest?
    private var didLoadDownloadedManifest = false
    private var bundledManifestCache: PokemonChecklistSnapshotManifest?
    private var didLoadBundledManifest = false

    // These caches are deliberately per set. The production catalog only needs
    // the set currently being displayed, while the legacy snapshot methods
    // remain available for release tooling and tests that explicitly request a
    // complete value-type snapshot.
    private var downloadedChecklistCache = BoundedCache<String, [CatalogCardSummary]>(capacity: 10)
    private var bundledChecklistCache = BoundedCache<String, [CatalogCardSummary]>(capacity: 10)
    private var unreadableChecklistIDs: Set<String> = []
    private var downloadedSnapshotCache: PokemonChecklistSnapshot?
    private var bundledSnapshotCache: PokemonChecklistSnapshot?
    private var memoryWarningObserver: NSObjectProtocol?

    nonisolated static let refreshInterval: TimeInterval = 24 * 60 * 60
    nonisolated static let failedRefreshBackoff: TimeInterval = 60 * 60

    init(root: URL? = nil, bundle: Bundle? = .main, bundledRoot: URL? = nil) {
        if let root {
            self.root = root
        } else {
            self.root = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("BrowseCatalogCache/PokemonChecklists", isDirectory: true)
        }
        if let bundledRoot {
            self.bundledRoot = bundledRoot
        } else {
            self.bundledRoot = bundle?.url(
                forResource: "PokemonChecklistSnapshot",
                withExtension: nil
            )
        }
        self.refreshStateURL = self.root.appendingPathComponent("refresh-state.json")
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    func downloadedSnapshot() -> PokemonChecklistSnapshot? {
        installMemoryWarningObserverIfNeeded()
        guard downloadedSnapshotCache == nil else { return downloadedSnapshotCache }
        downloadedSnapshotCache = loadSnapshot(from: root)
        if let manifest = downloadedSnapshotCache?.manifest {
            downloadedManifestCache = manifest
            didLoadDownloadedManifest = true
        }
        return downloadedSnapshotCache
    }

    func bundledSnapshot() -> PokemonChecklistSnapshot? {
        installMemoryWarningObserverIfNeeded()
        guard bundledSnapshotCache == nil, let bundledRoot else {
            return bundledSnapshotCache
        }
        bundledSnapshotCache = loadSnapshot(from: bundledRoot)
        if let manifest = bundledSnapshotCache?.manifest {
            bundledManifestCache = manifest
            didLoadBundledManifest = true
        }
        return bundledSnapshotCache
    }

    /// The scanner and Browse use the same precedence rule: a complete
    /// downloaded overlay wins for a set, while bundled data remains available
    /// for sets the overlay does not contain.
    func mergedSnapshot() -> PokemonChecklistSnapshot? {
        installMemoryWarningObserverIfNeeded()
        return PokemonChecklistSnapshot.merged(
            bundled: bundledSnapshot(),
            downloaded: downloadedSnapshot()
        )
    }

    /// Returns only manifest entries and verifies that the referenced resource
    /// exists. No checklist JSON is decoded here, so Browse and scanning can
    /// share one store without materialising the entire Pokémon corpus.
    func mergedEntries() -> [PokemonChecklistSnapshotEntry] {
        installMemoryWarningObserverIfNeeded()
        return mergeEntries(
            bundled: validEntries(from: bundledManifest(), directory: bundledRoot),
            downloaded: validEntries(from: downloadedManifest(), directory: root)
        )
    }

    /// Whether the checklist `mergedEntries()` names for this set is intact.
    ///
    /// Deliberately **not** `mergedChecklist(for:) != nil`. The refresh crawl
    /// compares provider fingerprints against the entry the merge serves, and
    /// the merge prefers the downloaded overlay. If a readable bundled copy
    /// were allowed to vouch for a corrupt overlay, the crawl would skip the
    /// set as healthy, the overlay would never be republished, and the app
    /// would quietly serve older bundled data for that set indefinitely.
    /// Only the owning tier's own resource may answer this question.
    func hasMergedChecklist(for setID: CatalogSetID) -> Bool {
        installMemoryWarningObserverIfNeeded()
        let key = setID.id
        guard !unreadableChecklistIDs.contains(key) else { return false }
        if let entry = downloadedEntry(for: key) {
            guard case .loaded = cachedChecklist(for: entry, in: root, isDownloaded: true) else {
                return false
            }
            return true
        }
        guard let bundledRoot, let entry = bundledEntry(for: key) else { return false }
        guard case .loaded = cachedChecklist(
            for: entry,
            in: bundledRoot,
            isDownloaded: false
        ) else {
            return false
        }
        return true
    }

    /// Decodes one checklist on demand, for display.
    ///
    /// A downloaded set wins when it is readable; a corrupt overlay falls back
    /// to the bundled set rather than hiding a known-good offline resource. A
    /// reader wants the best data available — deciding whether the *overlay*
    /// needs repairing is `hasMergedChecklist(for:)`'s job, not this one's.
    func mergedChecklist(for setID: CatalogSetID) -> [CatalogCardSummary]? {
        installMemoryWarningObserverIfNeeded()
        let key = setID.id
        guard !unreadableChecklistIDs.contains(key) else { return nil }
        var encounteredUndecodableResource = false
        var encounteredUnreadableResource = false

        if let entry = downloadedEntry(for: key) {
            switch cachedChecklist(for: entry, in: root, isDownloaded: true) {
            case let .loaded(cards):
                unreadableChecklistIDs.remove(key)
                return cards
            case .undecodable:
                encounteredUndecodableResource = true
            case .unreadable:
                encounteredUnreadableResource = true
            }
        }

        if let bundledRoot, let entry = bundledEntry(for: key) {
            switch cachedChecklist(for: entry, in: bundledRoot, isDownloaded: false) {
            case let .loaded(cards):
                unreadableChecklistIDs.remove(key)
                return cards
            case .undecodable:
                encounteredUndecodableResource = true
            case .unreadable:
                encounteredUnreadableResource = true
            }
        }

        // Only a deterministic decode failure, with no transient I/O error
        // anywhere in the lookup, is safe to remember as permanently bad.
        if encounteredUndecodableResource, !encounteredUnreadableResource {
            unreadableChecklistIDs.insert(key)
        }
        return nil
    }

    private func downloadedEntry(for setID: String) -> PokemonChecklistSnapshotEntry? {
        validEntries(from: downloadedManifest(), directory: root)
            .first { $0.set.id == setID }
    }

    private func bundledEntry(for setID: String) -> PokemonChecklistSnapshotEntry? {
        guard let bundledRoot else { return nil }
        return validEntries(from: bundledManifest(), directory: bundledRoot)
            .first { $0.set.id == setID }
    }

    /// One tier's checklist, served from the LRU when it is already decoded.
    /// A successful decode populates that tier's cache; a failure never does,
    /// so the caller still sees why it failed.
    private func cachedChecklist(
        for entry: PokemonChecklistSnapshotEntry,
        in directory: URL,
        isDownloaded: Bool
    ) -> ChecklistLoadOutcome {
        let key = entry.set.id
        if isDownloaded {
            if let cached = downloadedChecklistCache[key] { return .loaded(cached) }
        } else if let cached = bundledChecklistCache[key] {
            return .loaded(cached)
        }

        let outcome = loadChecklist(for: entry, in: directory)
        if case let .loaded(cards) = outcome {
            if isDownloaded {
                downloadedChecklistCache[key] = cards
            } else {
                bundledChecklistCache[key] = cards
            }
        }
        return outcome
    }

    /// The active-session refresh uses this timestamp to avoid re-crawling the
    /// provider set directory on every foreground transition. A missing or
    /// unreadable state is intentionally treated as stale.
    func shouldRefresh(
        now: Date = .now,
        interval: TimeInterval = PokemonChecklistStore.refreshInterval
    ) -> Bool {
        installMemoryWarningObserverIfNeeded()
        // A bundled checklist is a valid, complete starting point. Requiring a
        // downloaded manifest here would make an app that has only ever used
        // its shipped snapshot crawl the entire provider directory on every
        // foreground forever, because the refresh itself may legitimately find
        // no changed sets to publish.
        guard !mergedEntries().isEmpty,
              let state = loadRefreshState() else {
            return true
        }
        // A stored timestamp in the future means the device clock moved
        // backwards. That is evidence the state is untrustworthy, never
        // evidence that the catalog is fresh — treating it as fresh would
        // suppress every refresh until wall-clock time caught up.
        if Self.isWithin(interval, of: state.lastSuccessfulAt, at: now) { return false }
        if Self.isWithin(Self.failedRefreshBackoff, of: state.lastAttemptAt, at: now) {
            return false
        }
        return true
    }

    /// Whether the next crawl must start at the beginning of the directory
    /// rather than resuming from its cursor.
    ///
    /// The cursor exists so an interrupted or partly failed crawl does not
    /// restart from zero. It must not become permanent: a set that fails every
    /// time would otherwise hold the cursor at the end of the directory
    /// forever, and no other set would ever be re-checked for changes.
    func needsFullSweep(
        now: Date = .now,
        interval: TimeInterval = PokemonChecklistStore.refreshInterval
    ) -> Bool {
        guard let state = loadRefreshState() else { return true }
        return !Self.isWithin(interval, of: state.lastSweepAt, at: now)
    }

    /// True only when `date` exists, is not in the future, and is younger than
    /// `interval`. Absent and future timestamps are both treated as stale.
    private static func isWithin(
        _ interval: TimeInterval,
        of date: Date?,
        at now: Date
    ) -> Bool {
        guard let date else { return false }
        let age = now.timeIntervalSince(date)
        return age >= 0 && age < interval
    }

    func refreshResumeAfterProviderID() -> String? {
        loadRefreshState()?.resumeAfterProviderID
    }

    func refreshFailedProviderIDs() -> Set<String> {
        Set((loadRefreshState()?.failedProviderIDs ?? []).map { $0.lowercased() })
    }

    /// Progress is durable after each completed provider set. The cursor moves
    /// past failures so a bad provider set cannot force a full retry on every
    /// foreground; failed ids remain recorded for a retry when the crawl next
    /// encounters them.
    ///
    /// Ordinary progress deliberately does not arm the failure backoff. The
    /// crawl is cancelled by every `inactive` scene transition — the app
    /// switcher, Notification Center, an incoming call — and treating "two
    /// sets were fetched before the user swiped up" as a failed attempt would
    /// stall the directory for an hour each time.
    func recordRefreshProgress(
        after providerID: String,
        failed: Bool = false,
        advancesCursor: Bool = true,
        at date: Date = .now
    ) {
        let previous = loadRefreshState()
        var failedIDs = Set(previous?.failedProviderIDs ?? [])
        let normalizedID = providerID.lowercased()
        if failed {
            failedIDs.insert(normalizedID)
        } else {
            failedIDs.remove(normalizedID)
        }
        writeRefreshState(
            PokemonChecklistRefreshState(
                lastSuccessfulAt: previous?.lastSuccessfulAt,
                lastSweepAt: previous?.lastSweepAt,
                lastAttemptAt: failed ? date : previous?.lastAttemptAt,
                resumeAfterProviderID: advancesCursor
                    ? providerID
                    : previous?.resumeAfterProviderID,
                failedProviderIDs: failedIDs.sorted()
            )
        )
    }

    /// A crawl that reached the end of the directory with nothing outstanding.
    /// Clears the cursor and the failure backoff; the 24-hour interval alone
    /// governs the next crawl.
    func markRefreshSucceeded(at date: Date = .now) {
        writeRefreshState(
            PokemonChecklistRefreshState(
                lastSuccessfulAt: date,
                lastSweepAt: date,
                lastAttemptAt: nil,
                resumeAfterProviderID: nil,
                failedProviderIDs: []
            )
        )
    }

    /// A crawl that reached the end of the directory with sets still failing.
    ///
    /// The cursor and the failed ids are kept, so the next attempt retries only
    /// what is outstanding rather than re-crawling everything an hour later.
    /// `lastSweepAt` is what stops that from being permanent: once it ages past
    /// the refresh interval, `needsFullSweep` sends the crawl back to the start
    /// even though the failures are unresolved.
    func markRefreshSwept(at date: Date = .now) {
        let previous = loadRefreshState()
        writeRefreshState(
            PokemonChecklistRefreshState(
                lastSuccessfulAt: previous?.lastSuccessfulAt,
                lastSweepAt: date,
                lastAttemptAt: date,
                resumeAfterProviderID: previous?.resumeAfterProviderID,
                failedProviderIDs: previous?.failedProviderIDs ?? []
            )
        )
    }

    /// Records a crawl that could not start — an unreachable or unusable set
    /// directory. There is no per-set evidence to record, so this is the only
    /// thing standing between an outage and one crawl attempt per foreground.
    func markRefreshAttempted(at date: Date = .now) {
        let previous = loadRefreshState()
        writeRefreshState(
            PokemonChecklistRefreshState(
                lastSuccessfulAt: previous?.lastSuccessfulAt,
                lastSweepAt: previous?.lastSweepAt,
                lastAttemptAt: date,
                resumeAfterProviderID: previous?.resumeAfterProviderID,
                failedProviderIDs: previous?.failedProviderIDs ?? []
            )
        )
    }

    /// Drop decoded checklist values under memory pressure while retaining the
    /// tiny manifests. The next set lookup simply decodes that set again.
    func discardDecodedChecklists() {
        downloadedChecklistCache = BoundedCache<String, [CatalogCardSummary]>(capacity: 10)
        bundledChecklistCache = BoundedCache<String, [CatalogCardSummary]>(capacity: 10)
        unreadableChecklistIDs.removeAll()
        downloadedSnapshotCache = nil
        bundledSnapshotCache = nil
    }

    private func installMemoryWarningObserverIfNeeded() {
        guard memoryWarningObserver == nil else { return }
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { await self?.discardDecodedChecklists() }
        }
    }

    /// Files are written using unique resource names and the manifest is the
    /// final write. A cancellation or malformed response cannot replace the
    /// last manifest because the caller only invokes this after full building.
    func publish(_ snapshot: PokemonChecklistSnapshot) throws {
        try publish(snapshot, mergingExisting: true, removingStaleResources: false)
    }

    /// Replaces a generated snapshot directory exactly. Release generation is
    /// not an incremental refresh: stale resources from an older partial run
    /// must not survive beside the new manifest.
    func replace(_ snapshot: PokemonChecklistSnapshot) throws {
        try publish(snapshot, mergingExisting: false, removingStaleResources: true)
    }

    private func publish(
        _ snapshot: PokemonChecklistSnapshot,
        mergingExisting: Bool,
        removingStaleResources: Bool
    ) throws {
        guard snapshot.manifest.isSupported,
              !snapshot.manifest.entries.isEmpty else {
            throw PokemonChecklistError.malformedSnapshot
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // A refresh is allowed to publish one set at a time. Always merge that
        // partial overlay with the last valid manifest before writing so a
        // later set failure can never erase earlier progress. The generator
        // opts out because its output must be an exact directory replacement.
        let merged: PokemonChecklistSnapshot?
        if mergingExisting {
            let existingEntries = validEntries(from: downloadedManifest(), directory: root)
            let entries = mergeEntries(
                bundled: existingEntries,
                downloaded: snapshot.manifest.entries
            )
            merged = PokemonChecklistSnapshot(
                manifest: PokemonChecklistSnapshotManifest(
                    schemaVersion: snapshot.manifest.schemaVersion,
                    rulesVersion: snapshot.manifest.rulesVersion,
                    generatedAt: snapshot.manifest.generatedAt,
                    directoryFingerprint: PokemonMasterSetChecklistBuilder.directoryFingerprint(entries),
                    entries: entries
                ),
                checklists: snapshot.checklists
            )
        } else {
            merged = snapshot
        }
        guard let merged else {
            throw PokemonChecklistError.malformedSnapshot
        }
        let mergedManifest = PokemonChecklistSnapshotManifest(
            schemaVersion: merged.manifest.schemaVersion,
            rulesVersion: merged.manifest.rulesVersion,
            generatedAt: snapshot.manifest.generatedAt,
            directoryFingerprint: PokemonMasterSetChecklistBuilder.directoryFingerprint(
                merged.manifest.entries
            ),
            entries: merged.manifest.entries
        )
        let publishable = PokemonChecklistSnapshot(
            manifest: mergedManifest,
            checklists: merged.checklists
        )

        if removingStaleResources {
            let resourceDirectory = root.appendingPathComponent("sets", isDirectory: true)
            if FileManager.default.fileExists(atPath: resourceDirectory.path) {
                try FileManager.default.removeItem(at: resourceDirectory)
            }
        }

        // Only the incoming overlay needs new resource bytes. Existing
        // resources are already protected by the old manifest and remain in
        // place, which keeps a per-set refresh from rewriting the full catalog.
        for entry in snapshot.manifest.entries {
            guard let cards = snapshot.checklists[entry.set.id] else {
                throw PokemonChecklistError.malformedSnapshot
            }
            let file = root.appendingPathComponent(entry.resource)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(cards).write(to: file, options: .atomic)
        }

        let manifestURL = root.appendingPathComponent("manifest.json")
        try encoder.encode(publishable.manifest).write(to: manifestURL, options: .atomic)
        if !removingStaleResources {
            removeUnreferencedResources(keeping: Set(publishable.manifest.entries.map(\.resource)))
        }
        downloadedSnapshotCache = nil
        downloadedManifestCache = publishable.manifest
        didLoadDownloadedManifest = true
        for entry in snapshot.manifest.entries {
            if let cards = snapshot.checklists[entry.set.id] {
                downloadedChecklistCache[entry.set.id] = cards
                unreadableChecklistIDs.remove(entry.set.id)
            }
        }
    }

    /// Remove superseded set resources only after the new manifest is durable.
    /// A failed refresh therefore leaves the previous manifest and all of its
    /// files usable, while a successful refresh cannot grow the directory
    /// forever as provider fingerprints change.
    private func removeUnreferencedResources(keeping resources: Set<String>) {
        let resourceDirectory = root.appendingPathComponent("sets", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: resourceDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for file in files where !resources.contains("sets/" + file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func loadSnapshot(from directory: URL) -> PokemonChecklistSnapshot? {
        guard let manifest = loadManifest(from: directory) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var validEntries: [PokemonChecklistSnapshotEntry] = []
        var checklists: [String: [CatalogCardSummary]] = [:]
        for entry in manifest.entries {
            guard case let .loaded(cards) = loadChecklist(
                for: entry,
                in: directory,
                decoder: decoder
            ) else {
                // One damaged or interrupted resource must not hide the rest of
                // an otherwise useful offline catalog.
                continue
            }
            validEntries.append(entry)
            checklists[entry.set.id] = cards
        }
        guard !validEntries.isEmpty else { return nil }
        let validManifest = PokemonChecklistSnapshotManifest(
            schemaVersion: manifest.schemaVersion,
            rulesVersion: manifest.rulesVersion,
            generatedAt: manifest.generatedAt,
            directoryFingerprint: manifest.directoryFingerprint,
            entries: validEntries
        )
        return PokemonChecklistSnapshot(manifest: validManifest, checklists: checklists)
    }

    private func downloadedManifest() -> PokemonChecklistSnapshotManifest? {
        guard !didLoadDownloadedManifest else { return downloadedManifestCache }
        didLoadDownloadedManifest = true
        downloadedManifestCache = loadManifest(from: root)
        return downloadedManifestCache
    }

    private func bundledManifest() -> PokemonChecklistSnapshotManifest? {
        guard !didLoadBundledManifest, let bundledRoot else {
            return bundledManifestCache
        }
        didLoadBundledManifest = true
        bundledManifestCache = loadManifest(from: bundledRoot)
        return bundledManifestCache
    }

    private func validEntries(
        from manifest: PokemonChecklistSnapshotManifest?,
        directory: URL?
    ) -> [PokemonChecklistSnapshotEntry] {
        guard let manifest, let directory else { return [] }
        return manifest.entries.filter {
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent($0.resource).path
            )
        }
    }

    private func mergeEntries(
        bundled: [PokemonChecklistSnapshotEntry],
        downloaded: [PokemonChecklistSnapshotEntry]
    ) -> [PokemonChecklistSnapshotEntry] {
        var entriesByID: [String: PokemonChecklistSnapshotEntry] = [:]
        var order: [String] = []
        for entry in bundled + downloaded {
            if entriesByID[entry.set.id] == nil { order.append(entry.set.id) }
            entriesByID[entry.set.id] = entry
        }
        return order.compactMap { entriesByID[$0] }
    }

    private func loadManifest(from directory: URL) -> PokemonChecklistSnapshotManifest? {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? decoder.decode(
                PokemonChecklistSnapshotManifest.self,
                from: manifestData
              ),
              manifest.isSupported else {
            return nil
        }
        return manifest
    }

    private func loadChecklist(
        for entry: PokemonChecklistSnapshotEntry,
        in directory: URL,
        decoder: JSONDecoder = JSONDecoder()
    ) -> ChecklistLoadOutcome {
        let file = directory.appendingPathComponent(entry.resource)
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            return .unreadable
        }
        do {
            return .loaded(try decoder.decode([CatalogCardSummary].self, from: data))
        } catch {
            return .undecodable
        }
    }

    private func loadRefreshState() -> PokemonChecklistRefreshState? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: refreshStateURL) else { return nil }
        return try? decoder.decode(PokemonChecklistRefreshState.self, from: data)
    }

    private func writeRefreshState(_ state: PokemonChecklistRefreshState) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: refreshStateURL, options: .atomic)
    }
}

#if DEBUG
/// Release tooling calls this from a test so the generator uses exactly the
/// same builder as the app. It is excluded from production builds.
enum PokemonChecklistSnapshotGenerator {
    static func generate(
        transport: any PokemonBrowseTransport,
        outputDirectory: URL,
        setIDs: Set<String>? = nil
    ) async throws {
        let rows = try await transport.fetchSetDirectory()
        let pocketIDs = (try? await transport.fetchPocketSetIDs()) ?? []
        let baseSets = PokemonMasterSetChecklistBuilder.baseSets(
            from: rows,
            excluding: pocketIDs
        )
        let normalizedFilter = setIDs?.map { $0.lowercased() }
        let selectedSets = normalizedFilter.map { filter in
            baseSets.filter { filter.contains($0.providerID.lowercased()) }
        } ?? baseSets
        let built = try await buildAll(
            baseSets: selectedSets,
            transport: transport
        )
        let snapshot = PokemonChecklistSnapshot.from(builtSets: built)
        let requiredIDs = normalizedFilter ?? SetCodeMap.definitions.values.map {
            $0.tcgdexSetID.lowercased()
        }
        let builtIDs = Set(built.map { $0.set.providerID.lowercased() })
        let missing = Set(requiredIDs).subtracting(builtIDs)
        guard missing.isEmpty else {
            throw PokemonChecklistError.missingModernSetCoverage(Array(missing))
        }
        let store = PokemonChecklistStore(root: outputDirectory, bundle: nil)
        try await store.replace(snapshot)
    }

    private static func buildAll(
        baseSets: [CatalogSet],
        transport: any PokemonBrowseTransport
    ) async throws -> [PokemonMasterSetChecklistBuilder.BuiltSet] {
        var result: [PokemonMasterSetChecklistBuilder.BuiltSet] = []
        var iterator = baseSets.makeIterator()
        try await withThrowingTaskGroup(of: [PokemonMasterSetChecklistBuilder.BuiltSet].self) { group in
            for _ in 0..<min(3, baseSets.count) {
                guard let set = iterator.next() else { break }
                group.addTask { try await build(set: set, transport: transport) }
            }
            while let value = try await group.next() {
                result.append(contentsOf: value)
                if let set = iterator.next() {
                    group.addTask { try await build(set: set, transport: transport) }
                }
            }
        }
        return result.sorted { $0.set.id < $1.set.id }
    }

    private static func build(
        set: CatalogSet,
        transport: any PokemonBrowseTransport
    ) async throws -> [PokemonMasterSetChecklistBuilder.BuiltSet] {
        let provider = try await transport.fetchSet(id: set.providerID)
        var details: [String: TCGdexCard] = [:]
        var iterator = provider.cards.makeIterator()
        try await withThrowingTaskGroup(of: (String, TCGdexCard).self) { group in
            for _ in 0..<min(8, provider.cards.count) {
                guard let card = iterator.next() else { break }
                group.addTask { (card.id, try await transport.fetchCard(id: card.id)) }
            }
            while let value = try await group.next() {
                details[value.0] = value.1
                if let card = iterator.next() {
                    group.addTask { (card.id, try await transport.fetchCard(id: card.id)) }
                }
            }
        }
        return try PokemonMasterSetChecklistBuilder.build(
            providerSet: provider,
            baseSet: set,
            cardDetails: details
        )
    }

}
#endif
