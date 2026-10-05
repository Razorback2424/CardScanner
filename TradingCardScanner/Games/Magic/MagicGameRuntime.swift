import Foundation

extension ResolvedCatalogCard {
    static func magic(_ card: ScryfallCard) -> Self { .init(legacy: .magic(card)) }
}

struct MagicGameRuntime: Sendable {
    let coordinator: MagicCatalogCoordinator
    static let descriptor = CardGameDescriptor(
        game: .magic, displayName: "Magic", sortOrder: 1,
        capabilities: [.scan, .browse, .pricing, .sealed, .collectionWrite, .gradedPricing]
    )

    init(coordinator: MagicCatalogCoordinator = MagicCatalogCoordinator()) {
        self.coordinator = coordinator
    }

    var runtime: CardGameRuntime {
        .init(descriptor: Self.descriptor, variantPolicy: MagicVariantPolicy(),
              pricing: MagicPriceAdapter(),
              catalog: MagicCatalogAdapter(coordinator: coordinator),
              legacyCatalogBindings: .init(magic: coordinator))
    }
}
