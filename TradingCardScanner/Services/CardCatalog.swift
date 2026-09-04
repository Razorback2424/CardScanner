import Foundation

/// Why a lookup failed, in the only terms the scanner cares about.
enum CatalogFailure: Equatable {
    /// The identifier was read correctly but no such record exists, or the record
    /// contradicts what was printed on the card. Re-reading the same card will
    /// fail the same way, so the scanner keeps its latch and asks the user to set
    /// the card aside instead of retrying in a loop.
    case notInCatalog
    /// Network or server trouble. Nothing was written and nothing is known to be
    /// wrong with the card, so the very next reading should be allowed through.
    case transient
}

enum PokemonHistoricalCatalogError: Error, Sendable {
    case ambiguous([PokemonCatalogCardIdentity])
    case unsupported
}
/// A small, identity-only Pokémon record assembled from the on-device Browse
/// checklist. The checklist is authoritative for the set/card relationship, but
/// it deliberately does not pretend to contain live market data.
enum PokemonOfflineCardFactory {
    private static func makeCard(
        summaries: [CatalogCardSummary],
        setName: String,
        providerSetID: String,
        officialCount: Int
    ) -> TCGdexCard {
        // One numbered Pokémon card may occupy several checklist rows: normal,
        // holo, reverse, and named parallels are all distinct physical objects.
        // The offline snapshot has no live prices, but it does have authoritative
        // variant evidence. Preserve that evidence so the same resolver used by
        // collection scans can choose one variant or ask the user.
        let variants = Set(summaries.compactMap(\.masterSetVariant))
        let hasNormal = variants.contains(.normal)
        let hasHolo = variants.contains(.holo)
        let hasReverse = variants.contains(.reverse)
        let hasFirstEdition = variants.contains(.firstEdition)
        let namedVariants = variants.filter {
            ![PhysicalVariant.normal, .holo, .reverse, .firstEdition].contains($0)
        }
        let detailedVariants = namedVariants.map { variant in
            TCGdexDetailedVariant(
                type: "reverse",
                subtype: nil,
                stamp: nil,
                foil: variant.id,
                size: nil,
                variantId: nil,
                pricing: nil,
                languages: ["en"],
                thirdParty: nil
            )
        }
        let count = TCGdexCardCount(
            total: max(officialCount, 0),
            official: max(officialCount, 0)
        )
        let brief = TCGdexSetBrief(
            id: providerSetID,
            name: setName,
            cardCount: count
        )
        return TCGdexCard(
            id: summaries[0].providerID,
            localId: summaries[0].collectorNumber,
            name: summaries[0].name,
            image: summaries.compactMap { imageBaseURL(for: $0.imageURL) }.first,
            rarity: nil,
            set: brief,
            variants: variants.isEmpty
                ? nil
                : TCGdexVariants(
                    firstEdition: hasFirstEdition,
                    holo: hasHolo,
                    normal: hasNormal,
                    reverse: hasReverse,
                    wPromo: nil
                ),
            pricing: nil,
            variantsDetailed: detailedVariants.isEmpty ? nil : detailedVariants
        )
    }

    static func card(
        in snapshot: PokemonChecklistSnapshot,
        providerSetID: String,
        localID: String,
        expectedOfficialCount: Int?
    ) -> TCGdexCard? {
        let matchingEntries = snapshot.manifest.entries.filter {
            $0.providerID.caseInsensitiveCompare(providerSetID) == .orderedSame
                && $0.set.pokemonPrintRun == nil
        }

        for entry in matchingEntries {
            guard let cards = snapshot.checklists[entry.set.id] else { continue }
            let matches = cards.filter {
                $0.game == .pokemon
                    && $0.setID.providerID.caseInsensitiveCompare(providerSetID) == .orderedSame
                    && PokemonHistoricalIdentityResolver.canonicalLocalID($0.collectorNumber)
                        == PokemonHistoricalIdentityResolver.canonicalLocalID(localID)
            }
            let summaries = matches.sorted { left, right in
                let leftVariant = left.masterSetVariant?.id ?? ""
                let rightVariant = right.masterSetVariant?.id ?? ""
                return (leftVariant, left.id) < (rightVariant, right.id)
            }
            guard !summaries.isEmpty else { continue }

            return makeCard(
                summaries: summaries,
                setName: entry.set.name,
                providerSetID: providerSetID,
                officialCount: expectedOfficialCount ?? entry.set.cardCount ?? 0
            )
        }
        return nil
    }

    static func historicalCard(
        in snapshot: PokemonChecklistSnapshot,
        evidence: PokemonHistoricalScanEvidence
    ) -> IdentifiedCard? {
        let candidateSetIDs: Set<String>
        switch evidence.number.scheme {
        case .officialSet:
            // `entry.set.cardCount` is the master-set count and may include
            // secret rares/parallel rows. Use the provider denominator saved
            // by the snapshot builder, with the modern map as a compatibility
            // fallback for older manifests that predate this field.
            candidateSetIDs = Set(snapshot.manifest.entries.compactMap { entry in
                let officialCount = entry.officialCount ?? SetCodeMap.definitions.values.first {
                    $0.tcgdexSetID.caseInsensitiveCompare(entry.providerID) == .orderedSame
                }?.officialCount
                return officialCount == evidence.number.denominator
                    ? entry.providerID.lowercased()
                    : nil
            })
        case .subset:
            candidateSetIDs = Set(
                PokemonHistoricalIdentityResolver.candidateSetIDs(
                    for: evidence.number,
                    in: []
                )
            )
        }
        guard !candidateSetIDs.isEmpty else { return nil }

        var identitiesByProviderID: [String: PokemonCatalogCardIdentity] = [:]
        var summariesByProviderID: [String: (summary: CatalogCardSummary, set: CatalogSet)] = [:]
        for entry in snapshot.manifest.entries where candidateSetIDs.contains(entry.providerID.lowercased()) {
            guard let cards = snapshot.checklists[entry.set.id] else { continue }
            for summary in cards where summary.game == .pokemon {
                let providerID = summary.providerID.lowercased()
                identitiesByProviderID[providerID] = PokemonCatalogCardIdentity(
                    providerID: summary.providerID,
                    setID: entry.providerID,
                    setName: entry.set.name,
                    localID: summary.collectorNumber,
                    name: summary.name
                )
                summariesByProviderID[providerID] = (summary, entry.set)
            }
        }

        switch PokemonHistoricalIdentityResolver.resolve(
            evidence,
            candidateSetIDs: Array(candidateSetIDs),
            in: Array(identitiesByProviderID.values)
        ) {
        case let .unique(identity):
            guard let value = summariesByProviderID[identity.providerID.lowercased()] else {
                return nil
            }
            let officialCount = evidence.number.denominator
            let card = makeCard(
                summaries: [value.summary],
                setName: identity.setName,
                providerSetID: identity.setID,
                officialCount: officialCount
            )
            return .pokemon(card, setCode: value.summary.setCode)
        case .ambiguous, .unsupported:
            // The offline snapshot must preserve the same conservative rule as
            // the live historical resolver. A missing or colliding title is not
            // permission to pick the first summary.
            return nil
        }
    }

