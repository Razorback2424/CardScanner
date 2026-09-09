import SwiftUI

extension Color {
    static let finishFoil = Color("FinishFoil")
    static let finishFoilHigh = Color("FinishFoilHigh")
    static let finishFoilMid = Color("FinishFoilMid")
    static let finishFoilLow = Color("FinishFoilLow")
    static let finishReverse = Color("FinishReverse")
    static let finishReverseHigh = Color("FinishReverseHigh")
    static let finishReverseMid = Color("FinishReverseMid")
    static let finishReverseLow = Color("FinishReverseLow")
    static let finishTreatment = Color("FinishTreatment")
    static let finishTreatmentRed = Color("FinishTreatmentRed")
    static let finishTreatmentYellow = Color("FinishTreatmentYellow")
    static let finishTreatmentGreen = Color("FinishTreatmentGreen")
    static let finishTreatmentTeal = Color("FinishTreatmentTeal")
    static let finishTreatmentPurple = Color("FinishTreatmentPurple")
    static let finishGraded = Color("FinishGraded")
    static let finishSealed = Color("FinishSealed")
}

/// The one status line shown beneath a collection tile's identity.
struct CollectionFinishStatus: Equatable {
    enum Kind: Equatable {
        case treatment
        case foil
        case reverse
        case flat
        case plain
    }

    let kind: Kind
    let label: String

    /// Resolve the display priority before the tile chooses its tint. Slabs
    /// and sealed products always lead with what the object is, even if stale
    /// treatment evidence happens to be attached to their exact-printing row.
    static func resolve(
        row: CollectionRow,
        showDefaultFinish: Bool = true
    ) -> Self? {
        switch row.itemKind {
        case .gradedCard, .sealedProduct:
            return Self(kind: .flat, label: row.displayKindLabel)
        case .rawCard:
            break
        }

        let evidence = row.displayedMagicTreatmentEvidence
        if let firstTreatment = evidence.displayLabels.first {
            let extraCount = evidence.displayLabels.count - 1
            let label = extraCount > 0
                ? "\(firstTreatment) +\(extraCount)"
                : firstTreatment
            return Self(kind: .treatment, label: label)
        }

        if let variant = row.variant,
           !evidence.impliesFinish(variant) {
            switch variant.id {
            case PhysicalVariant.reverse.id:
                return Self(kind: .reverse, label: variant.label)
            case PhysicalVariant.foil.id,
                 PhysicalVariant.holo.id,
                 PhysicalVariant.etched.id:
                return Self(kind: .foil, label: variant.label)
            case PhysicalVariant.normal.id,
                 PhysicalVariant.nonfoil.id:
                guard showDefaultFinish else { return nil }
                return Self(kind: .plain, label: variant.label)
            default:
                // Poke Ball, Master Ball, First Edition, and future variants
                // retain their existing finish tint as a flat status dot.
                return Self(kind: .flat, label: variant.label)
            }
        }

        guard showDefaultFinish else { return nil }
        return Self(kind: .plain, label: row.variant?.label ?? "Nonfoil")
    }
}

/// A seven-point visual key for the status row. The dot never carries
/// semantics by itself; its label remains the accessible source of truth.
struct CollectionFinishDot: View {
    enum Style {
        case treatment
        case foil
        case reverse
        case flat(Color)
        case plain
    }

    let style: Style
    var size: CGFloat = 7

    var body: some View {
        Group {
            switch style {
            case .treatment:
                AngularGradient(
                    gradient: Gradient(colors: [
                        .finishTreatmentRed,
                        .finishTreatmentYellow,
                        .finishTreatmentGreen,
                        .finishTreatmentTeal,
                        .finishTreatmentPurple,
                        .finishTreatmentRed
                    ]),
                    center: .center,
                    angle: .degrees(210)
                )
            case .foil:
                LinearGradient(
                    colors: [.finishFoilHigh, .finishFoilMid, .finishFoilLow],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .reverse:
                LinearGradient(
                    colors: [.finishReverseHigh, .finishReverseMid, .finishReverseLow],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case let .flat(tint):
                Circle().fill(tint)
            case .plain:
                Circle()
                    .strokeBorder(.secondary.opacity(0.85), lineWidth: 1)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
