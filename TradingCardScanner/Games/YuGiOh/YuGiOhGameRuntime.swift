import Foundation
import OSLog

struct YuGiOhVariantPolicy: GameVariantPolicy {
    let selectableVariants = YuGiOhEdition.allCases.map(\.variant)
}
struct YuGiOhGameRuntime: Sendable {
    static let descriptor = CardGameDescriptor(game: .yuGiOh, displayName: "Yu-Gi-Oh!", sortOrder: 4, capabilities: [])
    let catalog: YuGiOhCatalog
    var coordinator: YuGiOhCatalogCoordinator? = nil
    /// Capabilities already established for this exact catalog, so building
    /// the runtime does not read a lazily loaded catalog's data.
    var knownCapabilities: CardGameCapabilities? = nil
    static func capabilities(for catalog: YuGiOhCatalog) -> CardGameCapabilities {
        guard !catalog.printingByID.isEmpty else { return [] }
        let adapter = YuGiOhCatalogAdapter(catalog: catalog)
        let supported = catalog.printingsByCode.values.contains { family in
            let candidates = family.map(adapter.candidate)
            return family.contains { $0.explicitSelectionSupported && adapter.candidate($0).selectionEvidence(among: candidates) != .insufficient }
        }
        return supported ? [.scan, .browse, .pricing, .collectionWrite] : [.browse]
    }
    var runtime: CardGameRuntime {
        let capabilities = knownCapabilities ?? Self.capabilities(for: catalog)
        guard !capabilities.isEmpty else {
            return .init(descriptor: Self.descriptor, variantPolicy: YuGiOhVariantPolicy(), requiresLaunchActivation: false)
        }
        return .init(descriptor: .init(game: .yuGiOh, displayName: "Yu-Gi-Oh!", sortOrder: 4,
                capabilities: capabilities),
            variantPolicy: YuGiOhVariantPolicy(), pricing: YuGiOhPriceAdapter(catalog: catalog, coordinator: coordinator),
            recognizer: YuGiOhRecognitionAdapter(catalog: catalog), catalog: YuGiOhCatalogAdapter(catalog: catalog),
            browse: YuGiOhBrowseAdapter(catalog: catalog), importer: YuGiOhImportAdapter(catalog: catalog),
            priceAuthority: YuGiOhPriceAdapter.priceAuthority(catalog), activationSource: coordinator, requiresLaunchActivation: false)
    }
}

extension YuGiOhCatalog {
    /// Every bundled runtime shares this deferred load.
    static let bundledHandle = YuGiOhCatalog(knownGeneration: YuGiOhBundledLaunch.cachedManifest()?.generation) {
        let interval = PerformanceSignpost.beginInterval(
            "YuGiOh.catalogLoad", id: PerformanceSignpost.makeID(), "main=\(Thread.isMainThread ? 1 : 0)"
        )
        defer { PerformanceSignpost.endInterval("YuGiOh.catalogLoad", interval, "") }
        do {
            return try YuGiOhBundledLaunch.loadSeed()
        } catch {
            YuGiOhBundledLaunch.clear()
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "CardScanner", category: "CatalogBootstrap")
                .error("Yu-Gi-Oh! bundled seed rejected on deferred load; lookups are disabled for this session")
            throw error
        }
    }
    static var bundled: Result<Self, Error> { Result { try bundledHandle.loaded() } }
}

/// Per-build registration facts let warm launches defer decoding the bundle.
enum YuGiOhBundledLaunch {
    struct Manifest: Codable, Equatable {
        let buildKey: String
        let generation: String
        let capabilities: Int
    }
    static let defaultsKey = "yugioh.bundledLaunchManifest"

