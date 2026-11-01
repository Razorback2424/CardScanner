import SwiftUI

/// Illustrations shared by the Pro hub and the tools it opens. They are drawn,
/// not bundled, so they follow Dynamic Type spacing, both appearances and the
/// accent colour, and they borrow the foil palette of the opening mark so the
/// Pro surfaces read as part of the same app.

/// A stylised trading card: a foil border around an inner printed window.
/// `window` is each border's share of the card's width (horizontal edges) or
/// height (vertical edges), so a centering illustration can be off-centre on
/// purpose.
struct ProMiniCard: View {
    var width: CGFloat
    var window = EdgeInsets(top: 0.08, leading: 0.09, bottom: 0.08, trailing: 0.09)
    @Environment(\.colorScheme) private var colorScheme

    static func height(forWidth width: CGFloat) -> CGFloat { width * 88 / 63 }

    var body: some View {
        let height = Self.height(forWidth: width)
        let radius = width * 0.075
        let innerWidth = width * (1 - window.leading - window.trailing)
        let innerHeight = height * (1 - window.top - window.bottom)
        let bar = max(width * 0.05, 2)

        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: AppPalette.foil, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: radius * 0.5, style: .continuous)
                    .fill(.white.opacity(0.3))
                    .overlay {
                        RoundedRectangle(cornerRadius: radius * 0.5, style: .continuous)
                            .strokeBorder(.white.opacity(0.75), lineWidth: max(width * 0.008, 0.75))
                    }
                    .overlay(alignment: .top) {
                        VStack(alignment: .leading, spacing: bar * 0.9) {
                            RoundedRectangle(cornerRadius: radius * 0.35, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [AppPalette.ink.opacity(0.72), AppPalette.ink.opacity(0.42)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(alignment: .topTrailing) {
                                    Circle()
                                        .fill(.white.opacity(0.55))
                                        .frame(width: innerWidth * 0.16)
                                        .padding(innerWidth * 0.08)
                                }
                                .frame(height: innerHeight * 0.56)
                            Capsule().fill(.white.opacity(0.8)).frame(width: innerWidth * 0.62, height: bar)
                            Capsule().fill(.white.opacity(0.5)).frame(width: innerWidth * 0.4, height: bar)
                        }
                        .padding(innerWidth * 0.07)
                    }
                    .frame(width: innerWidth, height: innerHeight)
                    .offset(x: width * window.leading, y: height * window.top)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.08),
                        lineWidth: colorScheme == .dark ? 1 : 0.5
                    )
            }
            .frame(width: width, height: height)
    }
}

/// A card with its outer and inner frames traced, the way the centering tool
/// draws them. On appearance the guides drift in and settle on the edges; with
/// `isScanning` a light band sweeps the card while edges are being found.
struct CenteringGuideArt: View {
    var cardWidth: CGFloat = 112
    var isScanning = false
    var showsReadout = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSettled = false
    @State private var scanPhase = false

    /// Deliberately a little off-centre left to right, so the readout has a
    /// story to tell: 55/45 and 50/50.
    private static let window = EdgeInsets(top: 0.075, leading: 0.11, bottom: 0.075, trailing: 0.09)

    private var cardHeight: CGFloat { ProMiniCard.height(forWidth: cardWidth) }
    /// The dark accent sinks into a black background; the foil's mint keeps
    /// the guides as legible there as the accent is on light.
    private var guideColor: Color { colorScheme == .dark ? AppPalette.foil[0] : .accentColor }
    private var overhang: CGFloat { cardWidth * 0.16 }