    private static func imageBaseURL(for imageURL: URL?) -> String? {
        guard let imageURL else { return nil }
        let path = imageURL.path
        for suffix in ["/high.png", "/low.png"] where path.hasSuffix(suffix) {
            let basePath = String(path.dropLast(suffix.count))
            var components = URLComponents(url: imageURL, resolvingAgainstBaseURL: false)
            components?.path = basePath
            return components?.url?.absoluteString
        }
        return imageURL.absoluteString
    }
}

actor PokemonOfflineCatalog {
    private let store: PokemonChecklistStore
    private var entries: [PokemonChecklistSnapshotEntry] = []
    private var didLoad = false
    private var loadTask: Task<[PokemonChecklistSnapshotEntry], Never>?

    init(store: PokemonChecklistStore = .shared) {
        self.store = store
    }

    func card(
        providerSetID: String,
        localID: String,
        expectedOfficialCount: Int?
    ) async -> TCGdexCard? {
        await loadIfNeeded()
        for entry in entries where
            entry.providerID.caseInsensitiveCompare(providerSetID) == .orderedSame
            && entry.set.pokemonPrintRun == nil {
            guard let cards = await store.mergedChecklist(for: entry.set.catalogID) else { continue }
            let snapshot = snapshot(entry: entry, cards: cards)
            if let card = PokemonOfflineCardFactory.card(
                in: snapshot,
                providerSetID: providerSetID,
                localID: localID,
                expectedOfficialCount: expectedOfficialCount
            ) {
                return card
            }
        }
        return nil
    }

    func contains(
        providerSetID: String,
        localID: String,
        expectedOfficialCount: Int?
    ) async -> Bool {
        await card(
            providerSetID: providerSetID,
            localID: localID,
            expectedOfficialCount: expectedOfficialCount
        ) != nil
    }

    func historicalCard(for evidence: PokemonHistoricalScanEvidence) async -> IdentifiedCard? {
        await loadIfNeeded()
        let candidateSetIDs: Set<String>
        switch evidence.number.scheme {
        case .officialSet:
            candidateSetIDs = Set(entries.compactMap { entry in
                let officialCount = entry.officialCount ?? SetCodeMap.definitions.values.first {
                    $0.tcgdexSetID.caseInsensitiveCompare(entry.providerID) == .orderedSame
                }?.officialCount
                return officialCount == evidence.number.denominator
                    ? entry.providerID.lowercased()
                    : nil
            })
        case .subset:
            candidateSetIDs = Set(
                PokemonHistoricalIdentityResolver.candidateSetIDs(
                    for: evidence.number,
                    in: []
                )
            )
        }
        guard !candidateSetIDs.isEmpty else { return nil }

        var matchingEntries: [PokemonChecklistSnapshotEntry] = []
        var checklists: [String: [CatalogCardSummary]] = [:]
        for entry in entries where candidateSetIDs.contains(entry.providerID.lowercased()) {
            guard let cards = await store.mergedChecklist(for: entry.set.catalogID) else { continue }
            matchingEntries.append(entry)
            checklists[entry.set.id] = cards
        }
        guard !matchingEntries.isEmpty else { return nil }
        let manifest = PokemonChecklistSnapshotManifest(
            schemaVersion: PokemonChecklistSnapshotVersion.schema,
            rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
            generatedAt: .now,
            directoryFingerprint: "lazy",
            entries: matchingEntries
        )
        let snapshot = PokemonChecklistSnapshot(manifest: manifest, checklists: checklists)
        return PokemonOfflineCardFactory.historicalCard(in: snapshot, evidence: evidence)
    }

    func prewarm() async {
        await loadIfNeeded()
    }

    private func loadIfNeeded() async {
        guard !didLoad else { return }
        let task: Task<[PokemonChecklistSnapshotEntry], Never>
        if let existing = loadTask {
            task = existing
        } else {
            let store = store
            let newTask = Task<[PokemonChecklistSnapshotEntry], Never> {
                await store.mergedEntries()
            }
            loadTask = newTask
            task = newTask
        }

        let loaded = await task.value
        guard !Task.isCancelled else { return }
        loadTask = nil
        entries = loaded
        didLoad = true
    }

    private func snapshot(
        entry: PokemonChecklistSnapshotEntry,
        cards: [CatalogCardSummary]
    ) -> PokemonChecklistSnapshot {
        PokemonChecklistSnapshot(
            manifest: PokemonChecklistSnapshotManifest(
                schemaVersion: PokemonChecklistSnapshotVersion.schema,
                rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
                generatedAt: .now,
                directoryFingerprint: "lazy",
                entries: [entry]
            ),
            checklists: [entry.set.id: cards]
        )
    }
}


