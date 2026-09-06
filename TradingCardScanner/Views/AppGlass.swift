import SwiftUI

/// Shared app chrome for content that floats above a changing visual surface.
///
/// The iOS 26 branch uses the system material. Older deployments retain the
/// opaque fallback so white labels remain readable over a bright card or camera
/// frame, and the app can adopt the material without raising its minimum OS.
struct AppGlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 18
    var tint: Color?
    var isCapsule = false
    var fallbackTintOpacity = 0.36

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if isCapsule {
                if let tint {
                    content.glassEffect(.regular.tint(tint), in: .capsule)
                } else {
                    content.glassEffect(.regular, in: .capsule)
                }
            } else if let tint {
                content.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
            } else {
                content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else if isCapsule {
            content
                .background(
                    tint?.opacity(fallbackTintOpacity) ?? Color.black.opacity(0.62),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
        } else {
            content
                .background(
                    tint?.opacity(fallbackTintOpacity) ?? Color.black.opacity(0.62),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                )
        }
    }
}

extension View {
    func appGlass(cornerRadius: CGFloat = 18) -> some View {
        modifier(AppGlassBackground(cornerRadius: cornerRadius, tint: nil))
    }

    func appPillGlass(
        tint: Color? = nil,
        fallbackTintOpacity: Double = 1
    ) -> some View {
        modifier(
            AppGlassBackground(
                cornerRadius: 0,
                tint: tint,
                isCapsule: true,
                fallbackTintOpacity: fallbackTintOpacity
            )
        )
    }

    /// Equal-weight option controls must not visually rank an unresolved choice.
    func appGlassOptionButton(cornerRadius: CGFloat = 13) -> some View {
        modifier(AppGlassOptionButtonModifier(cornerRadius: cornerRadius))
    }

    /// Gives mutually exclusive app surfaces a shared morph identity when the
    /// Liquid Glass API is available, while remaining a no-op on older systems.
    @ViewBuilder
    func appGlassEffectID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}

private struct AppGlassOptionButtonModifier: ViewModifier {
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content
                .buttonStyle(.plain)
                .background(
                    .white.opacity(0.16),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                )
        }
    }
}
