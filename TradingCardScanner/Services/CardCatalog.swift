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
        summary: CatalogCardSummary,
        setName: String,
        providerSetID: String,
        officialCount: Int
    ) -> TCGdexCard {
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
            id: summary.providerID,
            localId: summary.collectorNumber,
            name: summary.name,
            image: imageBaseURL(for: summary.imageURL),
            rarity: nil,
            set: brief,
            variants: nil,
            pricing: nil,
            variantsDetailed: nil
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
            guard let summary = matches.sorted(by: { $0.id < $1.id }).first else { continue }

            // A downloaded checklist can be from an incompatible provider
            // release. If it knows the official denominator, require the same
            // printed denominator before using it for scan identity.
            if let expectedOfficialCount,
               let localCount = entry.set.cardCount,
               localCount != expectedOfficialCount {
                continue
            }

            return makeCard(
                summary: summary,
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
            candidateSetIDs = Set(
                snapshot.manifest.entries.compactMap { entry in
                    entry.set.cardCount == evidence.number.denominator
                        ? entry.providerID.lowercased()
                        : nil
                }
            )
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
                summary: value.summary,
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
    private var snapshot: PokemonChecklistSnapshot?
    private var didLoad = false

    init(store: PokemonChecklistStore = PokemonChecklistStore()) {
        self.store = store
    }

    func card(
        providerSetID: String,
        localID: String,
        expectedOfficialCount: Int?
    ) async -> TCGdexCard? {
        await loadIfNeeded()
        guard let snapshot else { return nil }
        return PokemonOfflineCardFactory.card(
            in: snapshot,
            providerSetID: providerSetID,
            localID: localID,
            expectedOfficialCount: expectedOfficialCount
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

    func historicalCard(for evidence: PokemonHistoricalScanEvidence) async -> IdentifiedCard? {
        await loadIfNeeded()
        guard let snapshot else { return nil }
        return PokemonOfflineCardFactory.historicalCard(in: snapshot, evidence: evidence)
    }

    private func loadIfNeeded() async {
        guard !didLoad else { return }
        snapshot = await store.mergedSnapshot()
        didLoad = true
    }
}

/// Prevents every scan frame from opening another doomed TCGdex connection
/// while the provider is timing out. A success closes the circuit immediately;
/// only provider failures open it.
actor TCGdexCircuitBreaker {
    private let cooldown: TimeInterval
    private var unavailableUntil: Date?

    init(cooldown: TimeInterval = 30) {
        self.cooldown = max(cooldown, 0)
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
    }

    func recordFailure(now: Date = .now) {
        unavailableUntil = now.addingTimeInterval(cooldown)
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
    private let tcgdex = TCGdexService()
    private let pokemonAPI = PokemonTCGAPIService()
    private let pokemonOffline = PokemonOfflineCatalog()
    private let tcgdexCircuit = TCGdexCircuitBreaker()
    private let scryfall = ScryfallService()
    private let historicalPokemon = PokemonHistoricalCatalog()

    /// Bounded: see `BoundedCache`. Large enough that re-scanning a stack never
    /// evicts anything the user is actually working through, small enough that
    /// unstable OCR cannot grow it without limit.
    private var resolved = BoundedCache<ScanIdentifier, IdentifiedCard>(capacity: 256)
    private var inFlight: [ScanIdentifier: Task<IdentifiedCard, Error>] = [:]
    private var enrichmentStarted: Set<ScanIdentifier> = []

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
        // Complete on the catalog actor before returning to the scanner. This
        // is the original, proven prefetch-to-confirmation handoff: success is
        // cached and the in-flight slot is cleared as one actor transaction.
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

    private func start(_ identifier: ScanIdentifier) -> Task<IdentifiedCard, Error> {
        let tcgdex = tcgdex
        let pokemonAPI = pokemonAPI
        let pokemonOffline = pokemonOffline
        let tcgdexCircuit = tcgdexCircuit
        let scryfall = scryfall
        let historicalPokemon = historicalPokemon
        let task = Task<IdentifiedCard, Error> {
            switch identifier {
            case let .pokemon(setCode, cardNumber, printedTotal, setDefinition):
                if let card = await pokemonOffline.card(
                    providerSetID: setDefinition.tcgdexSetID,
                    localID: cardNumber,
                    expectedOfficialCount: printedTotal
                ) {
                    return .pokemon(card, setCode: setCode)
                }

                let card = try await Self.fetchPokemonCard(
                    tcgdex: tcgdex,
                    pokemonAPI: pokemonAPI,
                    circuit: tcgdexCircuit,
                    setID: setDefinition.tcgdexSetID,
                    localID: cardNumber,
                    expectedOfficialCount: printedTotal
                )
                return .pokemon(card, setCode: setCode)

            case let .pokemonPromo(prefix, localID, setDefinition):
                if let card = await pokemonOffline.card(
                    providerSetID: setDefinition.tcgdexSetID,
                    localID: localID,
                    expectedOfficialCount: nil
                ) {
                    return .pokemon(card, setCode: prefix)
                }

                let card = try await Self.fetchPokemonCard(
                    tcgdex: tcgdex,
                    pokemonAPI: pokemonAPI,
                    circuit: tcgdexCircuit,
                    setID: setDefinition.tcgdexSetID,
                    localID: localID,
                    expectedOfficialCount: nil
                )
                return .pokemon(card, setCode: prefix)

            case let .pokemonHistorical(evidence):
                if let card = await pokemonOffline.historicalCard(for: evidence) {
                    return card
                }
                return try await historicalPokemon.card(for: evidence)

            case let .magic(setCode, collectorNumber, language, contentKind):
                guard contentKind != .regular else {
                    // Unchanged fast path. An ordinary footer resolves exactly
                    // as it always has.
                    return .magic(
                        try await scryfall.fetchCard(
                            setCode: setCode,
                            collectorNumber: collectorNumber,
                            language: language
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
                return .magic(card)
            }
        }
        inFlight[identifier] = task
        return task
    }

    private static func fetchPokemonCard(
        tcgdex: TCGdexService,
        pokemonAPI: PokemonTCGAPIService,
        circuit: TCGdexCircuitBreaker,
        setID: String,
        localID: String,
        expectedOfficialCount: Int?
    ) async throws -> TCGdexCard {
        var lastError: Error = TCGdexError.badResponse

        if await circuit.permitsRequest() {
            do {
                let card = try await tcgdex.fetchCard(
                    setID: setID,
                    localID: localID,
                    timeout: 2.5
                )
                guard card.set.id.caseInsensitiveCompare(setID) == .orderedSame,
                      expectedOfficialCount == nil
                        || card.set.cardCount.official == expectedOfficialCount,
                      PokemonHistoricalIdentityResolver.canonicalLocalID(card.localId)
                        == PokemonHistoricalIdentityResolver.canonicalLocalID(localID) else {
                    await circuit.recordSuccess()
                    throw TCGdexError.identityMismatch
                }
                await circuit.recordSuccess()
                return card
            } catch let error as TCGdexError {
                switch error {
                case .cardNotFound, .identityMismatch:
                    // A definitive provider answer must not be replaced by a
                    // looser secondary search.
                    await circuit.recordSuccess()
                    throw error
                default:
                    await circuit.recordFailure()
                    lastError = error
                }
            } catch {
                await circuit.recordFailure()
                lastError = error
            }
        }

        // TCGdex is optional for scanner completion. The secondary provider is
        // queried by exact provider set id and local number, then validated again
        // before its identity-only card enters the session cache.
        do {
            guard let alternate = try await pokemonAPI.fetchCard(
                setID: setID,
                cardNumber: localID,
                timeout: 3
            ),
            alternate.set.id?.caseInsensitiveCompare(setID) == .orderedSame,
            expectedOfficialCount == nil
                || alternate.set.printedTotal == nil
                || alternate.set.printedTotal == expectedOfficialCount,
            PokemonHistoricalIdentityResolver.canonicalLocalID(alternate.number)
                == PokemonHistoricalIdentityResolver.canonicalLocalID(localID) else {
                throw lastError
            }

            let officialCount = expectedOfficialCount
                ?? alternate.set.printedTotal
                ?? 0
            let set = TCGdexSetBrief(
                id: setID,
                name: alternate.set.name,
                cardCount: TCGdexCardCount(
                    total: max(officialCount, 0),
                    official: max(officialCount, 0)
                )
            )
            return TCGdexCard(
                id: "\(setID)-\(alternate.number)",
                localId: alternate.number,
                name: alternate.name,
                image: alternate.images.large.absoluteString,
                rarity: nil,
                set: set,
                variants: nil,
                pricing: nil,
                variantsDetailed: nil
            )
        } catch {
            throw lastError
        }
    }

    private func complete(
        _ identifier: ScanIdentifier,
        task: Task<IdentifiedCard, Error>
    ) async -> Result<IdentifiedCard, Error> {
        let result = await task.result
        if case let .success(card) = result {
            resolved[identifier] = card
            if await isOfflinePokemon(identifier), enrichmentStarted.insert(identifier).inserted {
                Task { [weak self] in
                    await self?.enrich(identifier)
                }
            }
        }
        // Only successes are remembered. A failed lookup leaves no trace, so the
        // next attempt is a real attempt rather than a replayed failure.
        inFlight[identifier] = nil
        return result
    }

    private func isOfflinePokemon(_ identifier: ScanIdentifier) async -> Bool {
        switch identifier {
        case let .pokemon(_, cardNumber, printedTotal, setDefinition):
            return await pokemonOffline.contains(
                providerSetID: setDefinition.tcgdexSetID,
                localID: cardNumber,
                expectedOfficialCount: printedTotal
            )
        case let .pokemonPromo(_, localID, setDefinition):
            return await pokemonOffline.contains(
                providerSetID: setDefinition.tcgdexSetID,
                localID: localID,
                expectedOfficialCount: nil
            )
        case .pokemonHistorical, .magic:
            return false
        }
    }

    private func enrich(_ identifier: ScanIdentifier) async {
        defer { enrichmentStarted.remove(identifier) }
        do {
            switch identifier {
            case let .pokemon(setCode, cardNumber, printedTotal, setDefinition):
                let card = try await Self.fetchPokemonCard(
                    tcgdex: tcgdex,
                    pokemonAPI: pokemonAPI,
                    circuit: tcgdexCircuit,
                    setID: setDefinition.tcgdexSetID,
                    localID: cardNumber,
                    expectedOfficialCount: printedTotal
                )
                resolved[identifier] = .pokemon(card, setCode: setCode)
            case let .pokemonPromo(prefix, localID, setDefinition):
                let card = try await Self.fetchPokemonCard(
                    tcgdex: tcgdex,
                    pokemonAPI: pokemonAPI,
                    circuit: tcgdexCircuit,
                    setID: setDefinition.tcgdexSetID,
                    localID: localID,
                    expectedOfficialCount: nil
                )
                resolved[identifier] = .pokemon(card, setCode: prefix)
            case .pokemonHistorical, .magic:
                break
            }
        } catch {
            // Offline identity is already usable. Enrichment is best effort and
            // must never turn a provider outage into a failed scan.
        }
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
