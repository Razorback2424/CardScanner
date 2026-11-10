import Foundation

struct PokemonVariantPolicy: GameVariantPolicy {
    func correctionOptions(for evidence: VariantEvidence) -> [PhysicalVariant] {
        VariantResolver.options(for: evidence.excludingFirstEditionPseudoFinish())
    }

    var selectableVariants: [PhysicalVariant] {
        [.normal, .holo, .reverse, .pokeBall, .masterBall, .duskBall,
         .friendBall, .quickBall, .loveBall, .jumbo, .firstEdition]
    }
}
