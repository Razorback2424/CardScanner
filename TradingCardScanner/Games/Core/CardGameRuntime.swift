import Foundation
import SwiftUI
import SwiftData
import OSLog

private struct CardGameRuntimesKey: EnvironmentKey {
    static let defaultValue: CardGameRuntimeContainer? = nil
}

extension EnvironmentValues {
    var cardGameRuntimes: CardGameRuntimeContainer? {
        get { self[CardGameRuntimesKey.self] }
        set { self[CardGameRuntimesKey.self] = newValue }
    }
}

/// Existing coordinator bindings are isolated here during adapter extraction.
/// New games add catalog/browse adapters, not additional legacy binding fields.
struct LegacyCatalogBindings: Sendable {
    let pokemon: PokemonCatalogCoordinator?
    let magic: MagicCatalogCoordinator?

    init(pokemon: PokemonCatalogCoordinator? = nil, magic: MagicCatalogCoordinator? = nil) {
        self.pokemon = pokemon
        self.magic = magic
    }
}

struct CardGameRuntime: Sendable {
    let descriptor: CardGameDescriptor
    let variantPolicy: any GameVariantPolicy
    let pricing: (any GamePriceAdapter)?
    let recognizer: (any GameRecognitionAdapter)?
    let catalog: (any GameCatalogAdapter)?
    let browse: (any GameBrowseAdapter)?
    let importer: (any GameImportAdapter)?
    let priceAuthority: GameCatalogPriceAuthority?
    let activationSource: (any GameCatalogActivationSource)?
    /// Optional rollout modules may be omitted if their collection authority cannot be prepared.
    let requiresLaunchActivation: Bool
    let legacyCatalogBindings: LegacyCatalogBindings

    init(descriptor: CardGameDescriptor, variantPolicy: any GameVariantPolicy,
         pricing: (any GamePriceAdapter)? = nil,
         recognizer: (any GameRecognitionAdapter)? = nil,
         catalog: (any GameCatalogAdapter)? = nil,
         browse: (any GameBrowseAdapter)? = nil,
         importer: (any GameImportAdapter)? = nil,
         priceAuthority: GameCatalogPriceAuthority? = nil,
         activationSource: (any GameCatalogActivationSource)? = nil,
         requiresLaunchActivation: Bool = true,
         legacyCatalogBindings: LegacyCatalogBindings = .init()) {
        self.descriptor = descriptor
        self.variantPolicy = variantPolicy
        self.pricing = pricing
        self.recognizer = recognizer
        self.catalog = catalog
        self.browse = browse
        self.importer = importer
        self.priceAuthority = priceAuthority
        self.activationSource = activationSource
        self.requiresLaunchActivation = requiresLaunchActivation
        self.legacyCatalogBindings = legacyCatalogBindings
    }
}

struct CardGameRuntimeContainer: Sendable {
    enum RegistrationError: Error, Equatable {
        case duplicateGame(CardGame)
        case duplicateLegacyBinding
        case pricingGameMismatch(CardGame)
        case catalogGameMismatch(CardGame)
        case browseGameMismatch(CardGame)
        case importGameMismatch(CardGame)
        case recognitionGameMismatch(CardGame)
        case activationGameMismatch(CardGame)
    }
    private let runtimes: [CardGame: CardGameRuntime]
    let registry: CardGameRegistry
    /// Configured modules that failed preparation, distinct from disabled games.
    let unavailableGames: [CardGameDescriptor]
    /// Static price authorities that `bound(to:deferringPriceAuthorityInstall:)`
    /// left for `installDeferredPriceAuthorities` to apply after launch.
    let deferredPriceAuthorities: [GameCatalogPriceAuthority]
    private let legacyBindings: LegacyCatalogBindings
    private let pricingAdapters: GamePriceAdapterRegistry
    private let catalogAdapters: GameCatalogAdapterRegistry
    private let recognitionAdapters: GameRecognitionRegistry

