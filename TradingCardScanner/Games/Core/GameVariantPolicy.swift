import Foundation

protocol GameVariantPolicy: Sendable {
    var selectableVariants: [PhysicalVariant] { get }
    var lockOptions: [VariantLock] { get }
    func correctionOptions(for evidence: VariantEvidence) -> [PhysicalVariant]
}

struct GameVariantLockOptions: Identifiable, Equatable, Sendable {
    let game: CardGame
    let displayName: String
    let options: [VariantLock]
    var id: CardGame { game }
}

extension GameVariantPolicy {
    func correctionOptions(for evidence: VariantEvidence) -> [PhysicalVariant] {
        VariantResolver.options(for: evidence)
    }

    var lockOptions: [VariantLock] {
        selectableVariants.map { VariantLock(finish: $0) }
    }
}