/// Prevents every scan frame from opening another doomed TCGdex connection
/// while the provider is timing out. A success closes the circuit immediately;
/// only provider failures open it.
actor TCGdexCircuitBreaker {
    /// Outage state belongs to the host, not to whichever type noticed first.
    /// The catalog and the price refresher both talk to TCGdex, and a private
    /// breaker each meant the second caller re-paid the connect timeout the
    /// first had already established was hopeless.
    static let shared = TCGdexCircuitBreaker()

    /// How badly the provider failed, which decides how long to stay away.
    ///
    /// These are not the same outage. A 5xx is a host that answered — the next
    /// request may well succeed, and banishing it for ten minutes would throw
    /// away a working provider. A refused or timed-out connection is a host
    /// that is not there, and re-probing it costs the full timeout every time.
    enum Failure: Equatable {
        /// The host answered, badly. Retry soon.
        case serverError
        /// Nothing answered: connection refused, DNS failure, or timeout.
        case unreachable

        var base: TimeInterval {
            switch self {
            case .serverError: return 10
            case .unreachable: return 30
            }
        }

        var cap: TimeInterval {
            switch self {
            case .serverError: return 60
            case .unreachable: return 600
            }
        }
    }

    private let baseCooldown: TimeInterval?
    private var unavailableUntil: Date?
    /// Survives cooldown expiry on purpose. A probe that fails again must back
    /// off further than the one before it, which cannot happen if the count is
    /// cleared every time the door is reopened.
    private var consecutiveFailures = 0

    /// - Parameter cooldown: fixes the cooldown at one value, for tests that
    ///   need a deterministic window. Production leaves this nil and lets the
    ///   failure kind decide.
    init(cooldown: TimeInterval? = nil) {
        self.baseCooldown = cooldown.map { max($0, 0) }
    }

    func permitsRequest(now: Date = .now) -> Bool {
        guard let unavailableUntil else { return true }
        if now >= unavailableUntil {
            self.unavailableUntil = nil
            return true
        }
        return false
    }

    func recordSuccess() {
        unavailableUntil = nil
        consecutiveFailures = 0
    }

    func recordFailure(_ failure: Failure = .unreachable, now: Date = .now) {
        consecutiveFailures += 1
        unavailableUntil = now.addingTimeInterval(cooldown(for: failure))
    }

    private func cooldown(for failure: Failure) -> TimeInterval {
        if let baseCooldown { return baseCooldown }
        // 30s, 60, 120, 240 … capped. `consecutiveFailures` is at least 1 here.
        let exponent = min(consecutiveFailures - 1, 16)
        let scaled = failure.base * pow(2, Double(exponent))
        return min(scaled, failure.cap)
    }
}

/// The two provider calls used on the Pokémon scan path. Keeping them behind a
/// single seam makes the fallback order testable without URL loading, while the
/// concrete adapter preserves the production timeouts and retry behavior.
protocol PokemonCardSource: Sendable {
    func fetchTCGdexCard(setID: String, localID: String) async throws -> TCGdexCard
    func fetchPokemonTCGCard(setID: String, cardNumber: String) async throws -> PokemonTCGAPICard?
}

struct LivePokemonCardSource: PokemonCardSource, Sendable {
    private let tcgdex = TCGdexService()
    private let pokemonTCG = PokemonTCGAPIService()

    func fetchTCGdexCard(setID: String, localID: String) async throws -> TCGdexCard {
        // Keep the service default. In particular, do not add a shorter scan
        // timeout here; the provider default is the shared transport contract.
        try await tcgdex.fetchCard(setID: setID, localID: localID)
    }

    func fetchPokemonTCGCard(setID: String, cardNumber: String) async throws -> PokemonTCGAPICard? {
        try await pokemonTCG.fetchCard(setID: setID, cardNumber: cardNumber)
    }
}

