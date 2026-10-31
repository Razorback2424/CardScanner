import Foundation

extension ResolvedCatalogCard {
    static func pokemon(_ card: TCGdexCard, setCode: String) -> Self {
        .init(legacy: .pokemon(card, setCode: setCode))
    }
}

struct PokemonGameRuntime: Sendable {
    let coordinator: PokemonCatalogCoordinator
    static let descriptor = CardGameDescriptor(
        game: .pokemon, displayName: "Pokémon", sortOrder: 0,
        capabilities: [.scan, .browse, .pricing, .sealed, .collectionWrite, .gradedPricing]
    )

    init(coordinator: PokemonCatalogCoordinator = PokemonCatalogCoordinator()) {
        self.coordinator = coordinator
    }

    var runtime: CardGameRuntime {
        .init(descriptor: Self.descriptor, variantPolicy: PokemonVariantPolicy(),
              pricing: PokemonPriceAdapter(),
              catalog: PokemonCatalogAdapter(),
              legacyCatalogBindings: .init(pokemon: coordinator))
    }
}
