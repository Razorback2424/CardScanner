import Foundation

/// Why a lookup failed, in the only terms the scanner cares about.
enum CatalogFailure: Equatable {
    /// The lookup produced a deterministic catalog-side result rather than a
    /// transient outage. This may mean no record was found, the provider's
    /// identity disagreed, or the requested printing is unsupported.
    case notInCatalog
    /// Network or server trouble. Nothing was written and nothing is known to be
    /// wrong with the card, so the very next reading should be allowed through.
    case transient
    /// The provider is actively cooling down after a server/rate-limit outage.
    /// Keep the physical card latched so a held card cannot turn the outage into
    /// a request loop; a later presentation can try again after the circuit opens.
    case providerUnavailable
}

enum CatalogResolutionPath: String, Sendable {
    case cacheHit = "cache-hit"
    case network
    case historicalFallback = "historical-fallback"
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
        let path: CatalogResolutionPath
        /// The time the card payload was obtained. A session-cache hit keeps
        /// this original provider time instead of manufacturing a new price
        /// retrieval timestamp at the next scan.
        let retrievedAt: Date

        init(
            _ card: IdentifiedCard,
            isPersistable: Bool = false,
            retrievedAt: Date = .now,
            path: CatalogResolutionPath = .network
        ) {
            self.card = card
            self.isPersistable = isPersistable
            self.retrievedAt = retrievedAt
            self.path = path
        }
    }

    /// Bounded: see `BoundedCache`. Large enough that re-scanning a stack never
    /// evicts anything the user is actually working through, small enough that
    /// unstable OCR cannot grow it without limit.
    private var gameCatalogAdapters: GameCatalogAdapterRegistry
    private var adapterOutcomes = BoundedCache<ScanIdentifier, CatalogLookupOutcome>(capacity: 256)
    private struct AdapterLookup {
        let token: UUID
        let task: Task<CatalogLookupOutcome, Error>
    }
    private var adapterLookups: [ScanIdentifier: AdapterLookup] = [:]

    var registeredGameCatalogAdapters: GameCatalogAdapterRegistry { gameCatalogAdapters }

    func install(_ adapter: any GameCatalogAdapter) {
        gameCatalogAdapters = gameCatalogAdapters.replacing(adapter)
        adapterOutcomes.removeAll()
    }

    func identifierForRetry(_ identifier: ScanIdentifier) throws -> ScanIdentifier {
        guard let adapter = gameCatalogAdapters.adapter(for: identifier.game) else {
            throw CatalogLookupError.catalogIncomplete(nil)
        }
        return try adapter.identifierForRetry(identifier)
    }

    init(
        source: any PokemonCardSource = LivePokemonCardSource(),
        offline: PokemonOfflineCatalog? = nil,
        resolvedDiskCache: ResolvedPokemonCardCache = ResolvedPokemonCardCache(),
        tcgdexBreaker: TCGdexCircuitBreaker = .shared,
        registry: PokemonCatalogRegistry = .bundledSeed,
        magicCatalogCoordinator: MagicCatalogCoordinator? = nil,
        gameCatalogAdapters: GameCatalogAdapterRegistry = try! .init(adapters: [])
    ) {
        self.gameCatalogAdapters = gameCatalogAdapters.installingLegacyDefaults(
            pokemon: PokemonCatalogAdapter(source: source, offline: offline, resolvedDiskCache: resolvedDiskCache,
                tcgdexBreaker: tcgdexBreaker, registry: registry), magicCoordinator: magicCatalogCoordinator)
    }

    /// Compatibility facade for existing Pokémon scanner/print-run callers.
    /// Provider state and captured-definition policy live in the game module.
    func updateRegistry(_ registry: PokemonCatalogRegistry) async {
        guard let adapter = gameCatalogAdapters.pokemonCatalog else { return }
        guard adapter.registry.revision != registry.revision || adapter.registry.descriptors != registry.descriptors else { return }
        adapterOutcomes.removeAll()
        install(await adapter.updating(registry))
    }

    func candidates(for number: PokemonPrintedNumberEvidence) async -> [PokemonCatalogCardIdentity] {
        guard let adapter = gameCatalogAdapters.pokemonCatalog else { return [] }
        return await adapter.candidates(for: number)
    }

    func prewarm() async {
        for game in gameCatalogAdapters.games { await gameCatalogAdapters.adapter(for: game)?.prewarm() }
    }

    func prefetch(_ identifier: ScanIdentifier) {
        Task { _ = try? await self.lookupOutcome(for: identifier) }
    }

    func card(for identifier: ScanIdentifier) async throws -> IdentifiedCard {
        try await resolution(for: identifier).card
    }

    func resolution(for identifier: ScanIdentifier) async throws -> CatalogResolution {
        switch try await lookupOutcome(for: identifier) {
        case let .resolved(resolution): return resolution
        case let .needsPrintingChoice(canonical, candidates):
            throw CatalogLookupError.printingChoiceRequired(canonical, candidates)
        case let .catalogIncomplete(canonical): throw CatalogLookupError.catalogIncomplete(canonical)
        }
    }

    func lookupOutcome(for identifier: ScanIdentifier) async throws -> CatalogLookupOutcome {
        guard let adapter = gameCatalogAdapters.adapter(for: identifier.game) else {
            throw CardGameSupportError.unsupportedGame(identifier.game)
        }
        let prepared = try adapter.prepareLookupIdentifier(identifier)
        guard prepared.game == identifier.game, prepared.catalogGeneration == adapter.generation else {
            throw CatalogLookupError.invalidAdapterOutcome
        }
        if let cached = adapterOutcomes[prepared] { return cached }
        let lookup: AdapterLookup
        if let existing = adapterLookups[prepared] { lookup = existing }
        else {
            lookup = .init(token: UUID(), task: Task { try await adapter.lookup(prepared) })
            adapterLookups[prepared] = lookup
        }
        defer {
            if adapterLookups[prepared]?.token == lookup.token { adapterLookups[prepared] = nil }
        }
        let outcome = try await lookup.task.value
        guard gameCatalogAdapters.adapter(for: identifier.game)?.acceptsCompletion(for: prepared, fromGeneration: adapter.generation) == true else {
            throw CatalogLookupError.staleCatalog
        }
        switch outcome {
        case let .resolved(resolution):
            guard resolution.card.game == identifier.game else { throw CatalogLookupError.invalidAdapterOutcome }
        case let .needsPrintingChoice(canonical, candidates):
            guard canonical.game == identifier.game, !candidates.isEmpty,
                  Set(candidates.map(\.id)).count == candidates.count,
                  candidates.allSatisfy({
                      $0.game == identifier.game && $0.canonicalCardID == canonical.id
                          && $0.catalogGeneration == adapter.generation && !$0.id.isEmpty
                  }) else { throw CatalogLookupError.invalidAdapterOutcome }
        case let .catalogIncomplete(canonical):
            guard canonical == nil || canonical?.game == identifier.game else { throw CatalogLookupError.invalidAdapterOutcome }
        }
        // Candidate lookup is cached, never the user's physical-printing answer.
        // Missing/incomplete entries remain retryable within the same generation.
        if case .catalogIncomplete = outcome {} else { adapterOutcomes[prepared] = outcome }
        return outcome
    }

    func resolvePrintingChoice(_ candidate: PhysicalPrintingCandidate,
                               for identifier: ScanIdentifier) async throws -> CatalogResolution {
        guard let adapter = gameCatalogAdapters.adapter(for: identifier.game),
              candidate.game == identifier.game,
              candidate.catalogGeneration == adapter.generation,
              identifier.catalogGeneration == adapter.generation else { throw CatalogLookupError.staleCatalog }
        switch try await lookupOutcome(for: identifier) {
        case let .needsPrintingChoice(canonical, candidates):
            guard candidates.contains(where: { $0.matchesPersistedChoice(candidate) }),
                  canonical.id == candidate.canonicalCardID else {
                throw CatalogLookupError.invalidPrintingChoice
            }
        case let .resolved(resolution):
            // A persisted choice from before singleton auto-resolution may
            // still be answered in recovery. Revalidate it through the adapter
            // below, and accept only the exact printing now resolved.
            guard resolution.card.physicalPrintingID == candidate.id,
                  resolution.card.canonicalCardID == candidate.canonicalCardID else {
                throw CatalogLookupError.invalidPrintingChoice
            }
        case .catalogIncomplete:
            throw CatalogLookupError.invalidPrintingChoice
        }
        let resolution = try await adapter.resolve(candidate, for: identifier)
        guard gameCatalogAdapters.adapter(for: identifier.game)?.generation == adapter.generation else {
            throw CatalogLookupError.staleCatalog
        }
        guard resolution.card.game == candidate.game,
              resolution.card.physicalPrintingID == candidate.id,
              resolution.card.canonicalCardID == candidate.canonicalCardID,
              resolution.card.language == candidate.language else { throw CatalogLookupError.invalidAdapterOutcome }
        return resolution
    }

    func cachedCard(for identifier: ScanIdentifier) -> IdentifiedCard? {
        guard let adapter = gameCatalogAdapters.adapter(for: identifier.game),
              let prepared = try? adapter.prepareLookupIdentifier(identifier),
              case let .resolved(resolution)? = adapterOutcomes[prepared] else { return nil }
        return resolution.card
    }

    func card(for candidate: PokemonCatalogCardIdentity, matching evidence: PokemonHistoricalScanEvidence) async throws -> IdentifiedCard {
        guard let adapter = gameCatalogAdapters.pokemonCatalog else { throw PokemonHistoricalCatalogError.unsupported }
        return try await adapter.card(for: candidate, matching: evidence)
    }

    static func classify(_ error: Error) -> CatalogFailure {
        switch error {
        case is CatalogLookupError:
            // A local identity/generation failure cannot be repaired by
            // repeating the same network request or old identifier.
            return .notInCatalog
        case is PokemonHistoricalCatalogError:
            return .notInCatalog
        case TCGdexError.cardNotFound, TCGdexError.identityMismatch, TCGdexError.invalidURL,
             ScryfallError.cardNotFound, ScryfallError.identityMismatch,
             ScryfallError.unsupportedPrinting, ScryfallError.invalidURL:
            return .notInCatalog
        case ScryfallError.endpointNotFound,
             ScryfallError.rateLimited,
             ScryfallError.providerUnavailable:
            return .providerUnavailable
        default:
            return .transient
        }
    }

    static func isProviderNotFound(_ error: Error) -> Bool {
        switch error {
        case TCGdexError.cardNotFound, ScryfallError.cardNotFound:
            return true
        default:
            return false
        }
    }

}