/// Identity-only disk cache for cards that are outside the bundled modern
/// checklist. Prices and finish claims are deliberately excluded; a cache hit
/// is enough to route the card into the existing finish/price flows, not to make
/// a stale market-data claim.
actor ResolvedPokemonCardCache {
    private static let writeQueue = DispatchQueue(
        label: "TradingCardScanner.ResolvedPokemonCardCache",
        qos: .utility
    )

    private struct Entry: Codable, Sendable {
        let key: String
        let storedAt: Date
        let cardID: String
        let localID: String
        let name: String
        let image: String?
        let rarity: String?
        let setID: String
        let setName: String
        let officialCount: Int
        let setCode: String
        /// The cache must preserve the physical objects published by the
        /// catalog. An empty list cannot answer the finish question and is
        /// therefore never served as a cache hit.
        let variants: [PhysicalVariant]

        enum CodingKeys: String, CodingKey {
            case key, storedAt, cardID, localID, name, image, rarity
            case setID, setName, officialCount, setCode, variants
        }

        init(
            key: String,
            storedAt: Date,
            cardID: String,
            localID: String,
            name: String,
            image: String?,
            rarity: String?,
            setID: String,
            setName: String,
            officialCount: Int,
            setCode: String,
            variants: [PhysicalVariant]
        ) {
            self.key = key
            self.storedAt = storedAt
            self.cardID = cardID
            self.localID = localID
            self.name = name
            self.image = image
            self.rarity = rarity
            self.setID = setID
            self.setName = setName
            self.officialCount = officialCount
            self.setCode = setCode
            self.variants = variants
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            key = try container.decode(String.self, forKey: .key)
            storedAt = try container.decode(Date.self, forKey: .storedAt)
            cardID = try container.decode(String.self, forKey: .cardID)
            localID = try container.decode(String.self, forKey: .localID)
            name = try container.decode(String.self, forKey: .name)
            image = try container.decodeIfPresent(String.self, forKey: .image)
            rarity = try container.decodeIfPresent(String.self, forKey: .rarity)
            setID = try container.decode(String.self, forKey: .setID)
            setName = try container.decode(String.self, forKey: .setName)
            officialCount = try container.decode(Int.self, forKey: .officialCount)
            setCode = try container.decode(String.self, forKey: .setCode)
            variants = try container.decodeIfPresent([PhysicalVariant].self, forKey: .variants) ?? []
        }
    }

    private struct File: Codable, Sendable {
        let appVersion: String
        /// Bumped when cache validity rules change independently from the app
        /// marketing version. Optional so pre-generation files decode and are
        /// deliberately rejected by the reader below.
        let schemaGeneration: Int?
        let entries: [Entry]
    }

    /// Generation 2 discards entries written before the cache's provenance
    /// gate. Those files cannot distinguish a complete primary-provider card
    /// from outage-time fallback data that lacked variant evidence.
    private static let schemaGeneration = 2
    private static let maxAge: TimeInterval = 28 * 24 * 60 * 60
    private static let maxEntries = 512

    private let fileURL: URL
    private let appVersion: String
    private var entries: [String: Entry] = [:]
    private var didLoad = false

    init(root: URL? = nil, appVersion: String? = nil) {
        let cacheRoot = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("BrowseCatalogCache", isDirectory: true)
        self.fileURL = cacheRoot.appendingPathComponent("ResolvedPokemonCards.json")
        self.appVersion = appVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "development"
    }

    func prewarm() async {
        loadIfNeeded()
    }

    func card(for key: String) -> (card: TCGdexCard, setCode: String)? {
        loadIfNeeded()
        guard let entry = entries[key] else { return nil }
        guard Date.now.timeIntervalSince(entry.storedAt) <= Self.maxAge else {
            entries[key] = nil
            persist()
            return nil
        }
        // A cache hit that knows no finishes is worse than a miss: it shadows
        // the bundled checklist and forces VariantResolver into
        // `.catalogSilent`. Remove it so this scan falls through to richer
        // offline or live catalog evidence.
        guard !entry.variants.isEmpty else {
            entries[key] = nil
            persist()
            return nil
        }
        let count = TCGdexCardCount(total: entry.officialCount, official: entry.officialCount)
        let card = TCGdexCard(
            id: entry.cardID,
            localId: entry.localID,
            name: entry.name,
            image: entry.image,
            rarity: entry.rarity,
            set: TCGdexSetBrief(id: entry.setID, name: entry.setName, cardCount: count),
            variants: TCGdexVariants(
                firstEdition: entry.variants.contains(.firstEdition),
                holo: entry.variants.contains(.holo),
                normal: entry.variants.contains(.normal),
                reverse: entry.variants.contains(.reverse),
                wPromo: nil
            ),
            pricing: nil,
            variantsDetailed: entry.variants
                .filter { ![.normal, .holo, .reverse, .firstEdition].contains($0) }
                .map { variant in
                    TCGdexDetailedVariant(
                        type: "reverse",
                        subtype: nil,
                        stamp: nil,
                        foil: variant.id,
                        size: nil,
                        variantId: nil,
                        pricing: nil,
                        languages: ["en"],
                        thirdParty: nil
                    )
                }
        )
        return (card, entry.setCode)
    }

    func store(
        card: TCGdexCard,
        setCode: String,
        key: String,
        officialCount: Int? = nil
    ) {
        loadIfNeeded()
        let variants = card.catalogVariants
        guard !variants.isEmpty else {
            // An incomplete live response is not evidence that an already
            // cached, fully resolved card ceased to have finishes. Retain the
            // complete entry and let this response fall through to the
            // checklist or a later provider retry instead.
            return
        }
        entries[key] = Entry(
            key: key,
            storedAt: .now,
            cardID: card.id,
            localID: card.localId,
            name: card.name,
            image: card.image,
            rarity: card.rarity,
            setID: card.set.id,
            setName: card.set.name,
            officialCount: officialCount ?? card.set.cardCount.official,
            setCode: setCode,
            variants: variants
        )
        if entries.count > Self.maxEntries {
            let oldest = entries.values
                .sorted { $0.storedAt < $1.storedAt }
                .prefix(entries.count - Self.maxEntries)
            for entry in oldest { entries[entry.key] = nil }
        }
        persist()
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        // A cold cache reader may be a new catalog instance racing the prior
        // instance's background write. Flush the shared utility queue before
        // reading, while resolution itself never awaits the write operation.
        Self.writeQueue.sync {}
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? decoder.decode(File.self, from: data),
              file.appVersion == appVersion,
              file.schemaGeneration == Self.schemaGeneration else {
            return
        }
        let cutoff = Date.now.addingTimeInterval(-Self.maxAge)
        entries = file.entries.reduce(into: [:]) { values, entry in
            guard !entry.key.isEmpty, entry.storedAt >= cutoff else { return }
            // A partially recovered or hand-edited cache may contain duplicate
            // keys. Keep the newest record rather than crashing the scanner
            // while constructing a dictionary with uniqueKeysWithValues.
            if let current = values[entry.key], current.storedAt >= entry.storedAt {
                return
            }
            values[entry.key] = entry
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let file = File(
            appVersion: appVersion,
            schemaGeneration: Self.schemaGeneration,
            entries: Array(entries.values)
        )
        guard let data = try? encoder.encode(file) else { return }
        let fileURL = fileURL
        Self.writeQueue.async {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: fileURL, options: .atomic)
            } catch {
                // Disk cache failure must never affect identification.
            }
        }
    }
}

