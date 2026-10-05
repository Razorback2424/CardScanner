import Foundation

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
        officialCount: Int,
        localID: String? = nil
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
            localId: localID ?? summaries[0].collectorNumber,
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

    static func card(
        in snapshot: PokemonChecklistSnapshot,
        candidate: PokemonCatalogCardIdentity,
        number: PokemonPrintedNumberEvidence,
        registry: PokemonCatalogRegistry
    ) -> IdentifiedCard? {
        let isMembership = PokemonHistoricalIdentityResolver.isMembershipIdentity(
            candidate,
            for: number,
            in: registry
        )
        let candidateSets = candidateSetIDs(
            in: snapshot.manifest.entries,
            number: number,
            registry: registry
        )
        let providerSetID = candidate.setID.lowercased()
        guard candidateSets.contains(providerSetID) || isMembership,
              let entry = snapshot.manifest.entries.first(where: {
                  $0.providerID.caseInsensitiveCompare(candidate.setID) == .orderedSame
              }),
              let cards = snapshot.checklists[entry.set.id] else { return nil }

        let localID = PokemonHistoricalIdentityResolver.canonicalLocalID(candidate.localID)
        let summaries = cards.filter {
            $0.game == .pokemon
                && $0.providerID.caseInsensitiveCompare(candidate.providerID) == .orderedSame
                && $0.setID.providerID.caseInsensitiveCompare(candidate.setID) == .orderedSame
                && (isMembership || (
                    PokemonHistoricalIdentityResolver.canonicalLocalID($0.collectorNumber) == localID
                        && localID == PokemonHistoricalIdentityResolver.canonicalLocalID(number.localID)
                ))
                && CatalogIdentityNormalization.canonicalText($0.name)
                    == CatalogIdentityNormalization.canonicalText(candidate.name)
        }.sorted { left, right in
            let leftVariant = left.masterSetVariant?.id ?? ""
            let rightVariant = right.masterSetVariant?.id ?? ""
            return (leftVariant, left.id) < (rightVariant, right.id)
        }
        guard let primary = summaries.first else { return nil }
        let card = makeCard(
            summaries: summaries,
            setName: entry.set.name,
            providerSetID: entry.providerID,
            officialCount: number.denominator,
            localID: candidate.localID
        )
        return .pokemon(
            card,
            setCode: isMembership
                ? registry.printedCode(forProviderSetID: entry.providerID) ?? primary.setCode
                : primary.setCode
        )
    }

    static func candidates(
        in snapshot: PokemonChecklistSnapshot,
        number: PokemonPrintedNumberEvidence,
        registry: PokemonCatalogRegistry = .bundledSeed
    ) -> [PokemonCatalogCardIdentity] {
        let membershipSetIDs = membershipSetIDs(for: number, registry: registry)
        let candidateSetIDs = candidateSetIDs(
            in: snapshot.manifest.entries,
            number: number,
            registry: registry
        ).union(membershipSetIDs)
        let localID = PokemonHistoricalIdentityResolver.canonicalLocalID(number.localID)
        var identitiesByProviderID: [String: PokemonCatalogCardIdentity] = [:]
        for entry in snapshot.manifest.entries where candidateSetIDs.contains(entry.providerID.lowercased())
            && (!registry.isScanDisabled(forProviderSetID: entry.providerID)
                || membershipSetIDs.contains(entry.providerID.lowercased())) {
            guard let cards = snapshot.checklists[entry.set.id] else { continue }
            for summary in cards where summary.game == .pokemon
                && PokemonHistoricalIdentityResolver.canonicalLocalID(summary.collectorNumber) == localID {
                let identity = PokemonCatalogCardIdentity(
                    providerID: summary.providerID,
                    setID: entry.providerID,
                    setName: entry.set.name,
                    localID: summary.collectorNumber,
                    name: summary.name,
                    releaseYear: entry.set.releaseDate.map {
                        Calendar(identifier: .gregorian).component(.year, from: $0)
                    },
                    thumbnailURL: summary.thumbnailURL
                )
                identitiesByProviderID[identity.providerID.lowercased()] = identity
            }
        }
        for identity in PokemonHistoricalIdentityResolver.membershipIdentities(
            for: number,
            in: registry
        ) {
            identitiesByProviderID[identity.providerID.lowercased()] = identity
        }
        return Array(identitiesByProviderID.values).sorted { left, right in
            if left.setID != right.setID { return left.setID < right.setID }
            return left.providerID < right.providerID
        }
    }

    /// The registry is part of the historical lookup contract. Explicitly
    /// withdrawn sets are excluded here as well as by the actor caller, so a
    /// future caller cannot accidentally re-open the disabled path.
    static func historicalCard(
        in snapshot: PokemonChecklistSnapshot,
        evidence: PokemonHistoricalScanEvidence,
        registry: PokemonCatalogRegistry = .bundledSeed
    ) -> IdentifiedCard? {
        let candidateSetIDs = candidateSetIDs(
            in: snapshot.manifest.entries,
            number: evidence.number,
            registry: registry
        ).union(
            PokemonHistoricalIdentityResolver.membershipSetIDs(
                for: evidence,
                in: registry
            )
        )
        guard !candidateSetIDs.isEmpty else { return nil }

        var identitiesByProviderID: [String: PokemonCatalogCardIdentity] = [:]
        // One numbered card occupies one checklist row per physical slot, and
        // every one of those rows is variant evidence. Keyed by provider id
        // alone, a `normal` row and a `reverse` row of the same printing
        // overwrite each other and the surviving row becomes the card's only
        // published finish — which is the resolver being told a lie, not a
        // catalog that is silent. Keep the whole group.
        var summariesByProviderID: [String: (summaries: [CatalogCardSummary], set: CatalogSet)] = [:]
        for entry in snapshot.manifest.entries where candidateSetIDs.contains(entry.providerID.lowercased()) {
            guard let cards = snapshot.checklists[entry.set.id] else { continue }
            for summary in cards where summary.game == .pokemon {
                let providerID = summary.providerID.lowercased()
                identitiesByProviderID[providerID] = PokemonCatalogCardIdentity(
                    providerID: summary.providerID,
                    setID: entry.providerID,
                    setName: entry.set.name,
                    localID: summary.collectorNumber,
                    name: summary.name,
                    releaseYear: entry.set.releaseDate.map {
                        Calendar(identifier: .gregorian).component(.year, from: $0)
                    }
                )
                summariesByProviderID[providerID, default: (summaries: [], set: entry.set)]
                    .summaries
                    .append(summary)
            }
        }

        for identity in PokemonHistoricalIdentityResolver.membershipIdentities(
            for: evidence,
            in: registry
        ) {
            identitiesByProviderID[identity.providerID.lowercased()] = identity
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
            // Same ordering rule as the modern offline path, so the record's
            // name and image come from a stable row rather than from whichever
            // slot the checklist file happened to list last.
            let summaries = value.summaries.sorted { left, right in
                let leftVariant = left.masterSetVariant?.id ?? ""
                let rightVariant = right.masterSetVariant?.id ?? ""
                return (leftVariant, left.id) < (rightVariant, right.id)
            }
            guard let primary = summaries.first else { return nil }
            let officialCount = evidence.number.denominator
            let card = makeCard(
                summaries: summaries,
                setName: identity.setName,
                providerSetID: identity.setID,
                officialCount: officialCount,
                localID: identity.localID
            )
            return .pokemon(card, setCode: primary.setCode)
        case .ambiguous, .unsupported:
            // The offline snapshot must preserve the same conservative rule as
            // the live historical resolver. A missing or colliding title is not
            // permission to pick the first summary.
            return nil
        }
    }

    static func candidateSetIDs(
        in entries: [PokemonChecklistSnapshotEntry],
        number: PokemonPrintedNumberEvidence,
        registry: PokemonCatalogRegistry
    ) -> Set<String> {
        switch number.scheme {
        case .officialSet:
            return Set(entries.compactMap { entry in
                let officialCount = entry.officialCount
                    ?? registry.officialCount(forProviderSetID: entry.providerID)
                    ?? PokemonCatalogRegistry.bundledSeed.officialCount(forProviderSetID: entry.providerID)
                return officialCount == number.denominator
                    && !registry.isScanDisabled(forProviderSetID: entry.providerID)
                    ? entry.providerID.lowercased()
                    : nil
            })
        case .subset:
            return Set(
                PokemonHistoricalIdentityResolver.candidateSetIDs(for: number, in: [])
                    .filter { !registry.isScanDisabled(forProviderSetID: $0) }
            )
        }
    }

    static func membershipSetIDs(
        for number: PokemonPrintedNumberEvidence,
        registry: PokemonCatalogRegistry
    ) -> Set<String> {
        let localID = PokemonHistoricalIdentityResolver.canonicalLocalID(number.localID)
        return Set(registry.descriptors.compactMap { descriptor in
            guard let recognition = descriptor.membershipRecognition,
                  recognition.members.contains(where: {
                      $0.printedDenominator == number.denominator
                          && PokemonHistoricalIdentityResolver.canonicalLocalID($0.printedLocalID) == localID
                  }) else { return nil }
            return descriptor.providerSetID.lowercased()
        })
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
    private var registry: PokemonCatalogRegistry

    init(
        store: PokemonChecklistStore = .shared,
        registry: PokemonCatalogRegistry = .bundledSeed
    ) {
        self.store = store
        self.registry = registry
    }

    func updateRegistry(_ registry: PokemonCatalogRegistry) {
        self.registry = registry
    }

    nonisolated func sessionCopy(registry: PokemonCatalogRegistry) -> PokemonOfflineCatalog {
        PokemonOfflineCatalog(store: store, registry: registry)
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

    func card(
        for candidate: PokemonCatalogCardIdentity,
        number: PokemonPrintedNumberEvidence
    ) async -> IdentifiedCard? {
        await loadIfNeeded()
        let registry = self.registry
        guard let entry = entries.first(where: {
            $0.providerID.caseInsensitiveCompare(candidate.setID) == .orderedSame
        }),
              let cards = await store.mergedChecklist(for: entry.set.catalogID) else { return nil }
        let manifest = PokemonChecklistSnapshotManifest(
            schemaVersion: PokemonChecklistSnapshotVersion.schema,
            rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
            generatedAt: .now,
            directoryFingerprint: "candidate",
            entries: [entry]
        )
        return PokemonOfflineCardFactory.card(
            in: PokemonChecklistSnapshot(manifest: manifest, checklists: [entry.set.id: cards]),
            candidate: candidate,
            number: number,
            registry: registry
        )
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

    func candidates(
        for number: PokemonPrintedNumberEvidence
    ) async -> [PokemonCatalogCardIdentity] {
        await loadIfNeeded()
        let registry = self.registry
        let membershipSetIDs = PokemonOfflineCardFactory.membershipSetIDs(
            for: number,
            registry: registry
        )
        let candidateSetIDs = PokemonOfflineCardFactory.candidateSetIDs(
            in: entries,
            number: number,
            registry: registry
        ).union(membershipSetIDs)
        guard !candidateSetIDs.isEmpty else { return [] }

        var matchingEntries: [PokemonChecklistSnapshotEntry] = []
        var checklists: [String: [CatalogCardSummary]] = [:]
        for entry in entries where candidateSetIDs.contains(entry.providerID.lowercased())
            && (!registry.isScanDisabled(forProviderSetID: entry.providerID)
                || membershipSetIDs.contains(entry.providerID.lowercased())) {
            guard let cards = await store.mergedChecklist(for: entry.set.catalogID) else { continue }
            matchingEntries.append(entry)
            checklists[entry.set.id] = cards
        }
        let membershipIdentities = PokemonHistoricalIdentityResolver.membershipIdentities(
            for: number,
            in: registry
        )
        guard !matchingEntries.isEmpty else { return membershipIdentities }
        let manifest = PokemonChecklistSnapshotManifest(
            schemaVersion: PokemonChecklistSnapshotVersion.schema,
            rulesVersion: PokemonChecklistSnapshotVersion.masterSetRules,
            generatedAt: .now,
            directoryFingerprint: "lazy",
            entries: matchingEntries
        )
        return PokemonOfflineCardFactory.candidates(
            in: PokemonChecklistSnapshot(manifest: manifest, checklists: checklists),
            number: number,
            registry: registry
        )
    }

    func historicalCard(for evidence: PokemonHistoricalScanEvidence) async -> IdentifiedCard? {
        await loadIfNeeded()
        // Pin the immutable snapshot for this lookup. Activation can happen
        // while checklist files are being read, but one resolution must never
        // combine candidate filtering from two registry revisions.
        let registry = self.registry
        let membershipSetIDs = Set(
            PokemonHistoricalIdentityResolver.membershipSetIDs(
                for: evidence,
                in: registry
            )
        )
        let candidateSetIDs: Set<String>
        switch evidence.number.scheme {
        case .officialSet:
            let liveCandidateSetIDs = Set(entries.compactMap { entry in
                let officialCount = entry.officialCount
                    ?? registry.officialCount(forProviderSetID: entry.providerID)
                    ?? PokemonCatalogRegistry.bundledSeed.officialCount(forProviderSetID: entry.providerID)
                return officialCount == evidence.number.denominator
                    && !registry.isScanDisabled(forProviderSetID: entry.providerID)
                    ? entry.providerID.lowercased()
                    : nil
            })
            candidateSetIDs = liveCandidateSetIDs.union(membershipSetIDs)
        case .subset:
            candidateSetIDs = Set(
                PokemonHistoricalIdentityResolver.candidateSetIDs(
                    for: evidence.number,
                    in: []
                ).filter { !registry.isScanDisabled(forProviderSetID: $0) }
            )
        }
        guard !candidateSetIDs.isEmpty else { return nil }

        var matchingEntries: [PokemonChecklistSnapshotEntry] = []
        var checklists: [String: [CatalogCardSummary]] = [:]
        for entry in entries where candidateSetIDs.contains(entry.providerID.lowercased())
            && (!registry.isScanDisabled(forProviderSetID: entry.providerID)
                || membershipSetIDs.contains(entry.providerID.lowercased())) {
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
        return PokemonOfflineCardFactory.historicalCard(
            in: snapshot,
            evidence: evidence,
            registry: registry
        )
    }

    func prewarm() async {
        await loadIfNeeded()
    }

    func invalidate() {
        didLoad = false
        loadTask?.cancel()
        loadTask = nil
        entries = []
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
    private var isLoading = false
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []

    struct CachedCard: Sendable {
        let card: TCGdexCard
        let setCode: String
        let storedAt: Date
    }

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
        await loadIfNeeded()
    }

    func card(for key: String) async -> CachedCard? {
        await loadIfNeeded()
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
        return CachedCard(card: card, setCode: entry.setCode, storedAt: entry.storedAt)
    }

    func store(
        card: TCGdexCard,
        setCode: String,
        key: String,
        officialCount: Int? = nil
    ) async {
        await loadIfNeeded()
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

    func invalidateEntry(for key: String) async {
        await loadIfNeeded()
        guard entries.removeValue(forKey: key) != nil else { return }
        persist()
    }

    func invalidateEntries(forSetIDs setIDs: Set<String>) {
        guard !setIDs.isEmpty else { return }
        var changed = false
        for (key, entry) in entries {
            if setIDs.contains(entry.setID.lowercased()) {
                entries[key] = nil
                changed = true
            }
        }
        if changed { persist() }
    }

    private func loadIfNeeded() async {
        guard !didLoad else { return }
        if isLoading {
            await withCheckedContinuation { continuation in
                loadWaiters.append(continuation)
            }
            return
        }
        isLoading = true
        // A cold cache reader may be a new catalog instance racing the prior
        // instance's background write. Flush the shared utility queue before
        // reading, suspending this actor instead of blocking its executor
        // thread while the filesystem write drains.
        await withCheckedContinuation { continuation in
            Self.writeQueue.async {
                continuation.resume()
            }
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL),
           let file = try? decoder.decode(File.self, from: data),
           file.appVersion == appVersion,
           file.schemaGeneration == Self.schemaGeneration {
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

        didLoad = true
        isLoading = false
        let waiters = loadWaiters
        loadWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
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
