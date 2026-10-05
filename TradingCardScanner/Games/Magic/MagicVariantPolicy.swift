import Foundation

struct MagicVariantPolicy: GameVariantPolicy {
    var selectableVariants: [PhysicalVariant] { [.nonfoil, .foil, .etched] }

    var lockOptions: [VariantLock] {
        selectableVariants.map { VariantLock(finish: $0) }
            + MagicTreatment.lockable.compactMap { treatment in
                guard treatment.requiredFinishes.count == 1,
                      let finish = treatment.requiredFinishes.first else { return nil }
                return VariantLock(finish: finish, treatment: treatment)
            }
    }
}
