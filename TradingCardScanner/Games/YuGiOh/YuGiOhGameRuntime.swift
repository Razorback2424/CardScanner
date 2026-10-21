import Foundation

struct YuGiOhVariantPolicy: GameVariantPolicy {
    let selectableVariants = YuGiOhEdition.allCases.map(\.variant)
}
struct YuGiOhGameRuntime: Sendable {
    static let descriptor = CardGameDescriptor(game: .yuGiOh, displayName: "Yu-Gi-Oh!", sortOrder: 4, capabilities: [])
    let catalog: YuGiOhCatalog
    var runtime: CardGameRuntime {
        guard !catalog.printingByID.isEmpty else {
            return .init(descriptor: Self.descriptor, variantPolicy: YuGiOhVariantPolicy(), requiresLaunchActivation: false)
        }
        let adapter = YuGiOhCatalogAdapter(catalog: catalog)
        let hasSupportedChoice = catalog.printingsByCode.values.contains { family in
            let candidates = family.map(adapter.candidate)
            return family.contains { $0.explicitSelectionSupported && adapter.candidate($0).selectionEvidence(among: candidates) != .insufficient }
        }
        let capabilities: CardGameCapabilities = hasSupportedChoice
            ? [.scan, .browse, .pricing, .collectionWrite] : [.browse]
        return .init(descriptor: .init(game: .yuGiOh, displayName: "Yu-Gi-Oh!", sortOrder: 4,
                capabilities: capabilities),
            variantPolicy: YuGiOhVariantPolicy(), pricing: YuGiOhPriceAdapter(catalog: catalog),
            recognizer: YuGiOhRecognitionAdapter(catalog: catalog), catalog: YuGiOhCatalogAdapter(catalog: catalog),
            browse: YuGiOhBrowseAdapter(catalog: catalog), importer: YuGiOhImportAdapter(catalog: catalog),
            priceAuthority: YuGiOhPriceAdapter.priceAuthority(catalog), requiresLaunchActivation: false)
    }
}

#if DEBUG && LOCAL_ONLY_SIGNING
/// Fixture OCR routed through normal scanner choices, with a separate store.
enum YuGiOhAcceptanceLaunch {
    static let storageDirectory = "YuGiOhAcceptance"
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
        var id: String { rawValue }
        var lines: [RecognizedLine] {
            [.init(text: rawValue)] + (self == .limited ? [.init(text: "Limited Edition")] : [])
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