    init(runtimes: [CardGameRuntime], unavailableGames: [CardGameDescriptor] = [],
         capabilityState: GameCatalogCapabilityState? = nil,
         deferredPriceAuthorities: [GameCatalogPriceAuthority] = []) throws {
        var values: [CardGame: CardGameRuntime] = [:]
        for runtime in runtimes {
            let game = runtime.descriptor.game
            guard values[game] == nil else { throw RegistrationError.duplicateGame(game) }
            guard runtime.pricing == nil || runtime.pricing?.game == game else {
                throw RegistrationError.pricingGameMismatch(game)
            }
            guard runtime.catalog == nil || runtime.catalog?.game == game else {
                throw RegistrationError.catalogGameMismatch(game)
            }
            guard runtime.browse == nil || runtime.browse?.game == game else {
                throw RegistrationError.browseGameMismatch(game)
            }
            guard runtime.importer == nil || runtime.importer?.game == game else {
                throw RegistrationError.importGameMismatch(game)
            }
            guard runtime.recognizer == nil || runtime.recognizer?.game == game else {
                throw RegistrationError.recognitionGameMismatch(game)
            }
            guard runtime.activationSource == nil || runtime.activationSource?.game == game else {
                throw RegistrationError.activationGameMismatch(game)
            }
            values[game] = runtime
        }
        let pokemonBindings = runtimes.compactMap { $0.legacyCatalogBindings.pokemon }
        let magicBindings = runtimes.compactMap { $0.legacyCatalogBindings.magic }
        guard pokemonBindings.count <= 1, magicBindings.count <= 1 else {
            throw RegistrationError.duplicateLegacyBinding
        }
        self.runtimes = values
        self.deferredPriceAuthorities = deferredPriceAuthorities
        self.unavailableGames = unavailableGames.filter { values[$0.game] == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
        self.pricingAdapters = try GamePriceAdapterRegistry(adapters: runtimes.compactMap(\.pricing))
        self.catalogAdapters = try GameCatalogAdapterRegistry(adapters: runtimes.compactMap(\.catalog))
        self.recognitionAdapters = try GameRecognitionRegistry(recognizers: runtimes
            .filter { $0.descriptor.capabilities.contains(.scan) }.compactMap(\.recognizer))
        self.legacyBindings = .init(pokemon: pokemonBindings.first, magic: magicBindings.first)
        self.registry = CardGameRegistry(
            descriptors: runtimes.map(\.descriptor),
            variantPolicies: Dictionary(uniqueKeysWithValues: runtimes.map { ($0.descriptor.game, $0.variantPolicy) }),
            capabilityState: capabilityState
        )
    }

    func runtime(for game: CardGame) -> CardGameRuntime? { runtimes[game] }

    /// Bind once per authoritative storage session, before constructing consumers.
    ///
    /// With `deferringPriceAuthorityInstall`, static price-authority withdrawal
    /// is left out of binding so launch does not wait on it; the caller must
    /// then run `installDeferredPriceAuthorities` and recompute derived values
    /// if it withdrew anything.
    @MainActor
    func bound(to container: ModelContainer,
               recovering previous: Self? = nil,
               configurePricing: Bool = true,
               deferringPriceAuthorityInstall: Bool = false,
               isCurrent: @escaping @MainActor @Sendable () -> Bool = { true }) async throws -> Self {
        let interval = PerformanceSignpost.beginInterval("Launch.bind", id: PerformanceSignpost.makeID(), "")
        defer { PerformanceSignpost.endInterval("Launch.bind", interval, "") }
        guard isCurrent() else { throw PriceQuoteError.providerUnavailable }
        let storageGeneration = CollectionStorageGeneration.shared
        let token = storageGeneration.activeSession()?.container === container
            ? storageGeneration.currentToken() : nil
        let shouldContinue: StorageGenerationContinuation = token.map { storageGeneration.continuation(for: $0) } ?? { true }
        if previous == nil { configureCollectionAuthority(for: container, configurePricing: false) }
        var modules: [CardGameRuntime] = []
        var unavailable = unavailableGames
        var deferred: [GameCatalogPriceAuthority] = []
        let capabilities = previous?.registry.capabilityState ?? GameCatalogCapabilityState()
        for runtime in runtimes.values {
            // Existing consumers retain their authorities on a retry. Only an
            // omitted module needs activation and storage binding again.
            if let existing = previous?.runtime(for: runtime.descriptor.game) {
                modules.append(existing)
                continue
            }
            let source = runtime.activationSource.map { CollectionAuthorizedActivationSource(source: $0, container: container, isCurrent: isCurrent, capabilities: capabilities) }
            do {
                if let source {
                    guard await source.currentSnapshot() != nil else { throw PriceQuoteError.providerUnavailable }
                } else if let authority = runtime.priceAuthority, deferringPriceAuthorityInstall {
                    deferred.append(authority)
                } else if let authority = runtime.priceAuthority {
                    let installer = await CatalogPriceAuthorityInstaller.makeBackground(modelContainer: container)
                    try await installer.install(authority, shouldContinue: shouldContinue)
                    try Task.checkCancellation()
                    guard isCurrent() else { throw CancellationError() }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard isCurrent(), !runtime.requiresLaunchActivation else { throw error }
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "CardScanner", category: "CatalogBootstrap")
                    .error("Optional catalog activation failed; existing games remain available")
                unavailable.append(runtime.descriptor)
                continue
            }
            let pricing: (any GamePriceAdapter)?
            if let adapter = runtime.pricing, source != nil || runtime.priceAuthority != nil {
                pricing = ActivatedGamePriceAdapter(adapter: adapter, source: source, container: container)
            } else { pricing = runtime.pricing }
            modules.append(.init(descriptor: runtime.descriptor, variantPolicy: runtime.variantPolicy,
                pricing: pricing, recognizer: runtime.recognizer, catalog: runtime.catalog, browse: runtime.browse,
                importer: runtime.importer, priceAuthority: runtime.priceAuthority, activationSource: source,
                requiresLaunchActivation: runtime.requiresLaunchActivation,
                legacyCatalogBindings: runtime.legacyCatalogBindings))
        }
        guard isCurrent() else { throw PriceQuoteError.providerUnavailable }
        let bound = try Self(runtimes: modules, unavailableGames: unavailable, capabilityState: capabilities,
                             deferredPriceAuthorities: deferred)
        if let previous, previous.registry.games(supporting: []) == bound.registry.games(supporting: []) {
            return previous
        }
        bound.configureCollectionAuthority(for: container, configurePricing: configurePricing)
        return bound
    }

    /// Applies the withdrawals binding deferred, in one serialized transaction.
    /// Returns whether any managed price was withdrawn.
    func installDeferredPriceAuthorities(container: ModelContainer,
                                         shouldContinue: @escaping StorageGenerationContinuation) async throws -> Bool {
        guard !deferredPriceAuthorities.isEmpty else { return false }
        let installer = await CatalogPriceAuthorityInstaller.makeBackground(modelContainer: container)
        return try await installer.install(deferredPriceAuthorities, shouldContinue: shouldContinue)
    }

    /// Keep listening to omitted modules so a later verified release can
    /// trigger storage binding again without requiring an app relaunch.
    func optionalCatalogRecoveryEvents(for games: Set<CardGame>) -> AsyncStream<Void> {
        let sources = runtimes.values.filter {
            games.contains($0.descriptor.game) && !$0.requiresLaunchActivation
        }.compactMap(\.activationSource)
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                await withTaskGroup(of: Void.self) { group in
                    for source in sources {
                        group.addTask {
                            let events = await source.activationSnapshots()
                            // Subscribe before reading to close the launch/update race.
                            if await source.currentSnapshot() != nil { continuation.yield(()) }
                            for await _ in events {
                                guard !Task.isCancelled else { break }
                                continuation.yield(())
                            }
                        }
                    }
                    await group.waitForAll()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private var legacyCollectionCorrectionGames: Set<CardGame> {
        Set(runtimes.values.filter {
            $0.legacyCatalogBindings.pokemon != nil || $0.legacyCatalogBindings.magic != nil
        }.map { $0.descriptor.game })
    }

    @MainActor
    func configureCollectionAuthority(for container: ModelContainer, configurePricing: Bool = true) {
        if configurePricing { PriceRefreshController.shared.configureGamePricing(makePriceQuoteService()) }
        CollectionStore.configureGames(registry, for: container)
        CollectionStore.configureCatalogAdapters(
            catalogAdapters,
            legacyCorrectionGames: legacyCollectionCorrectionGames,
            for: container
        )
    }

    /// Keep finish-correction authority current even while the scanner is not
    /// visible. Each release revision is installed monotonically per game.
    func observeCollectionCatalogActivations(for container: ModelContainer) async {
        let sources = runtimes.values
            .filter { $0.descriptor.capabilities.contains(.collectionWrite) }
            .compactMap(\.activationSource)
        await withTaskGroup(of: Void.self) { group in
            for source in sources {
                group.addTask {
                    let updates = await source.activationSnapshots()
                    if let snapshot = await source.currentSnapshot(), snapshot.catalog.game == source.game {
                        CollectionStore.installCatalogAdapter(
                            snapshot.catalog, revision: snapshot.revision, for: container
                        )
                    }
                    for await snapshot in updates {
                        guard !Task.isCancelled else { break }
                        guard snapshot.catalog.game == source.game else { continue }
                        CollectionStore.installCatalogAdapter(
                            snapshot.catalog, revision: snapshot.revision, for: container
                        )
                    }
                }
            }
            await group.waitForAll()
        }
    }

    func makeImportAdapters() -> GameImportAdapterRegistry {
        try! .init(adapters: runtimes.values.compactMap(\.importer))
    }

    @MainActor
    func makeCollectionNormalizer() -> CollectionCatalogNormalizer {
        CollectionCatalogNormalizer(gameRegistry: registry, gameImportAdapters: makeImportAdapters(),
                                    gameActivationSources: runtimes.values.compactMap(\.activationSource),
                                    pokemonRegistry: { [coordinator = legacyBindings.pokemon] in
                                        guard let coordinator else { return .bundledSeed }
                                        await coordinator.loadPersistedOrBundled()
                                        return await coordinator.registry
                                    })
    }

    func currentImportAdapters() async -> GameImportAdapterRegistry {
        var adapters = makeImportAdapters()
        for runtime in runtimes.values {
            if let source = runtime.activationSource,
               let snapshot = await source.currentSnapshot(),
               let adapter = snapshot.importer, adapter.game == runtime.descriptor.game {
                adapters = adapters.replacing(adapter)
            }
        }
        return adapters
    }

    @MainActor private static var earlyPreparation: Task<CardGameRuntimeContainer, Never>?

    /// Starts default registration while the process launches, before the
    /// first frame schedules the launch task that consumes it.
    @MainActor
    static func startPreparingAppDefaults() {
        guard earlyPreparation == nil else { return }
        earlyPreparation = Task { await preparedAppDefaults() }
    }

    /// Consumes the early preparation once. Every other caller prepares afresh,
    /// so a retry re-reads configuration and the bundled seeds.
    @MainActor
    static func takePreparedAppDefaults() async -> Self {
        guard let early = earlyPreparation else { return await preparedAppDefaults() }
        earlyPreparation = nil
        return await early.value
    }

    /// Compile-time registration occurs once for the app session.
    static func preparedAppDefaults() async -> Self {
        // Decode the independent bundled seeds side by side. `appDefaults()`
        // then finds each ready, or waits only for the one it needs next.
        Task.detached(priority: .userInitiated) { _ = LorcanaDiscoveryCatalog.bundledMarket }
        if YuGiOhCatalogBootstrap.requestsDelivery() || YuGiOhBundledLaunch.cachedManifest() == nil {
            Task.detached(priority: .userInitiated) { _ = try? YuGiOhCatalog.bundledHandle.loaded() }
        }
        return await Task.detached(priority: .userInitiated) { appDefaults() }.value
    }

    private static func measured<T>(_ game: CardGame, _ body: () throws -> T) rethrows -> T {
        let interval = PerformanceSignpost.beginInterval(
            "Launch.catalogPrepare", id: PerformanceSignpost.makeID(), "game=\(game.rawValue)"
        )
        defer { PerformanceSignpost.endInterval("Launch.catalogPrepare", interval, "game=\(game.rawValue)") }
        return try body()
    }

    static func appDefaults() -> Self {
        var modules = measured(.pokemon) { [PokemonGameRuntime().runtime] }
        modules.append(measured(.magic) { MagicGameRuntime().runtime })
        var unavailable: [CardGameDescriptor] = []
        do {
            modules.append(try measured(.lorcana) { try LorcanaDiscoveryCatalog.bundledMarket.get().runtime })
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "CardScanner", category: "CatalogBootstrap")
                .error("Lorcana discovery seed rejected; existing games remain available")
            unavailable.append(LorcanaDiscoveryCatalog.descriptor)
        }
        do {
            let runtime = try measured(.yuGiOh) { () throws -> CardGameRuntime in
                // Approved delivery binds the decoded seed and keeps the eager
                // path. Otherwise a normal launch registers the bundled catalog
                // without decoding it; see `YuGiOhBundledLaunch`.
                guard YuGiOhCatalogBootstrap.requestsDelivery() else { return try YuGiOhBundledLaunch.runtime() }
                let catalog = try YuGiOhCatalog.bundled.get()
                do { return try YuGiOhCatalogBootstrap.configuredRuntime(bundled: catalog) ?? catalog.runtime }
                catch {
                    Logger(subsystem: Bundle.main.bundleIdentifier ?? "CardScanner", category: "CatalogBootstrap")
                        .error("Yu-Gi-Oh approved delivery configuration rejected; retaining bundled catalog")
                    return catalog.runtime
                }
            }
            if runtime.descriptor.capabilities.isEmpty {
                unavailable.append(YuGiOhGameRuntime.descriptor)
            } else {
                modules.append(runtime)
            }
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "CardScanner", category: "CatalogBootstrap")
                .error("Yu-Gi-Oh! seed rejected; existing games remain available")
            unavailable.append(YuGiOhGameRuntime.descriptor)
        }
#if DEBUG && LOCAL_ONLY_SIGNING
        let arguments = ProcessInfo.processInfo.arguments
        if let route = arguments.firstIndex(of: "-ui_debug_route"), arguments.indices.contains(route + 1),
           arguments[route + 1] == "CatalogUnavailable",
           let descriptor = CardGameRegistry.standard.descriptor(for: .onePiece) {
            return try! Self(runtimes: modules, unavailableGames: [descriptor])
        }
#endif
        do {
#if LOCAL_ONLY_SIGNING
            if let module = try OnePieceCatalogBootstrap.ownerRuntime() {
                modules.append(module)
                return try! Self(runtimes: modules, unavailableGames: unavailable)
            }
#endif
#if DEBUG && LOCAL_ONLY_SIGNING
            if OnePieceCatalogBootstrap.isLocalReviewLaunch {
                if let module = try OnePieceCatalogBootstrap.localReviewRuntime() { modules.append(module) }
                return try! Self(runtimes: modules)
            }
#endif
            if let module = try OnePieceCatalogBootstrap.configuredRuntime() { modules.append(module) }
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "CardScanner", category: "CatalogBootstrap")
                .error("One Piece catalog configuration or seed rejected; existing games remain available")
            if let descriptor = CardGameRegistry.standard.descriptor(for: .onePiece) {
                unavailable.append(descriptor)
            }
        }
        return try! Self(runtimes: modules, unavailableGames: unavailable)
    }

