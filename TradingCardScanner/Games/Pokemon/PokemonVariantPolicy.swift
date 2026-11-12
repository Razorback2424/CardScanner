import Foundation

struct PokemonVariantPolicy: GameVariantPolicy {
    static func allowsAcquisition(of card: IdentifiedCard, finish: PhysicalVariant?, printRun: PokemonPrintRun?) -> Bool {
        guard card.game == .pokemon else { return true }
        if let printRun, !PokemonMasterSetDefinition.printRuns(for: card).contains(printRun) { return false }
        guard let finish else { return true }
        let evidence = printRun == nil ? card.variantEvidence : card.variantEvidence.excludingFirstEditionPseudoFinish()
        return VariantResolver.options(for: evidence).contains(finish)
    }

    func correctionOptions(for evidence: VariantEvidence) -> [PhysicalVariant] {
        VariantResolver.options(for: evidence.excludingFirstEditionPseudoFinish())
    }

    var selectableVariants: [PhysicalVariant] {
        [.normal, .holo, .reverse, .pokeBall, .masterBall, .duskBall,
         .friendBall, .quickBall, .loveBall, .jumbo, .firstEdition]
    }
}
