import Foundation

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
    /// A request keeps its identity so an evicted task that finishes later
    /// cannot clear a newer request for the same provider key.
    private struct TaskMemo<Value> {
        let id = UUID()
        let task: Task<Value, Error>
    }

    private let service: any PokemonHistoricalCatalogSource
    private var directoryTask: Task<[CatalogSetReference], Error>?
    /// Whole-set responses are comparatively large, so keep a modest recent
    /// window. The capacity is injectable only so eviction remains testable.
    private var setTasks: BoundedCache<String, TaskMemo<TCGdexSetCatalog>>
    /// Resolved cards, keyed by provider id.
    ///
    /// Title OCR is not stable frame to frame — that is deliberate, and is why
    /// the evidence keeps every observation — so one physical card produces a
    /// different `ScanIdentifier` on almost every frame and the scanner's
    /// identifier-keyed coalescing cannot collapse them. The *network* work does
    /// not vary that way: it is a function of the printed number and, once
    /// resolved, of the provider id. Keying the memo on those makes re-reading a
    /// card free regardless of how many times Vision reads it.
    /// Individual card responses are smaller and are commonly revisited by
    /// OCR retries, so retain a larger recent window than set catalogs.
    private var cardTasks: BoundedCache<String, TaskMemo<TCGdexCard>>

    /// A failed memo is cleared so the next attempt can retry — but not at once.
    /// Clearing with no cooldown turns one stalled request into one request per
    /// frame, which is how a single timeout becomes a connection pool full of
    /// doomed tasks instead of staying a single timeout.
    private static let failureCooldown: TimeInterval = 3
    private var directoryFailure: (at: Date, error: any Error)?
    private var setFailures: BoundedCache<String, (at: Date, error: any Error)>
    private var cardFailures: BoundedCache<String, (at: Date, error: any Error)>
    private var registry = PokemonCatalogRegistry.bundledSeed

    init(
        service: any PokemonHistoricalCatalogSource = TCGdexService(),
        setTaskCapacity: Int = 64,
        cardTaskCapacity: Int = 256,
        registry: PokemonCatalogRegistry = .bundledSeed
    ) {
        self.service = service
        self.setTasks = BoundedCache(capacity: setTaskCapacity)
        self.cardTasks = BoundedCache(capacity: cardTaskCapacity)
        self.setFailures = BoundedCache(capacity: setTaskCapacity)
        self.cardFailures = BoundedCache(capacity: cardTaskCapacity)
        self.registry = registry
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

    func updateRegistry(_ registry: PokemonCatalogRegistry) {
        self.registry = registry
    }

    func card(for evidence: PokemonHistoricalScanEvidence) async throws -> IdentifiedCard {
        let registry = self.registry
        return try await card(for: evidence, registry: registry)
    }

    func card(
        for evidence: PokemonHistoricalScanEvidence,
        registry: PokemonCatalogRegistry
    ) async throws -> IdentifiedCard {
        let liveSetIDs = try await liveCandidateSetIDs(for: evidence, registry: registry)
        let membershipSetIDs = PokemonHistoricalIdentityResolver.membershipSetIDs(
            for: evidence,
            in: registry
        )
        let setIDs = Array(Set(liveSetIDs + membershipSetIDs)).sorted()
        guard !setIDs.isEmpty else { throw PokemonHistoricalCatalogError.unsupported }

        let catalogs = try await withThrowingTaskGroup(of: TCGdexSetCatalog.self) { group in
            for setID in liveSetIDs {
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
            + PokemonHistoricalIdentityResolver.membershipIdentities(
                for: evidence,
                in: registry
            )
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

        return try await card(for: identity, matching: evidence, registry: registry)
    }

    func card(
        for identity: PokemonCatalogCardIdentity,
        matching evidence: PokemonHistoricalScanEvidence,
        registry: PokemonCatalogRegistry? = nil
    ) async throws -> IdentifiedCard {
        let registrySnapshot = registry ?? self.registry
        let eligibleSets = Set(
            try await candidateSetIDs(for: evidence, registry: registrySnapshot)
        )
        guard eligibleSets.contains(identity.setID.lowercased()),
              PokemonHistoricalIdentityResolver.canonicalLocalID(identity.localID)
                == PokemonHistoricalIdentityResolver.canonicalLocalID(evidence.number.localID),
              PokemonNameMatcher.agrees(
                cardName: identity.name,
                readings: evidence.titleCandidates
              ) else {
            throw TCGdexError.identityMismatch
        }
        let card = try await fetchCard(providerID: identity.providerID)
        let isMembership = PokemonHistoricalIdentityResolver.isMembershipIdentity(
            identity,
            for: evidence.number,
            in: registrySnapshot
        )
        guard card.id.caseInsensitiveCompare(identity.providerID) == .orderedSame,
              card.set.id.caseInsensitiveCompare(identity.setID) == .orderedSame,
              CatalogIdentityNormalization.canonicalText(card.name)
                == CatalogIdentityNormalization.canonicalText(identity.name) else {
            throw TCGdexError.identityMismatch
        }
        if !isMembership {
            guard card.set.id.caseInsensitiveCompare(identity.setID) == .orderedSame,
                  PokemonHistoricalIdentityResolver.canonicalLocalID(card.localId)
                    == PokemonHistoricalIdentityResolver.canonicalLocalID(identity.localID) else {
                throw TCGdexError.identityMismatch
            }
            return .pokemon(card, setCode: card.set.id.uppercased())
        }

        let printedCount = evidence.number.denominator
        let materializedSet = TCGdexSetBrief(
            id: card.set.id,
            name: identity.setName,
            cardCount: TCGdexCardCount(total: printedCount, official: printedCount)
        )
        let materializedCard = TCGdexCard(
            id: card.id,
            localId: identity.localID,
            name: card.name,
            image: card.image,
            rarity: card.rarity,
            set: materializedSet,
            variants: card.variants,
            pricing: card.pricing,
            variantsDetailed: card.variantsDetailed
        )
        return .pokemon(
            materializedCard,
            setCode: registrySnapshot.printedCode(forProviderSetID: card.set.id)
                ?? card.set.id.uppercased()
        )
    }

    private func candidateSetIDs(
        for evidence: PokemonHistoricalScanEvidence,
        registry: PokemonCatalogRegistry
    ) async throws -> [String] {
        let live = try await liveCandidateSetIDs(for: evidence, registry: registry)
        let membership = PokemonHistoricalIdentityResolver.membershipSetIDs(
            for: evidence,
            in: registry
        )
        return Array(Set(live + membership)).sorted()
    }

    private func liveCandidateSetIDs(
        for evidence: PokemonHistoricalScanEvidence,
        registry: PokemonCatalogRegistry
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
        ).filter { !registry.isScanDisabled(forProviderSetID: $0) }
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
        if let memo = setTasks[key] { return try await memo.task.value }
        if let cooling = cooldownError(setFailures[key]) { throw cooling }

        let service = service
        let memo = TaskMemo(task: Task { try await service.historicalSet(id: setID) })
        setTasks[key] = memo
        do {
            let catalog = try await memo.task.value
            if setTasks[key]?.id == memo.id {
                setFailures[key] = nil
            }
            return catalog
        } catch {
            if setTasks[key]?.id == memo.id {
                setTasks[key] = nil
                setFailures[key] = (at: .now, error: error)
            }
            throw error
        }
    }

    /// One request per provider id, however many frames asked for it.
    private func fetchCard(providerID: String) async throws -> TCGdexCard {
        if let memo = cardTasks[providerID] { return try await memo.task.value }
        if let cooling = cooldownError(cardFailures[providerID]) { throw cooling }

        let service = service
        let memo = TaskMemo(task: Task { try await service.historicalCard(id: providerID) })
        cardTasks[providerID] = memo
        do {
            let card = try await memo.task.value
            if cardTasks[providerID]?.id == memo.id {
                cardFailures[providerID] = nil
            }
            return card
        } catch {
            if cardTasks[providerID]?.id == memo.id {
                cardTasks[providerID] = nil
                cardFailures[providerID] = (at: .now, error: error)
            }
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