    var body: some View {
        VStack(spacing: cardWidth * 0.12) {
            guides
            if showsReadout {
                readout
                    .opacity(isSettled && !isScanning ? 1 : 0)
                    .offset(y: isSettled && !isScanning ? 0 : 4)
            }
        }
        .onAppear {
            guard !isSettled else { return }
            if reduceMotion {
                isSettled = true
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.78).delay(0.15)) {
                    isSettled = true
                }
            }
        }
    }

    private var guides: some View {
        let width = cardWidth
        let height = cardHeight
        let o = overhang
        let window = Self.window
        let drift: CGFloat = isSettled ? 0 : width * 0.09
        let outerX = [o - drift, o + width + drift]
        let outerY = [o - drift, o + height + drift]
        let innerX = [o + width * window.leading + drift, o + width * (1 - window.trailing) - drift]
        let innerY = [o + height * window.top + drift, o + height * (1 - window.bottom) - drift]
        let fullWidth = width + o * 2
        let fullHeight = height + o * 2

        let lines = ZStack(alignment: .topLeading) {
            ForEach(Array(outerX.enumerated()), id: \.offset) { _, x in
                GuideLine(axis: .vertical)
                    .stroke(guideColor, lineWidth: 1.5)
                    .frame(width: 1.5, height: fullHeight)
                    .position(x: x, y: fullHeight / 2)
            }
            ForEach(Array(outerY.enumerated()), id: \.offset) { _, y in
                GuideLine(axis: .horizontal)
                    .stroke(guideColor, lineWidth: 1.5)
                    .frame(width: fullWidth, height: 1.5)
                    .position(x: fullWidth / 2, y: y)
            }
            ForEach(Array(innerX.enumerated()), id: \.offset) { _, x in
                GuideLine(axis: .vertical)
                    .stroke(guideColor, style: StrokeStyle(lineWidth: 1.25, dash: [4, 3]))
                    .frame(width: 1.25, height: fullHeight)
                    .position(x: x, y: fullHeight / 2)
            }
            ForEach(Array(innerY.enumerated()), id: \.offset) { _, y in
                GuideLine(axis: .horizontal)
                    .stroke(guideColor, style: StrokeStyle(lineWidth: 1.25, dash: [4, 3]))
                    .frame(width: fullWidth, height: 1.25)
                    .position(x: fullWidth / 2, y: y)
            }
        }
        .frame(width: fullWidth, height: fullHeight)
        .opacity(isSettled || reduceMotion ? 1 : 0.4)
        // Fade the guide ends so they read as measuring lines, not a box. Only
        // the lines are masked: masking the card would square off its shadow.
        .mask {
            RadialGradient(
                colors: [.black, .black, .black.opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: max(fullWidth, fullHeight) * 0.72
            )
        }

        return ZStack {
            ProMiniCard(width: width, window: window)
                .overlay { scanBand }
                .proCardShadow(colorScheme, width: width)
            lines
        }
        .frame(width: fullWidth, height: fullHeight)
    }

    @ViewBuilder
    private var scanBand: some View {
        if isScanning, !reduceMotion {
            GeometryReader { proxy in
                LinearGradient(
                    colors: [.white.opacity(0), .white.opacity(0.7), .white.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: proxy.size.height * 0.28)
                .offset(y: scanPhase ? proxy.size.height : -proxy.size.height * 0.28)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                        scanPhase = true
                    }
                }
                .onDisappear { scanPhase = false }
            }
            .clipShape(RoundedRectangle(cornerRadius: cardWidth * 0.075, style: .continuous))
            .allowsHitTesting(false)
        }
    }

    private var readout: some View {
        HStack(spacing: 6) {
            readoutChip("L/R", "55/45")
            readoutChip("T/B", "50/50")
        }
    }

    private func readoutChip(_ axis: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(axis).foregroundStyle(.secondary)
            Text(value).foregroundStyle(.primary)
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
    }
}

private struct GuideLine: Shape {
    enum Axis { case horizontal, vertical }
    let axis: Axis

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch axis {
        case .vertical:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        case .horizontal:
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        return path
    }
}

/// The listing-photo set at a glance: the full card, then a close-up of each
/// corner, numbered in upload order.
struct ListingPhotosArt: View {
    var cardWidth: CGFloat = 70
    @Environment(\.colorScheme) private var colorScheme

    private var cardHeight: CGFloat { ProMiniCard.height(forWidth: cardWidth) }
    private var loupe: CGFloat { cardWidth * 0.62 }

    var body: some View {
        let horizontal = cardWidth * 0.5 + loupe * 0.62
        let vertical = cardHeight * 0.5 - loupe * 0.18

        ZStack {
            ProMiniCard(width: cardWidth)
                .proCardShadow(colorScheme, width: cardWidth)
                .overlay(alignment: .topLeading) { orderBadge(1).offset(x: -6, y: -6) }

            cornerLoupe(.topLeading, order: 2).offset(x: -horizontal, y: -vertical)
            cornerLoupe(.topTrailing, order: 3).offset(x: horizontal, y: -vertical)
            cornerLoupe(.bottomLeading, order: 4).offset(x: -horizontal, y: vertical)
            cornerLoupe(.bottomTrailing, order: 5).offset(x: horizontal, y: vertical)
        }
        .frame(width: horizontal * 2 + loupe, height: max(cardHeight, vertical * 2 + loupe) + 12)
    }

    private func cornerLoupe(_ corner: Alignment, order: Int) -> some View {
        ProMiniCard(width: cardWidth * 2.6)
            .frame(width: loupe, height: loupe, alignment: corner)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: loupe * 0.26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: loupe * 0.26, style: .continuous)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .overlay(alignment: .topLeading) { orderBadge(order).offset(x: -5, y: -5) }
    }

    private func orderBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: 17, height: 17)
            .background(Color.accentColor, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1))
    }
}

extension View {
    /// The opening mark's card shadow: ink-tinted on light, plain depth on dark,
    /// where a tinted shadow reads as a muddy halo.
    func proCardShadow(_ colorScheme: ColorScheme, width: CGFloat) -> some View {
        shadow(
            color: colorScheme == .dark ? .black.opacity(0.6) : AppPalette.ink.opacity(0.26),
            radius: width * 0.12,
            y: width * 0.06
        )
    }
}

/// Large tappable surfaces settle back a touch when pressed, the way system
/// cards do, instead of flashing a highlight.
struct ProPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