/// Turns identifiers into catalog records, overlapping the network with OCR
/// instead of waiting for one to finish before starting the other.
///
/// The old shape was strictly serial:
///
///     OCR -> confirm -> request -> wait -> result
///
/// The moment a *plausible* identifier appears the request can already be in
/// flight while Vision keeps looking for its second matching observation. The
/// cost becomes `max(confirmation, network)` rather than their sum, and accuracy
/// is untouched because a speculative result is only ever consumed by the exact
/// identifier that was confirmed. A speculation that turns out to be a misread is
/// inert: it is filed under the identifier nobody will ask for.
///
/// The session cache is the other half. A second copy of a printing already
/// resolved this session needs no round trip at all.
actor CardCatalog {
    private let pokemonSource: any PokemonCardSource
    private let offline: PokemonOfflineCatalog
    private let resolvedDiskCache: ResolvedPokemonCardCache
    private let tcgdexBreaker: TCGdexCircuitBreaker
    private let scryfall = ScryfallService()
    private let historicalPokemon = PokemonHistoricalCatalog()

    /// One resolution plus where it came from.
    ///
    /// Provenance is what decides whether a result may be written to the
    /// identity disk cache, and only a live primary-provider response
    /// qualifies. The degraded outage-time fallback publishes no finishes and
    /// no pricing, so persisting it would let one bad afternoon strip a card of
    /// its variant question for the cache's whole 28-day life; the bundled
    /// checklist is already on disk in a richer form than the cache can hold.
    struct CatalogResolution: Sendable {
        let card: IdentifiedCard
        let isPersistable: Bool

        init(_ card: IdentifiedCard, isPersistable: Bool = false) {
            self.card = card
            self.isPersistable = isPersistable
        }
    }

    /// Bounded: see `BoundedCache`. Large enough that re-scanning a stack never
    /// evicts anything the user is actually working through, small enough that
    /// unstable OCR cannot grow it without limit.
    private var resolved = BoundedCache<ScanIdentifier, IdentifiedCard>(capacity: 256)
    private var inFlight: [ScanIdentifier: Task<CatalogResolution, Error>] = [:]

    init(
        source: any PokemonCardSource = LivePokemonCardSource(),
        offline: PokemonOfflineCatalog = PokemonOfflineCatalog(),
        resolvedDiskCache: ResolvedPokemonCardCache = ResolvedPokemonCardCache(),
        tcgdexBreaker: TCGdexCircuitBreaker = .shared
    ) {
        self.pokemonSource = source
        self.offline = offline
        self.resolvedDiskCache = resolvedDiskCache
        self.tcgdexBreaker = tcgdexBreaker
    }

    /// Starts loading both persistent sources before the camera begins feeding
    /// candidates. The calls are independent and safe to repeat for a session.
    func prewarm() async {
        async let offlineWarm: Void = offline.prewarm()
        async let diskWarm: Void = resolvedDiskCache.prewarm()
        _ = await (offlineWarm, diskWarm)
    }

    /// Start resolving an identifier that looks plausible but is not yet
    /// confirmed. Deliberately returns nothing: speculation must never be able to
    /// affect anything on its own.
    func prefetch(_ identifier: ScanIdentifier) {
        guard resolved[identifier] == nil, inFlight[identifier] == nil else { return }
        let task = start(identifier)
        Task { _ = await self.complete(identifier, task: task) }
    }

    func card(for identifier: ScanIdentifier) async throws -> IdentifiedCard {
        if let card = resolved[identifier] { return card }
        let task = inFlight[identifier] ?? start(identifier)
        return try await complete(identifier, task: task).get()
    }

    func cachedCard(for identifier: ScanIdentifier) -> IdentifiedCard? {
        resolved[identifier]
    }

    func card(
        for candidate: PokemonCatalogCardIdentity,
        matching evidence: PokemonHistoricalScanEvidence
    ) async throws -> IdentifiedCard {
        try await historicalPokemon.card(for: candidate, matching: evidence)
    }

    static func classify(_ error: Error) -> CatalogFailure {
        switch error {
        case is PokemonHistoricalCatalogError:
            return .notInCatalog
        case TCGdexError.cardNotFound, TCGdexError.identityMismatch, TCGdexError.invalidURL,
             ScryfallError.cardNotFound, ScryfallError.identityMismatch,
             ScryfallError.unsupportedPrinting, ScryfallError.invalidURL:
            return .notInCatalog
        default:
            return .transient
        }
    }

    private func start(_ identifier: ScanIdentifier) -> Task<CatalogResolution, Error> {
        let pokemonSource = pokemonSource
        let offline = offline
        let resolvedDiskCache = resolvedDiskCache
        let tcgdexBreaker = tcgdexBreaker
        let scryfall = scryfall
        let historicalPokemon = historicalPokemon
        let diskKey = Self.persistentKey(for: identifier)
        let task = Task<CatalogResolution, Error> {
            if let diskKey,
               let cached = await resolvedDiskCache.card(for: diskKey) {
                return CatalogResolution(.pokemon(cached.card, setCode: cached.setCode))
            }

            switch identifier {
            case let .pokemon(setCode, cardNumber, printedTotal, setDefinition):
                if let card = await offline.card(
                    providerSetID: setDefinition.tcgdexSetID,
                    localID: cardNumber,
                    expectedOfficialCount: printedTotal
                ) {
                    return CatalogResolution(.pokemon(card, setCode: setCode))
                }
                return try await Self.resolveModernPokemon(
                    setCode: setCode,
                    cardNumber: cardNumber,
                    setDefinition: setDefinition,
                    source: pokemonSource,
                    breaker: tcgdexBreaker
                )

            case let .pokemonPromo(prefix, localID, setDefinition):
                if let card = await offline.card(
                    providerSetID: setDefinition.tcgdexSetID,
                    localID: localID,
                    expectedOfficialCount: nil
                ) {
                    return CatalogResolution(.pokemon(card, setCode: prefix))
                }
                return try await Self.resolvePromoPokemon(
                    prefix: prefix,
                    localID: localID,
                    setDefinition: setDefinition,
                    source: pokemonSource,
                    breaker: tcgdexBreaker
                )

            case let .pokemonHistorical(evidence):
                if let card = await offline.historicalCard(for: evidence) {
                    return CatalogResolution(card)
                }
                return CatalogResolution(try await historicalPokemon.card(for: evidence))

            case let .magic(setCode, collectorNumber, language, contentKind):
                guard contentKind != .regular else {
                    // Unchanged fast path. An ordinary footer resolves exactly
                    // as it always has.
                    return CatalogResolution(
                        .magic(
                            try await scryfall.fetchCard(
                                setCode: setCode,
                                collectorNumber: collectorNumber,
                                language: language
                            )
                        )
                    )
                }

                // A token or art card prints its *parent's* code, so the printed
                // identity has to be mapped to the child set before anything is
                // fetched. `T 0017 MSH` is `TMSH 17`, not `MSH 17`.
                let children = try await scryfall.fetchChildSets()
                guard let child = ScryfallService.childSet(
                    for: contentKind,
                    parentCode: setCode,
                    in: children
                ) else {
                    // No child set, or more than one with no way to choose.
                    // Refusing is the point: reinterpreting an explicit marker
                    // as an ordinary card is the bug this exists to prevent.
                    throw ScryfallError.identityMismatch
                }

                let card = try await scryfall.fetchCard(
                    setCode: child.code,
                    collectorNumber: collectorNumber,
                    language: language,
                    requiresScannableCard: false
                )

                // Both directions are checked. The returned record must be from
                // the child set that was asked for, and its layout must match
                // the kind the marker claimed — otherwise a token could arrive
                // through an ordinary lookup, which is the same bug reversed.
                guard card.setCode.caseInsensitiveCompare(child.code) == .orderedSame,
                      let layout = card.layout,
                      contentKind.acceptedLayouts.contains(layout) else {
                    throw ScryfallError.identityMismatch
                }
                return CatalogResolution(.magic(card))
            }
        }
        inFlight[identifier] = task
        return task
    }

    private static func persistentKey(for identifier: ScanIdentifier) -> String? {
        switch identifier {
        case let .pokemon(_, cardNumber, printedTotal, setDefinition):
            return "pokemon|\(setDefinition.tcgdexSetID.lowercased())|\(PokemonHistoricalIdentityResolver.canonicalLocalID(cardNumber))|\(printedTotal)"
        case let .pokemonPromo(prefix, localID, setDefinition):
            return "pokemon-promo|\(prefix.uppercased())|\(setDefinition.tcgdexSetID.lowercased())|\(PokemonHistoricalIdentityResolver.canonicalLocalID(localID))"
        case .pokemonHistorical:
            // Historical identity is resolved from unstable OCR title evidence;
            // there is no safe stable key before the catalog response arrives.
            // Keep it session-cached only rather than poisoning the disk cache
            // with one key per OCR spelling.
            return nil
        case .magic:
            // The resolved disk cache is Pokémon-only. Never let a future
            // caller accidentally reinterpret a Magic hit as a Pokémon card.
            return nil
        }
    }

    private static func validate(
        _ card: TCGdexCard,
        setID: String,
        localID: String
    ) throws {
        guard card.set.id.caseInsensitiveCompare(setID) == .orderedSame,
              PokemonHistoricalIdentityResolver.canonicalLocalID(card.localId)
                == PokemonHistoricalIdentityResolver.canonicalLocalID(localID) else {
            throw TCGdexError.identityMismatch
        }
    }

    private static func breakerFailure(for error: Error) -> TCGdexCircuitBreaker.Failure {
        switch error {
        case TCGdexError.badResponse:
            return .serverError
        default:
            return .unreachable
        }
    }

    private static func fallbackPokemonCard(
        _ card: PokemonTCGAPICard,
        requestedSetID: String,
        requestedLocalID: String,
        officialCount: Int? = nil
    ) throws -> TCGdexCard {
        guard card.set.id?.caseInsensitiveCompare(requestedSetID) == .orderedSame,
              PokemonHistoricalIdentityResolver.canonicalLocalID(card.number)
                == PokemonHistoricalIdentityResolver.canonicalLocalID(requestedLocalID) else {
            throw TCGdexError.identityMismatch
        }
        let count = TCGdexCardCount(
            total: officialCount ?? card.set.printedTotal ?? 0,
            official: officialCount ?? card.set.printedTotal ?? 0
        )
        // pokemontcg.io uses unpadded ids (for example `sv10-85`) while
        // TCGdex's exact-card endpoint uses the printed/padded local id (such
        // as `sv10-085`). Keep the fallback result addressable by the primary
        // provider so the next Price Check or collection refresh can reprice it.
        return TCGdexCard(
            id: "\(requestedSetID)-\(requestedLocalID)",
            localId: requestedLocalID,
            name: card.name,
            image: card.images.large.absoluteString,
            rarity: nil,
            set: TCGdexSetBrief(
                id: card.set.id ?? requestedSetID,
                name: card.set.name,
                cardCount: count
            ),
            variants: nil,
            pricing: nil,
            variantsDetailed: nil
        )
    }

    private static func resolveModernPokemon(
        setCode: String,
        cardNumber: String,
        setDefinition: PokemonSetDefinition,
        source: any PokemonCardSource,
        breaker: TCGdexCircuitBreaker
    ) async throws -> CatalogResolution {
        if await breaker.permitsRequest() {
            do {
                let card = try await source.fetchTCGdexCard(
                    setID: setDefinition.tcgdexSetID,
                    localID: cardNumber
                )
                // The provider returned a complete, decodable card. Preserve
                // that host-health signal even when the card fails the exact
                // requested identity check below.
                await breaker.recordSuccess()
                try validate(card, setID: setDefinition.tcgdexSetID, localID: cardNumber)
                return CatalogResolution(
                    .pokemon(card, setCode: setCode),
                    isPersistable: true
                )
            } catch let error as TCGdexError {
                switch error {
                case .cardNotFound, .identityMismatch, .invalidURL:
                    throw error
                case .badResponse:
                    await breaker.recordFailure(.serverError)
                }
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                await breaker.recordFailure(Self.breakerFailure(for: error))
            }
        }

        guard let fallback = try await source.fetchPokemonTCGCard(
            setID: setDefinition.tcgdexSetID,
            cardNumber: cardNumber
        ) else {
            throw TCGdexError.cardNotFound
        }
        let card = try fallbackPokemonCard(
            fallback,
            requestedSetID: setDefinition.tcgdexSetID,
            requestedLocalID: cardNumber,
            officialCount: setDefinition.officialCount
        )
        // Deliberately not persistable. This record exists only because the
        // primary provider was unreachable, and it carries neither finishes nor
        // pricing; the session cache is the right lifetime for it.
        return CatalogResolution(.pokemon(card, setCode: setCode))
    }

    private static func resolvePromoPokemon(
        prefix: String,
        localID: String,
        setDefinition: PokemonPromoSetDefinition,
        source: any PokemonCardSource,
        breaker: TCGdexCircuitBreaker
    ) async throws -> CatalogResolution {
        if await breaker.permitsRequest() {
            do {
                let card = try await source.fetchTCGdexCard(
                    setID: setDefinition.tcgdexSetID,
                    localID: localID
                )
                await breaker.recordSuccess()
                try validate(card, setID: setDefinition.tcgdexSetID, localID: localID)
                return CatalogResolution(
                    .pokemon(card, setCode: prefix),
                    isPersistable: true
                )
            } catch let error as TCGdexError {
                switch error {
                case .cardNotFound, .identityMismatch, .invalidURL:
                    throw error
                case .badResponse:
                    await breaker.recordFailure(.serverError)
                }
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                await breaker.recordFailure(Self.breakerFailure(for: error))
            }
        }

        guard let fallback = try await source.fetchPokemonTCGCard(
            setID: setDefinition.tcgdexSetID,
            cardNumber: localID
        ) else {
            throw TCGdexError.cardNotFound
        }
        let card = try fallbackPokemonCard(
            fallback,
            requestedSetID: setDefinition.tcgdexSetID,
            requestedLocalID: localID
        )
        // Outage-time evidence only. See `resolveModernPokemon`.
        return CatalogResolution(.pokemon(card, setCode: prefix))
    }

    private func complete(
        _ identifier: ScanIdentifier,
        task: Task<CatalogResolution, Error>
    ) async -> Result<IdentifiedCard, Error> {
        let result = await task.result
        if case let .success(resolution) = result {
            let card = resolution.card
            resolved[identifier] = card
            // Only a live primary-provider response is written through. A
            // degraded fallback record would otherwise outlive the outage that
            // produced it, and a bundled-checklist record is already on disk
            // with the stamp and rarity detail this cache cannot represent.
            if resolution.isPersistable,
               case let .pokemon(pokemonCard, setCode) = card,
               let diskKey = Self.persistentKey(for: identifier) {
                let officialCount: Int?
                switch identifier {
                case let .pokemon(_, _, printedTotal, _): officialCount = printedTotal
                case let .pokemonHistorical(evidence): officialCount = evidence.number.denominator
                case .pokemonPromo, .magic: officialCount = nil
                }
                // The cache actor updates its entry and enqueues the file write,
                // but does not wait for the filesystem operation itself. Awaiting
                // this short actor hop ensures a cold catalog instance can see
                // the queued write without putting atomic file I/O on this path.
                await resolvedDiskCache.store(
                    card: pokemonCard,
                    setCode: setCode,
                    key: diskKey,
                    officialCount: officialCount
                )
            }
        }
        // Only successes are remembered. A failed lookup leaves no trace, so the
        // next attempt is a real attempt rather than a replayed failure.
        inFlight[identifier] = nil
        return result.map(\.card)
    }
}