    func refreshCatalogsAtLaunch() async {
        await withTaskGroup(of: Void.self) { group in
            for source in runtimes.values.compactMap(\.activationSource) {
                group.addTask { await source.refreshAtLaunch() }
            }
        }
    }

    @MainActor
    func makeScannerModel() -> ScannerViewModel {
        let interval = PerformanceSignpost.beginInterval("Launch.scannerModel", id: PerformanceSignpost.makeID(), "")
        defer { PerformanceSignpost.endInterval("Launch.scannerModel", interval, "") }
        let scanner = CardScanner()
        scanner.useAdditionalRecognitionAdapters(recognitionAdapters)
        var reviewRecovery: UnresolvedScanStore?
#if DEBUG && LOCAL_ONLY_SIGNING
        if let directory = YuGiOhAcceptanceLaunch.enabled ? YuGiOhAcceptanceLaunch.storageDirectory : LorcanaReviewLaunch.isEnabled() ? LorcanaReviewLaunch.storageDirectory
            : OnePieceCatalogBootstrap.developerStorageDirectory(),
           let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            reviewRecovery = UnresolvedScanStore(fileURL: support
                .appendingPathComponent(directory).appendingPathComponent("Scanner/unresolved-scans.json"))
        }
#endif
        let model = ScannerViewModel(
            scanner: scanner,
            gameRegistry: registry,
            priceQuoteService: makePriceQuoteService(),
            catalog: makeCardCatalog(),
            gradedResolver: ScannedGradedResolver(gameRegistry: registry),
            catalogCoordinator: legacyBindings.pokemon,
            magicCatalogCoordinator: legacyBindings.magic,
            unresolvedScanStore: reviewRecovery ?? .shared
        )
        model.observeCatalogActivations(runtimes.values
            .filter { $0.descriptor.capabilities.contains(.scan) }.compactMap(\.activationSource))
        return model
    }

    func makeBrowseCatalog() -> BrowseCatalog {
        BrowseCatalog(catalogCoordinator: legacyBindings.pokemon,
                      magicCatalogCoordinator: legacyBindings.magic, gameRegistry: registry,
                      gameBrowseAdapters: try! .init(adapters: runtimes.values.compactMap(\.browse)),
                      priceQuoteService: makePriceQuoteService(),
                      gameActivationSources: runtimes.values.filter {
                          $0.descriptor.capabilities.contains(.browse)
                      }.compactMap(\.activationSource))
    }

    func makePriceQuoteService() -> PriceQuoteService {
        PriceQuoteService(registry: registry, adapters: pricingAdapters)
    }

    func makeCardCatalog() -> CardCatalog {
        CardCatalog(magicCatalogCoordinator: legacyBindings.magic, gameCatalogAdapters: catalogAdapters)
    }
}
