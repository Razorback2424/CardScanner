import Foundation

struct PokemonVariantPolicy: GameVariantPolicy {
    var selectableVariants: [PhysicalVariant] {
        [.normal, .holo, .reverse, .pokeBall, .masterBall, .duskBall,
         .friendBall, .quickBall, .loveBall, .firstEdition]
    }
}
