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

    fileprivate static func generation(for registry: PokemonCatalogRegistry) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try! encoder.encode(registry.descriptors)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return "pokemon:\(registry.revision):\(digest)"
    }

    func prepareLookupIdentifier(_ identifier: ScanIdentifier) throws -> ScanIdentifier {
        guard identifier.game == game else { throw CatalogLookupError.staleCatalog }
        switch identifier.legacyIdentity {
        case .pokemon, .pokemonPromo: break // Keep the scan's captured definition.
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
        switch identifier.legacyIdentity {
        case .pokemon, .pokemonPromo: return true
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
        return .resolved(try await engine.resolution(for: prepared))
    }

    func resolve(_ candidate: PhysicalPrintingCandidate, for identifier: ScanIdentifier) async throws -> CardCatalog.CatalogResolution {
        throw CatalogLookupError.invalidPrintingChoice
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
    func card(for candidate: PokemonCatalogCardIdentity, matching evidence: PokemonHistoricalScanEvidence) async throws -> IdentifiedCard {
        try await engine.card(for: candidate, matching: evidence)
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
        await offline.candidates(for: number)
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
        matching evidence: PokemonHistoricalScanEvidence
    ) async throws -> IdentifiedCard {
        guard PokemonNameMatcher.agrees(
            cardName: candidate.name,
            readings: evidence.titleCandidates
        ) else {
            throw TCGdexError.identityMismatch
        }
        if let selectedOfflineCard = await offline.card(
            for: candidate,
            number: evidence.number
        ) {
            return applyingSignedArtwork(to: selectedOfflineCard)
        }
        if let offlineCard = await offline.historicalCard(for: evidence),
           case let .pokemon(card, _) = offlineCard.legacyIdentity,
           card.id.caseInsensitiveCompare(candidate.providerID) == .orderedSame,
           card.set.id.caseInsensitiveCompare(candidate.setID) == .orderedSame,
           PokemonHistoricalIdentityResolver.canonicalLocalID(card.localId)
                == PokemonHistoricalIdentityResolver.canonicalLocalID(candidate.localID) {
            return applyingSignedArtwork(to: offlineCard)
        }
        let card = try await historicalPokemon.card(
            for: candidate,
            matching: evidence,
            registry: catalogRegistry
        )
        return applyingSignedArtwork(to: card)
    }

    func resolution(for identifier: ScanIdentifier) async throws -> CatalogResolution {
        if case .pokemonHistorical = identifier.legacyIdentity,
           identifier.catalogGeneration != catalogGeneration { throw CatalogLookupError.staleCatalog }
        let resolution = try await fetchResolution(identifier)
        if case .pokemonHistorical = identifier.legacyIdentity,
           identifier.catalogGeneration != catalogGeneration { throw CatalogLookupError.staleCatalog }
        let card = applyingSignedArtwork(to: resolution.card)
        let enriched = CatalogResolution(card, isPersistable: resolution.isPersistable,
            retrievedAt: resolution.retrievedAt, path: resolution.path)
        if enriched.isPersistable, case let .pokemon(pokemonCard, setCode) = card.legacyIdentity,
           let key = Self.persistentKey(for: identifier) {
            let count: Int?
            switch identifier.legacyIdentity {
            case let .pokemon(_, _, denominator, _): count = denominator
            case let .pokemonHistorical(evidence): count = evidence.number.denominator
            default: count = nil
            }
            await resolvedDiskCache.store(card: pokemonCard, setCode: setCode, key: key, officialCount: count)
        }
        return enriched
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
            if let diskKey,
               let cached = await resolvedDiskCache.card(for: diskKey) {
                let historicalCacheIsStale: Bool
                if case let .pokemonHistorical(evidence) = identifier.legacyIdentity {
                    let membership = PokemonHistoricalIdentityResolver.membershipIdentities(
                        for: evidence,
                        in: registry
                    )
                    historicalCacheIsStale = registry.isScanDisabled(
                        forProviderSetID: cached.card.set.id
                    ) || membership.contains {
                        $0.providerID.caseInsensitiveCompare(cached.card.id) != .orderedSame
                    }
                } else {
                    historicalCacheIsStale = false
                }
                if historicalCacheIsStale {
                    // A historical card can be served by an older persistent
                    // cache entry even after its set is withdrawn or a newer
                    // membership reveals an ambiguous reprint. Remove it and
                    // continue through the registry-gated paths below;
                    // already-dispatched modern identifiers remain valid because
                    // their captured definition is part of the identifier.
                    await resolvedDiskCache.invalidateEntry(for: diskKey)
                } else {
                    return CatalogResolution(
                        .pokemon(cached.card, setCode: cached.setCode),
                        retrievedAt: cached.storedAt,
                        path: .cacheHit
                    )
                }
            }

            switch identifier.legacyIdentity {
            case .opaque:
                throw CardGameSupportError.unsupportedGame(identifier.game)
            case let .pokemon(setCode, cardNumber, printedTotal, setDefinition):
                if let card = await offline.card(
                    providerSetID: setDefinition.tcgdexSetID,
                    localID: cardNumber,
                    expectedOfficialCount: printedTotal
                ) {
                    return CatalogResolution(.pokemon(card, setCode: setCode), path: .cacheHit)
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
                    return CatalogResolution(.pokemon(card, setCode: prefix), path: .cacheHit)
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

    private func applyingSignedArtwork(to identifiedCard: IdentifiedCard) -> IdentifiedCard {
        guard case let .pokemon(card, setCode) = identifiedCard.legacyIdentity,
              !Self.hasUsableArtworkURL(card.image),
              let descriptor = catalogRegistry.descriptor(forProviderSetID: card.set.id),
              let artwork = descriptor.cardArtwork?.first(where: {
                  CatalogIdentityNormalization.localNumber($0.localID)
                    == CatalogIdentityNormalization.localNumber(card.localId)
              }),
              let image = Self.artworkBaseURL(from: artwork.imageURL) else {
            return identifiedCard
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
            variantsDetailed: card.variantsDetailed
        )
        return .pokemon(signedCard, setCode: setCode)
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