/// The catalog reads TCGdex through this rather than concretely, so a test can
/// count how many requests one scanned card actually costs.
protocol PokemonHistoricalCatalogSource: Sendable {
    func historicalSetDirectory() async throws -> [CatalogSetReference]
    func historicalSet(id: String) async throws -> TCGdexSetCatalog
    func historicalCard(id: String) async throws -> TCGdexCard
}

extension TCGdexService: PokemonHistoricalCatalogSource {
    func historicalSetDirectory() async throws -> [CatalogSetReference] {
        try await fetchSetDirectory()
    }

    func historicalSet(id: String) async throws -> TCGdexSetCatalog {
        try await fetchSet(id: id)
    }

    func historicalCard(id: String) async throws -> TCGdexCard {
        try await fetchCard(id: id)
    }
}

/// Network/cache substrate for historical Pokémon identity. The matching policy
/// remains the pure `PokemonHistoricalIdentityResolver`, so a catalog refresh
/// cannot turn a collision into a first-candidate selection.
actor PokemonHistoricalCatalog {
    private let service: any PokemonHistoricalCatalogSource
    private var directoryTask: Task<[CatalogSetReference], Error>?
    private var setTasks: [String: Task<TCGdexSetCatalog, Error>] = [:]
    /// Resolved cards, keyed by provider id.
    ///
    /// Title OCR is not stable frame to frame — that is deliberate, and is why
    /// the evidence keeps every observation — so one physical card produces a
    /// different `ScanIdentifier` on almost every frame and the scanner's
    /// identifier-keyed coalescing cannot collapse them. The *network* work does
    /// not vary that way: it is a function of the printed number and, once
    /// resolved, of the provider id. Keying the memo on those makes re-reading a
    /// card free regardless of how many times Vision reads it.
    private var cardTasks: [String: Task<TCGdexCard, Error>] = [:]

    /// A failed memo is cleared so the next attempt can retry — but not at once.
    /// Clearing with no cooldown turns one stalled request into one request per
    /// frame, which is how a single timeout becomes a connection pool full of
    /// doomed tasks instead of staying a single timeout.
    private static let failureCooldown: TimeInterval = 3
    private var directoryFailure: (at: Date, error: any Error)?
    private var setFailures: [String: (at: Date, error: any Error)] = [:]
    private var cardFailures: [String: (at: Date, error: any Error)] = [:]

    init(service: any PokemonHistoricalCatalogSource = TCGdexService()) {
        self.service = service
    }

    /// Rethrows the recorded failure while it is still cooling down.
    private func cooldownError(
        _ failure: (at: Date, error: any Error)?,
        now: Date = .now
    ) -> (any Error)? {
        guard let failure,
              now.timeIntervalSince(failure.at) < Self.failureCooldown else { return nil }
        return failure.error
    }

    func card(for evidence: PokemonHistoricalScanEvidence) async throws -> IdentifiedCard {
        let setIDs = try await candidateSetIDs(for: evidence)
        guard !setIDs.isEmpty else { throw PokemonHistoricalCatalogError.unsupported }

        let catalogs = try await withThrowingTaskGroup(of: TCGdexSetCatalog.self) { group in
            for setID in setIDs {
                group.addTask { try await self.catalog(for: setID) }
            }
            var values: [TCGdexSetCatalog] = []
            for try await catalog in group { values.append(catalog) }
            return values
        }

        let validatedCatalogs: [TCGdexSetCatalog]
        switch evidence.number.scheme {
        case .officialSet:
            validatedCatalogs = catalogs.filter {
                $0.cardCount?.official == evidence.number.denominator
            }
        case .subset:
            validatedCatalogs = catalogs
        }
        let identities = PokemonHistoricalIdentityResolver.identities(in: validatedCatalogs)
        let identity: PokemonCatalogCardIdentity
        switch PokemonHistoricalIdentityResolver.resolve(
            evidence,
            candidateSetIDs: setIDs,
            in: identities
        ) {
        case let .unique(match):
            identity = match
        case let .ambiguous(matches):
            throw PokemonHistoricalCatalogError.ambiguous(matches)
        case .unsupported:
            throw PokemonHistoricalCatalogError.unsupported
        }

        return try await card(for: identity, matching: evidence)
    }

    func card(
        for identity: PokemonCatalogCardIdentity,
        matching evidence: PokemonHistoricalScanEvidence
    ) async throws -> IdentifiedCard {
        let eligibleSets = Set(try await candidateSetIDs(for: evidence))
        guard eligibleSets.contains(identity.setID.lowercased()),
              PokemonHistoricalIdentityResolver.canonicalLocalID(identity.localID)
                == PokemonHistoricalIdentityResolver.canonicalLocalID(evidence.number.localID),
              evidence.titleCandidates.contains(
                CatalogIdentityNormalization.canonicalText(identity.name)
              ) else {
            throw TCGdexError.identityMismatch
        }
        let card = try await fetchCard(providerID: identity.providerID)
        guard card.id == identity.providerID,
              card.set.id.caseInsensitiveCompare(identity.setID) == .orderedSame,
              PokemonHistoricalIdentityResolver.canonicalLocalID(card.localId)
                == PokemonHistoricalIdentityResolver.canonicalLocalID(identity.localID),
              CatalogIdentityNormalization.canonicalText(card.name)
                == CatalogIdentityNormalization.canonicalText(identity.name) else {
            throw TCGdexError.identityMismatch
        }
        return .pokemon(card, setCode: card.set.id.uppercased())
    }

    private func candidateSetIDs(
        for evidence: PokemonHistoricalScanEvidence
    ) async throws -> [String] {
        let directory: [CatalogSetReference]
        switch evidence.number.scheme {
        case .officialSet:
            directory = try await setDirectory()
        case .subset:
            // Subset denominators do not correspond to the containing set's
            // official count, so the explicit scheme map is authoritative.
            directory = []
        }
        return PokemonHistoricalIdentityResolver.candidateSetIDs(
            for: evidence,
            in: directory
        )
    }

    private func setDirectory() async throws -> [CatalogSetReference] {
        if let directoryTask { return try await directoryTask.value }
        if let cooling = cooldownError(directoryFailure) { throw cooling }

        let service = service
        let task = Task { try await service.historicalSetDirectory() }
        directoryTask = task
        do {
            let directory = try await task.value
            directoryFailure = nil
            return directory
        } catch {
            directoryTask = nil
            directoryFailure = (at: .now, error: error)
            throw error
        }
    }

    private func catalog(for setID: String) async throws -> TCGdexSetCatalog {
        let key = setID.lowercased()
        if let task = setTasks[key] { return try await task.value }
        if let cooling = cooldownError(setFailures[key]) { throw cooling }

        let service = service
        let task = Task { try await service.historicalSet(id: setID) }
        setTasks[key] = task
        do {
            let catalog = try await task.value
            setFailures[key] = nil
            return catalog
        } catch {
            setTasks[key] = nil
            setFailures[key] = (at: .now, error: error)
            throw error
        }
    }

    /// One request per provider id, however many frames asked for it.
    private func fetchCard(providerID: String) async throws -> TCGdexCard {
        if let task = cardTasks[providerID] { return try await task.value }
        if let cooling = cooldownError(cardFailures[providerID]) { throw cooling }

        let service = service
        let task = Task { try await service.historicalCard(id: providerID) }
        cardTasks[providerID] = task
        do {
            let card = try await task.value
            cardFailures[providerID] = nil
            return card
        } catch {
            cardTasks[providerID] = nil
            cardFailures[providerID] = (at: .now, error: error)
            throw error
        }
    }
}