    static func seedURL(bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "catalog", withExtension: "json", subdirectory: "YuGiOhCatalogSeed")
    }

    static func buildKey(bundle: Bundle = .main) -> String? {
        guard let url = seedURL(bundle: bundle),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(version)|\(build)|\(size)|\(modified)"
    }

    static func cachedManifest(defaults: UserDefaults = .standard, bundle: Bundle = .main) -> Manifest? {
        guard let key = buildKey(bundle: bundle), let data = defaults.data(forKey: defaultsKey),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.buildKey == key, !manifest.generation.isEmpty, manifest.capabilities != 0 else { return nil }
        return manifest
    }

    static func store(generation: String, capabilities: CardGameCapabilities,
                      defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        guard !capabilities.isEmpty, let key = buildKey(bundle: bundle),
              let data = try? JSONEncoder().encode(Manifest(buildKey: key, generation: generation,
                                                            capabilities: capabilities.rawValue)) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    static func loadSeed(bundle: Bundle = .main) throws -> YuGiOhCatalog.Contents {
        guard let url = seedURL(bundle: bundle) else { throw YuGiOhCatalog.LoadError.missingResource }
        return try YuGiOhCatalog.Contents(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    /// The bundled-mode runtime for a normal launch. A cache hit registers the
    /// shared handle without decoding it. A miss decodes and validates the seed
    /// now, exactly as launches always did, and records the facts for the next
    /// launch of this build.
    static func runtime(defaults: UserDefaults = .standard) throws -> CardGameRuntime {
        let handle = YuGiOhCatalog.bundledHandle
        if let manifest = cachedManifest(defaults: defaults), manifest.generation == handle.generation {
            return YuGiOhGameRuntime(catalog: handle,
                knownCapabilities: CardGameCapabilities(rawValue: manifest.capabilities)).runtime
        }
        let catalog = try handle.loaded()
        let capabilities = YuGiOhGameRuntime.capabilities(for: catalog)
        store(generation: catalog.generation, capabilities: capabilities, defaults: defaults)
        return YuGiOhGameRuntime(catalog: catalog, knownCapabilities: capabilities).runtime
    }
}

#if DEBUG && LOCAL_ONLY_SIGNING
/// Fixture OCR routed through normal scanner choices, with a separate store.
enum YuGiOhAcceptanceLaunch {
    static var pricingSourceReview: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard enabled, let index = arguments.firstIndex(of: "-ui_debug_state"), arguments.indices.contains(index + 1) else { return false }
        return arguments[index + 1] == "pricing-source-review"
    }

    /// Presentation fixture only; never changes acquisition or price authority.
    static let pricingReviewRuntimes: CardGameRuntimeContainer? = {
        guard var catalog = try? YuGiOhCatalog.bundled.get() else { return nil }
        catalog.publicationRevision = 1
        return try? CardGameRuntimeContainer(runtimes: [catalog.runtime])
    }()
    static var storageDirectory: String { storageDirectory(arguments: ProcessInfo.processInfo.arguments) }
    static func storageDirectory(arguments: [String]) -> String {
        guard let route = arguments.firstIndex(of: "-ui_debug_route"), arguments.indices.contains(route + 1),
              arguments[route + 1] == "YuGiOhAcceptance",
              let state = arguments.firstIndex(of: "-ui_debug_state"), arguments.indices.contains(state + 1) else { return "YuGiOhAcceptance" }
        switch arguments[state + 1] {
        case "MP24-EN372": return "YuGiOhAutomaticEditionAcceptance"
        case "MP24-EN372-first": return "YuGiOhAutomaticFirstAcceptance"
        case "csv-import": return "YuGiOhCSVImportAcceptance"
        case "mixed-csv-source": return "YuGiOhMixedCSVSourceAcceptance"
        case "mixed-csv-import": return "YuGiOhMixedCSVImportAcceptance"
        default: return "YuGiOhAcceptance"
        }
    }
    static func recoveryFileURL(applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent(storageDirectory).appendingPathComponent("Scanner/unresolved-scans.json")
    }
    static func diagnostic(for outcome: GameRecognitionOutcome) -> String? {
        if case .nothing = outcome {
            return "Recognition diagnostic: no catalog match. No card was identified or added."
        }
        return nil
    }
    static var enabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-ui_debug_route"), args.indices.contains(index + 1) else { return false }
        return args[index + 1] == "YuGiOhAcceptance"
    }
    enum Sample: String, CaseIterable, Identifiable {
        case older = "LOB-001", modern = "RA02-EN001", limited = "IOC-SE1", unknown = "LOB-999"
        case reissue = "LOB-EN001", mixedDiscovery = "DCR-EN000", european = "MRL-E104"
        case mp24 = "MP24-EN372", mp24First = "MP24-EN372-first"
        var id: String { rawValue }
        var lines: [RecognizedLine] {
            [.init(text: self == .mp24First ? Sample.mp24.rawValue : rawValue)]
                + (self == .limited ? [.init(text: "Limited Edition")] : [])
                + (self == .mp24First ? [.init(text: "1st Edition")] : [])
        }
    }
    /// Optional deterministic fixture OCR for the existing screenshot script.
    /// No printing, edition or saved outcome is manufactured by this argument.
    static var initialSample: Sample? {
        let args = ProcessInfo.processInfo.arguments
        guard enabled, let index = args.firstIndex(of: "-ui_debug_state"), args.indices.contains(index + 1) else { return nil }
        return Sample(rawValue: args[index + 1])
    }
}
#endif
