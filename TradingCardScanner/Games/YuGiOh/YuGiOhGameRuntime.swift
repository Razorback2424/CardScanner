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
    static var enabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-ui_debug_route"), args.indices.contains(index + 1) else { return false }
        return args[index + 1] == "YuGiOhAcceptance"
    }
    enum Sample: String, CaseIterable, Identifiable {
        case older = "LOB-001", modern = "RA02-EN001", limited = "IOC-SE1", unknown = "LOB-999"
        var id: String { rawValue }
        var lines: [RecognizedLine] {
            [.init(text: rawValue)] + (self == .limited ? [.init(text: "Limited Edition")] : [])
        }
    }
}
#endif
