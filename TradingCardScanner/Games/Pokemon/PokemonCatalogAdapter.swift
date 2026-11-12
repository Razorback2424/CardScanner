import Foundation
import CryptoKit

/// Immutable identity/authority snapshot over the existing Pokémon provider engine.
struct PokemonCatalogAdapter: GameCatalogAdapter {
    let game = CardGame.pokemon
    let generation: String
    let registry: PokemonCatalogRegistry
    private let engine: PokemonCatalogEngine

    init(source: any PokemonCardSource = LivePokemonCardSource(),
         offline: PokemonOfflineCatalog? = nil,
         resolvedDiskCache: ResolvedPokemonCardCache = ResolvedPokemonCardCache(),
         tcgdexBreaker: TCGdexCircuitBreaker = .shared,
         registry: PokemonCatalogRegistry = .bundledSeed) {
        self.init(registry: registry, engine: PokemonCatalogEngine(source: source, offline: offline,
            resolvedDiskCache: resolvedDiskCache, tcgdexBreaker: tcgdexBreaker, registry: registry))
    }

    private init(registry: PokemonCatalogRegistry, engine: PokemonCatalogEngine) {
        self.registry = registry; self.engine = engine
        generation = Self.generation(for: registry)
    }

    static func generation(for registry: PokemonCatalogRegistry) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try! encoder.encode(registry.descriptors)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return "pokemon:\(registry.revision):\(digest)"
    }

    func prepareLookupIdentifier(_ identifier: ScanIdentifier) throws -> ScanIdentifier {
        guard identifier.game == game else { throw CatalogLookupError.staleCatalog }
        if identifier.namespace == PokemonUnnumberedEnergyEvidence.namespace {
            guard identifier.catalogGeneration == nil || identifier.catalogGeneration == generation,
                  let family = PokemonUnnumberedEnergyEvidence.family(for: identifier, registry: registry)
            else { throw CatalogLookupError.staleCatalog }
            return PokemonUnnumberedEnergyEvidence.identifier(year: family.year, generation: generation)
        }
        let expectedFields: Set<String>
        switch identifier.namespace {
        case "modern": expectedFields = ["printedCode", "localID", "denominator", "providerSetID", "officialCount", "releaseIndex"]
        case "promo": expectedFields = ["prefix", "localID", "providerSetID", "catalogLocalIDPrefix", "localIDPadWidth"]
        case "energy": expectedFields = ["printedCode", "localID", "providerSetID", "localIDPadWidth"]
        case "historical": expectedFields = ["localID", "denominator", "subsetPrefix", "titleReadings"]
        default: throw CatalogLookupError.invalidAdapterOutcome
        }
        guard Set(identifier.fields.map(\.key)) == expectedFields else { throw CatalogLookupError.invalidAdapterOutcome }
        switch identifier.legacyIdentity {
        case .pokemon, .pokemonPromo, .pokemonEnergy: break // Keep the scan's captured definition.
        case .pokemonHistorical:
            guard identifier.catalogGeneration == nil || identifier.catalogGeneration == generation else {
                throw CatalogLookupError.staleCatalog
            }
        default: throw CatalogLookupError.invalidAdapterOutcome
        }
        return try .init(game: game, namespace: identifier.namespace, fields: identifier.fields,
            displayIdentifier: identifier.displayIdentifier, suppressionIdentity: identifier.suppressionIdentity,
            catalogGeneration: generation)
    }

    func acceptsCompletion(for identifier: ScanIdentifier, fromGeneration: String) -> Bool {
        guard identifier.game == game else { return false }
        if identifier.namespace == PokemonUnnumberedEnergyEvidence.namespace {
            return generation == fromGeneration
        }
        switch identifier.legacyIdentity {
        case .pokemon, .pokemonPromo, .pokemonEnergy: return true
        case .pokemonHistorical: return generation == fromGeneration
        default: return false
        }
    }

    func identifierForRetry(_ identifier: ScanIdentifier) throws -> ScanIdentifier {
        // Recovery rebases printed evidence; it never restores a previous choice.
        let rebased = try ScanIdentifier(game: identifier.game, namespace: identifier.namespace,
            fields: identifier.fields, displayIdentifier: identifier.displayIdentifier,
            suppressionIdentity: identifier.suppressionIdentity)
        return try prepareLookupIdentifier(rebased)
    }

    func lookup(_ identifier: ScanIdentifier) async throws -> CatalogLookupOutcome {
        let prepared = try prepareLookupIdentifier(identifier)
        if let family = PokemonUnnumberedEnergyEvidence.family(for: prepared, registry: registry) {
            let summary = CanonicalCardSummary(id: prepared.suppressionIdentity, game: game,
                name: "\(family.year) Energy", printedIdentifier: prepared.displayIdentifier, language: "en")
            return .needsPrintingChoice(canonical: summary, candidates: unnumberedChoices(family, for: prepared))
        }
        return .resolved(try await engine.resolution(for: prepared))
    }

    func resolve(_ candidate: PhysicalPrintingCandidate, for identifier: ScanIdentifier) async throws -> CardCatalog.CatalogResolution {
        let prepared = try prepareLookupIdentifier(identifier)
        guard let family = PokemonUnnumberedEnergyEvidence.family(for: prepared, registry: registry),
              unnumberedChoices(family, for: prepared).contains(where: { $0.matchesPersistedChoice(candidate) }),
              let card = PokemonReviewedEnergyCatalog.unnumberedCard(providerID: candidate.id) else {
            throw CatalogLookupError.invalidPrintingChoice
        }
        let resolved = IdentifiedCard(legacy: .pokemon(card.applyingAdditionalVariants(from: registry), setCode: family.setCode),
                                      canonicalCardID: prepared.suppressionIdentity)
        return .init(resolved, path: .cacheHit)
    }

    private func unnumberedChoices(_ family: PokemonReviewedEnergyCatalog.UnnumberedFamily,
                                   for identifier: ScanIdentifier) -> [PhysicalPrintingCandidate] {
        family.cards.map { card in
            PhysicalPrintingCandidate(id: card.providerID, game: game, canonicalCardID: identifier.suppressionIdentity,
                language: "en", catalogGeneration: generation, name: card.name, printedIdentifier: "Unnumbered",
                thumbnailURL: card.thumbnailURL)
        }
    }

    func prewarm() async { await engine.prewarm() }
    func sessionCopy() -> Self {
        Self(registry: registry, engine: engine.sessionCopy(registry: registry))
    }
    func updating(_ registry: PokemonCatalogRegistry) async -> Self {
        await engine.updateRegistry(registry)
        return await Self(registry: engine.currentRegistry(), engine: engine)
    }
    func candidates(for number: PokemonPrintedNumberEvidence) async -> [PokemonCatalogCardIdentity] {
        await engine.candidates(for: number)
    }
    func recoveringArtwork(for resolution: CardCatalog.CatalogResolution,
                           identifier: ScanIdentifier) async -> CardCatalog.CatalogResolution {
        let card = await engine.recoveringArtworkIfNeeded(for: resolution.card)
        let enriched = CardCatalog.CatalogResolution(card, isPersistable: resolution.isPersistable,
            retrievedAt: resolution.retrievedAt, path: resolution.path)
        await engine.persistRecoveredArtwork(enriched, for: identifier)
        return enriched
    }
    func card(for candidate: PokemonCatalogCardIdentity, matching evidence: PokemonHistoricalScanEvidence,
              recoverArtwork: Bool = true) async throws -> IdentifiedCard {
        try await engine.card(for: candidate, matching: evidence, recoverArtwork: recoverArtwork)
    }
}

