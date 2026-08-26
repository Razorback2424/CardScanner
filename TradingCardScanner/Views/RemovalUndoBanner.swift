import SwiftUI

/// The single presentation of "that's gone — unless you say otherwise".
///
/// Collection and Portfolio both remove cards, and both owe the same promise:
/// a removal is recoverable until Undo, Dismiss, or the next removal. Two
/// copies of this layout meant two chances for the recovery affordance to drift
/// apart, so there is one.
///
/// It reflows rather than truncates at accessibility text sizes. Truncating
/// here is not a cosmetic problem: at the largest sizes a long sealed-product
/// name pushed Undo off the edge entirely, which turns a recoverable removal
/// into a permanent one for exactly the people least able to work around it.
struct RemovalUndoBanner: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let name: String
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    title
                    HStack(spacing: 20) {
                        undoButton
                        dismissButton
                    }
                }
            } else {
                HStack(spacing: 12) {
                    title
                    Spacer(minLength: 8)
                    undoButton
                    dismissButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 10 : 0)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
    }

    private var title: some View {
        Text("Removed \(name)")
            .font(.subheadline)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var undoButton: some View {
        Button("Undo", action: onUndo)
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
            .accessibilityLabel("Undo removal of \(name)")
    }

    private var dismissButton: some View {
        Button("Dismiss", action: onDismiss)
            .font(.subheadline)
            .frame(minHeight: 44)
            .accessibilityLabel("Dismiss removal message")
    }
}
