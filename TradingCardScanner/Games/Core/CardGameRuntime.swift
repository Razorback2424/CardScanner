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
    let legacyCatalogBindings: LegacyCatalogBindings

    init(descriptor: CardGameDescriptor, variantPolicy: any GameVariantPolicy,
         pricing: (any GamePriceAdapter)? = nil,
         recognizer: (any GameRecognitionAdapter)? = nil,
         catalog: (any GameCatalogAdapter)? = nil,
         browse: (any GameBrowseAdapter)? = nil,
         importer: (any GameImportAdapter)? = nil,
         priceAuthority: GameCatalogPriceAuthority? = nil,
         activationSource: (any GameCatalogActivationSource)? = nil,
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
    private let legacyBindings: LegacyCatalogBindings
    private let pricingAdapters: GamePriceAdapterRegistry
    private let catalogAdapters: GameCatalogAdapterRegistry
    private let recognitionAdapters: GameRecognitionRegistry

    init(runtimes: [CardGameRuntime]) throws {
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
        self.pricingAdapters = try GamePriceAdapterRegistry(adapters: runtimes.compactMap(\.pricing))
        self.catalogAdapters = try GameCatalogAdapterRegistry(adapters: runtimes.compactMap(\.catalog))
        self.recognitionAdapters = try GameRecognitionRegistry(recognizers: runtimes
            .filter { $0.descriptor.capabilities.contains(.scan) }.compactMap(\.recognizer))
        self.legacyBindings = .init(pokemon: pokemonBindings.first, magic: magicBindings.first)
        self.registry = CardGameRegistry(
            descriptors: runtimes.map(\.descriptor),
            variantPolicies: Dictionary(uniqueKeysWithValues: runtimes.map { ($0.descriptor.game, $0.variantPolicy) })
        )
    }

    func runtime(for game: CardGame) -> CardGameRuntime? { runtimes[game] }

    /// Bind once per authoritative storage session, before constructing consumers.
    @MainActor
    func bound(to container: ModelContainer,
               isCurrent: @escaping @MainActor @Sendable () -> Bool = { true }) async throws -> Self {
        guard isCurrent() else { throw PriceQuoteError.providerUnavailable }
        configureCollectionAuthority(for: container, configurePricing: false)
        var modules: [CardGameRuntime] = []
        for runtime in runtimes.values {
            let source = runtime.activationSource.map { CollectionAuthorizedActivationSource(source: $0, container: container, isCurrent: isCurrent) }
            if let source {
                guard await source.currentSnapshot() != nil else { throw PriceQuoteError.providerUnavailable }
            } else { try runtime.priceAuthority?.install(in: container) }
            let pricing: (any GamePriceAdapter)?
            if let adapter = runtime.pricing, let source {
                pricing = ActivatedGamePriceAdapter(adapter: adapter, source: source)
            } else { pricing = runtime.pricing }
            modules.append(.init(descriptor: runtime.descriptor, variantPolicy: runtime.variantPolicy,
                pricing: pricing, recognizer: runtime.recognizer, catalog: runtime.catalog, browse: runtime.browse,
                importer: runtime.importer, priceAuthority: runtime.priceAuthority, activationSource: source,
                legacyCatalogBindings: runtime.legacyCatalogBindings))
        }
        guard isCurrent() else { throw PriceQuoteError.providerUnavailable }
        let bound = try Self(runtimes: modules)
        bound.configureCollectionAuthority(for: container)
        return bound
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
                                    gameActivationSources: runtimes.values.compactMap(\.activationSource))
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

    /// Compile-time registration occurs once for the app session.
    static func appDefaults() -> Self {
        var modules = [PokemonGameRuntime().runtime, MagicGameRuntime().runtime]
        do {
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
        }
        return try! Self(runtimes: modules)
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
        let scanner = CardScanner()
        scanner.useAdditionalRecognitionAdapters(recognitionAdapters)
        var reviewRecovery: UnresolvedScanStore?
#if DEBUG && LOCAL_ONLY_SIGNING
        if OnePieceCatalogBootstrap.isLocalReviewLaunch,
           let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            reviewRecovery = UnresolvedScanStore(fileURL: support
                .appendingPathComponent("OnePieceLocalReview/Scanner/unresolved-scans.json"))
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