extension GameCatalogAdapterRegistry {
    var pokemonCatalog: PokemonCatalogAdapter? { adapter(for: .pokemon) as? PokemonCatalogAdapter }
    func installingLegacyDefaults(pokemon: @autoclosure () -> PokemonCatalogAdapter, magicCoordinator: MagicCatalogCoordinator?) -> Self {
        let installed: Self
        if let existing = pokemonCatalog { installed = replacing(existing.sessionCopy()) }
        else { installed = adapter(for: .pokemon) == nil ? replacing(pokemon()) : self }
        return installed.installingLegacyDefaults(magicCoordinator: magicCoordinator)
    }
}

actor PokemonCatalogEngine {
    typealias CatalogResolution = CardCatalog.CatalogResolution
    private let pokemonSource: any PokemonCardSource
    private let offline: PokemonOfflineCatalog
    private let resolvedDiskCache: ResolvedPokemonCardCache
    private let tcgdexBreaker: TCGdexCircuitBreaker
    private let historicalPokemon: PokemonHistoricalCatalog
    private var catalogRegistry: PokemonCatalogRegistry
    private var catalogGeneration: String

    nonisolated func sessionCopy(registry: PokemonCatalogRegistry) -> PokemonCatalogEngine {
        PokemonCatalogEngine(source: pokemonSource, offline: offline.sessionCopy(registry: registry),
            resolvedDiskCache: resolvedDiskCache, tcgdexBreaker: tcgdexBreaker, registry: registry)
    }

    init(
        source: any PokemonCardSource = LivePokemonCardSource(),
        offline: PokemonOfflineCatalog? = nil,
        resolvedDiskCache: ResolvedPokemonCardCache = ResolvedPokemonCardCache(),
        tcgdexBreaker: TCGdexCircuitBreaker = .shared,
        registry: PokemonCatalogRegistry = .bundledSeed
    ) {
        self.pokemonSource = source
        self.offline = offline ?? PokemonOfflineCatalog(registry: registry)
        self.resolvedDiskCache = resolvedDiskCache
        self.tcgdexBreaker = tcgdexBreaker
        self.historicalPokemon = PokemonHistoricalCatalog(registry: registry)
        self.catalogRegistry = registry
        self.catalogGeneration = PokemonCatalogAdapter.generation(for: registry)
    }

    /// Installs the same immutable registry snapshot used by the scanner. The
    /// offline and live historical paths are updated together so a disabled set
    /// cannot resolve through the provider after it disappears from the OCR
    /// vocabulary. Existing in-flight resolutions are intentionally not
    /// cancelled; their identifiers already carry the snapshot that authorized
    /// them.
    func updateRegistry(_ registry: PokemonCatalogRegistry) async {
        guard catalogRegistry.revision != registry.revision
            || catalogRegistry.descriptors != registry.descriptors else { return }
        catalogRegistry = registry
        catalogGeneration = PokemonCatalogAdapter.generation(for: registry)
        await offline.updateRegistry(registry)
        await offline.invalidate()
        await historicalPokemon.updateRegistry(registry)
    }

    func candidates(
        for number: PokemonPrintedNumberEvidence
    ) async -> [PokemonCatalogCardIdentity] {
        (try? await offline.candidates(for: number, registry: catalogRegistry)) ?? []
    }

    /// Starts loading both persistent sources before the camera begins feeding
    /// candidates. The calls are independent and safe to repeat for a session.
    func prewarm() async {
        await offline.updateRegistry(catalogRegistry)
        await historicalPokemon.updateRegistry(catalogRegistry)
        async let offlineWarm: Void = offline.prewarm()
        async let diskWarm: Void = resolvedDiskCache.prewarm()
        _ = await (offlineWarm, diskWarm)
    }

    func card(
        for candidate: PokemonCatalogCardIdentity,
        matching evidence: PokemonHistoricalScanEvidence,
        recoverArtwork: Bool = true
    ) async throws -> IdentifiedCard {
        let registry = catalogRegistry
        let generation = catalogGeneration
        guard !PokemonFinishMinimumCatalog.isUnnumbered(cardID: candidate.providerID),
              PokemonNameMatcher.agrees(
            cardName: candidate.name,
            readings: evidence.titleCandidates
        ) else {
            throw TCGdexError.identityMismatch
        }
        if let selectedOfflineCard = try await offline.card(
            for: candidate,
            number: evidence.number,
            registry: registry
        ) {
            guard generation == catalogGeneration else { throw CatalogLookupError.staleCatalog }
            return applyingSignedArtwork(to: selectedOfflineCard, registry: registry)
        }
        if let offlineCard = try await offline.historicalCard(for: evidence, registry: registry),
           case let .pokemon(card, _) = offlineCard.legacyIdentity,
           card.id.caseInsensitiveCompare(candidate.providerID) == .orderedSame,
           card.set.id.caseInsensitiveCompare(candidate.setID) == .orderedSame,
           PokemonHistoricalIdentityResolver.canonicalLocalID(card.localId)
                == PokemonHistoricalIdentityResolver.canonicalLocalID(candidate.localID) {
            guard generation == catalogGeneration else { throw CatalogLookupError.staleCatalog }
            return applyingSignedArtwork(to: offlineCard, registry: registry)
        }
        let card = try await historicalPokemon.card(
            for: candidate,
            matching: evidence,
            registry: registry
        )
        let authorized = applyingSignedArtwork(to: card, registry: registry)
        let enriched = recoverArtwork ? await recoveringArtworkIfNeeded(for: authorized) : authorized
        try Task.checkCancellation()
        guard generation == catalogGeneration else { throw CatalogLookupError.staleCatalog }
        return enriched
    }

    func resolution(for identifier: ScanIdentifier) async throws -> CatalogResolution {
        let registry = catalogRegistry
        if case .pokemonHistorical = identifier.legacyIdentity,
           identifier.catalogGeneration != catalogGeneration { throw CatalogLookupError.staleCatalog }
        let resolution = try await fetchResolution(identifier)
        if case .pokemonHistorical = identifier.legacyIdentity,
           identifier.catalogGeneration != catalogGeneration { throw CatalogLookupError.staleCatalog }
        if case let .pokemon(card, _) = resolution.card.legacyIdentity,
           PokemonFinishMinimumCatalog.isUnnumbered(cardID: card.id) {
            throw PokemonHistoricalCatalogError.unsupported
        }
        // Optional image discovery must not hold the serial scan lane. Signed
        // and payload artwork remain immediate; Collection's existing missing-
        // metadata normalizer recovers omitted provider images after intake.
        let card = applyingSignedArtwork(to: resolution.card, registry: registry)
        let enriched = CatalogResolution(card, isPersistable: resolution.isPersistable,
            retrievedAt: resolution.retrievedAt, path: resolution.path)
        await persistResolution(enriched, for: identifier)
        return enriched
    }

    private func persistResolution(_ enriched: CatalogResolution, for identifier: ScanIdentifier) async {
        if identifier.catalogGeneration == catalogGeneration, enriched.isPersistable, enriched.path == .network,
           case let .pokemon(pokemonCard, setCode) = enriched.card.legacyIdentity,
           let key = Self.persistentKey(for: identifier) {
            let count: Int?
            switch identifier.legacyIdentity {
            case let .pokemon(_, _, denominator, _): count = denominator
            case let .pokemonHistorical(evidence): count = evidence.number.denominator
            default: count = nil
            }
            let fingerprint = catalogRegistry.resolvedCardCacheFingerprint(forProviderSetID: pokemonCard.set.id)
            await resolvedDiskCache.store(card: pokemonCard, setCode: setCode, key: key,
                officialCount: count, catalogFingerprint: fingerprint)
        }
    }

    func persistRecoveredArtwork(_ enriched: CatalogResolution, for identifier: ScanIdentifier) async {
        guard identifier.catalogGeneration == catalogGeneration, enriched.isPersistable, enriched.path == .network,
              case let .pokemon(card, _) = enriched.card.legacyIdentity,
              let image = card.storedArtworkURL, let key = Self.persistentKey(for: identifier) else { return }
        let fingerprint = catalogRegistry.resolvedCardCacheFingerprint(forProviderSetID: card.set.id)
        await resolvedDiskCache.addArtwork(image, cardID: card.id, key: key, catalogFingerprint: fingerprint)
    }

    func currentRegistry() -> PokemonCatalogRegistry { catalogRegistry }
    private func fetchResolution(_ identifier: ScanIdentifier) async throws -> CatalogResolution {
        let pokemonSource = pokemonSource
        let offline = offline
        let resolvedDiskCache = resolvedDiskCache
        let tcgdexBreaker = tcgdexBreaker
        let historicalPokemon = historicalPokemon
        let registry = catalogRegistry
        let diskKey = Self.persistentKey(for: identifier)
        let load: @Sendable () async throws -> CatalogResolution = {
            // The reviewed source retains generic stamp provenance that legacy
            // disk entries do not encode. It is deterministic and needs no I/O.
            if case let .pokemonEnergy(code, number, definition) = identifier.legacyIdentity,
               let card = PokemonReviewedEnergyCatalog.card(setID: definition.tcgdexSetID, localID: number) {
                return CatalogResolution(.pokemon(card, setCode: code), path: .cacheHit)
            }
            if case let .pokemon(_, localID, count, definition) = identifier.legacyIdentity {
                let number = PokemonPrintedNumberEvidence(localID: localID, denominator: count, scheme: .officialSet)
                let choices = PokemonReviewedArtworkCatalog.identities(for: number, registry: registry)
                    .filter { $0.setID == definition.tcgdexSetID }
                if choices.count > 1 { throw PokemonHistoricalCatalogError.ambiguous(choices) }
            }
            var requiresExactChecklistFingerprint = false
            if let diskKey, let cached = await resolvedDiskCache.card(for: diskKey) {
                let fingerprint = registry.resolvedCardCacheFingerprint(forProviderSetID: cached.card.set.id)
                if cached.catalogFingerprint == fingerprint {
                    return CatalogResolution(
                        .pokemon(cached.card, setCode: cached.setCode),
                        retrievedAt: cached.storedAt,
                        path: .cacheHit
                    )
                }
                // Once a resolved set changes, an older offline checklist
                // must not refill the same cache entry under the new authority.
                requiresExactChecklistFingerprint = cached.catalogFingerprint != nil
            }

            func checklistResolution(
                providerSetID: String, localID: String, officialCount: Int?, setCode: String
            ) async throws -> CatalogResolution? {
                let fingerprint = registry.descriptor(forProviderSetID: providerSetID)?.providerFingerprint
                guard let match = try await offline.cardWithSource(
                    providerSetID: providerSetID, localID: localID, expectedOfficialCount: officialCount,
                    registry: registry, requiresExactFingerprint: requiresExactChecklistFingerprint
                ) else { return nil }
                let provisional = fingerprint != nil && match.providerFingerprint != fingerprint
                return CatalogResolution(.pokemon(match.card, setCode: setCode),
                    path: provisional ? .offlineFallback : .cacheHit)
            }

            func preferCurrent(_ local: CatalogResolution?,
                               live: () async throws -> CatalogResolution) async throws -> CatalogResolution {
                if let local, local.path != .offlineFallback { return local }
                do {
                    let current = try await live()
                    return current.path == .historicalFallback ? local ?? current : current
                } catch {
                    if error is CancellationError || Task.isCancelled { throw error }
                    if case .notInCatalog = CardCatalog.classify(error) { throw error }
                    if let local { return local }
                    throw error
                }
            }

            switch identifier.legacyIdentity {
            case .opaque:
                throw CardGameSupportError.unsupportedGame(identifier.game)
            case let .pokemon(setCode, cardNumber, printedTotal, setDefinition):
                let local = try await checklistResolution(providerSetID: setDefinition.tcgdexSetID,
                    localID: cardNumber, officialCount: printedTotal, setCode: setCode)
                return try await preferCurrent(local) {
                    try await Self.resolveModernPokemon(
                        setCode: setCode, cardNumber: cardNumber, setDefinition: setDefinition,
                        source: pokemonSource, breaker: tcgdexBreaker
                    )
                }

            case let .pokemonEnergy(code, localID, definition):
                let local = try await checklistResolution(providerSetID: definition.tcgdexSetID,
                    localID: localID, officialCount: nil, setCode: code)
                // Existing 001–008 use the same exact set/local-ID transport contract as promos.
                return try await preferCurrent(local) {
                    try await Self.resolvePromoPokemon(prefix: code, localID: localID,
                        setDefinition: .init(printedPrefix: code, tcgdexSetID: definition.tcgdexSetID,
                            catalogLocalIDPrefix: "", localIDPadWidth: definition.localIDPadWidth),
                        source: pokemonSource, breaker: tcgdexBreaker)
                }

            case let .pokemonPromo(prefix, localID, setDefinition):
                let local = try await checklistResolution(providerSetID: setDefinition.tcgdexSetID,
                    localID: localID, officialCount: nil, setCode: prefix)
                return try await preferCurrent(local) {
                    try await Self.resolvePromoPokemon(
                        prefix: prefix, localID: localID, setDefinition: setDefinition,
                        source: pokemonSource, breaker: tcgdexBreaker
                    )
                }

            case let .pokemonHistorical(evidence):
                // A shared reprint footer is already ambiguous on device. Do
                // not turn the offline factory's nil (no unique card) into a
                // provider request before offering those known printings.
                let artworks = PokemonReviewedArtworkCatalog.identities(for: evidence.number, registry: registry)
                if !artworks.isEmpty || !PokemonHistoricalIdentityResolver.membershipIdentities(
                    for: evidence.number, in: registry
                ).isEmpty {
                    let candidates = try await offline.candidates(for: evidence.number, registry: registry) + artworks
                    if case let .ambiguous(matches) = PokemonHistoricalIdentityResolver.resolve(
                        evidence,
                        candidateSetIDs: candidates.map(\.setID),
                        in: candidates
                    ) {
                        throw PokemonHistoricalCatalogError.ambiguous(matches)
                    }
                }
                if let card = try await offline.historicalCard(for: evidence, registry: registry) {
                    return CatalogResolution(card, path: .cacheHit)
                }
                return CatalogResolution(
                    try await historicalPokemon.card(for: evidence, registry: registry),
                    path: .historicalFallback
                )

            default:
                throw CardGameSupportError.unsupportedGame(identifier.game)
            }
        }
        return try await load()
    }

    private static func persistentKey(for identifier: ScanIdentifier) -> String? {
        switch identifier.legacyIdentity {
        case .opaque: return nil
        case let .pokemon(_, cardNumber, printedTotal, setDefinition):
            return "pokemon|\(setDefinition.tcgdexSetID.lowercased())|\(PokemonHistoricalIdentityResolver.canonicalLocalID(cardNumber))|\(printedTotal)"
        case let .pokemonPromo(prefix, localID, setDefinition):
            return "pokemon-promo|\(prefix.uppercased())|\(setDefinition.tcgdexSetID.lowercased())|\(PokemonHistoricalIdentityResolver.canonicalLocalID(localID))"
        case let .pokemonEnergy(code, localID, definition):
            return "pokemon-energy|\(code)|\(definition.tcgdexSetID)|\(localID)"
        case .pokemonHistorical:
            // Historical identity is resolved from unstable OCR title evidence;
            // there is no safe stable key before the catalog response arrives.
            // Keep it session-cached only rather than poisoning the disk cache
            // with one key per OCR spelling.
            return nil
        default:
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
                    isPersistable: true,
                    path: .network
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
        return CatalogResolution(
            .pokemon(card, setCode: setCode),
            path: .historicalFallback
        )
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
                    isPersistable: true,
                    path: .network
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
        return CatalogResolution(
            .pokemon(card, setCode: prefix),
            path: .historicalFallback
        )
    }

    func recoveringArtworkIfNeeded(for identifiedCard: IdentifiedCard) async -> IdentifiedCard {
        guard case let .pokemon(card, setCode) = identifiedCard.legacyIdentity,
              card.storedArtworkURL == nil else { return identifiedCard }
        let registry = card.acquisitionCatalog ?? catalogRegistry
        return applyingSignedArtwork(to: .pokemon(await pokemonSource.recoveringArtwork(for: card), setCode: setCode),
            registry: registry)
    }

    private func applyingSignedArtwork(to identifiedCard: IdentifiedCard,
                                       registry: PokemonCatalogRegistry? = nil) -> IdentifiedCard {
        guard case let .pokemon(rawCard, setCode) = identifiedCard.legacyIdentity else { return identifiedCard }
        // Reapply the captured registry on every path, including memory/disk
        // hits. An old authorization cannot survive its signed removal.
        let registry = registry ?? catalogRegistry
        let card = rawCard.applyingAdditionalVariants(from: registry)
        guard !Self.hasUsableArtworkURL(card.image),
              let descriptor = registry.descriptor(forProviderSetID: card.set.id),
              let artwork = descriptor.cardArtwork?.first(where: {
                  CatalogIdentityNormalization.localNumber($0.localID)
                    == CatalogIdentityNormalization.localNumber(card.localId)
              }),
              let image = Self.artworkBaseURL(from: artwork.imageURL) else {
            return .pokemon(card, setCode: setCode)
        }
        let signedCard = TCGdexCard(
            id: card.id,
            localId: card.localId,
            name: card.name,
            image: image,
            rarity: card.rarity,
            set: card.set,
            variants: card.variants,
            pricing: card.pricing,
            variantsDetailed: card.variantsDetailed,
            projectedCatalogVariants: card.projectedCatalogVariants
        )
        return .pokemon(signedCard.applyingAdditionalVariants(from: registry), setCode: setCode)
    }

    private static func hasUsableArtworkURL(_ raw: String?) -> Bool {
        guard let raw,
              let components = URLComponents(string: raw),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              !components.path.isEmpty else { return false }
        return components.url != nil
    }

    private static func artworkBaseURL(from raw: String) -> String? {
        guard var components = URLComponents(string: raw),
              components.scheme?.lowercased() == "https",
              components.host != nil else { return nil }
        if components.path.hasSuffix("/high.png") {
            components.path.removeLast("/high.png".count)
        }
        return components.url?.absoluteString
    }
}
