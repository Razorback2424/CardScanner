import Foundation

struct YuGiOhVariantPolicy: GameVariantPolicy {
    let selectableVariants = YuGiOhEdition.allCases.map(\.variant)
}
struct YuGiOhGameRuntime: Sendable {
    static let descriptor = CardGameDescriptor(game: .yuGiOh, displayName: "Yu-Gi-Oh!", sortOrder: 4, capabilities: [])
    let catalog: YuGiOhCatalog
    var runtime: CardGameRuntime {
        .init(descriptor: .init(game: .yuGiOh, displayName: "Yu-Gi-Oh!", sortOrder: 4,
                capabilities: [.scan, .browse, .pricing, .collectionWrite]),
            variantPolicy: YuGiOhVariantPolicy(), pricing: YuGiOhPriceAdapter(catalog: catalog),
            recognizer: YuGiOhRecognitionAdapter(catalog: catalog), catalog: YuGiOhCatalogAdapter(catalog: catalog),
            browse: YuGiOhBrowseAdapter(catalog: catalog), importer: YuGiOhImportAdapter(catalog: catalog),
            priceAuthority: YuGiOhPriceAdapter.priceAuthority(catalog), requiresLaunchActivation: false)
    }
}