/// A dictionary that forgets its least recently used entry once it is full.
///
/// The scan session cache is keyed by `ScanIdentifier`, which is the correct key
/// — two cards that happen to share a printed number must never share an entry.
/// But a historical identifier carries every title observation, and title OCR is
/// deliberately unstable frame to frame, so one physical card mints a new key on
/// almost every frame. Unbounded, the cache would grow with OCR noise instead of
/// with the number of cards actually scanned. Capping it costs at most a repeat
/// lookup, and repeats are now served from the catalog's own request memos.
struct BoundedCache<Key: Hashable, Value> {
    private let capacity: Int
    private var storage: [Key: Value] = [:]
    /// Least recently used first.
    private var usage: [Key] = []

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    var count: Int { storage.count }

    subscript(key: Key) -> Value? {
        mutating get {
            guard let value = storage[key] else { return nil }
            touch(key)
            return value
        }
        set {
            guard let newValue else {
                storage[key] = nil
                usage.removeAll { $0 == key }
                return
            }
            storage[key] = newValue
            touch(key)
            while storage.count > capacity, let oldest = usage.first {
                usage.removeFirst()
                storage[oldest] = nil
            }
        }
    }

    private mutating func touch(_ key: Key) {
        usage.removeAll { $0 == key }
        usage.append(key)
    }
}
