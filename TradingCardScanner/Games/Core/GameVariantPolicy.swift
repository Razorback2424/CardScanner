import Foundation

protocol GameVariantPolicy: Sendable {
    var selectableVariants: [PhysicalVariant] { get }
    var lockOptions: [VariantLock] { get }
}

struct GameVariantLockOptions: Identifiable, Equatable, Sendable {
    let game: CardGame
    let displayName: String
    let options: [VariantLock]
    var id: CardGame { game }
}

extension GameVariantPolicy {
    var lockOptions: [VariantLock] {
        selectableVariants.map { VariantLock(finish: $0) }
    }
}
