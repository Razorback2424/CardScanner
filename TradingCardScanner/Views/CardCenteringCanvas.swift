import SwiftUI
import UIKit

/// Where an image pixel appears on screen: `screen = origin + scale · pixel`.
struct CardCenteringProjection: Equatable {
    var origin: CGPoint
    var scale: CGFloat

    func screen(_ point: CardCenteringPoint) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(point.x) * scale, y: origin.y + CGFloat(point.y) * scale)
    }

    func image(_ point: CGPoint) -> CardCenteringPoint {
        CardCenteringPoint(x: Double((point.x - origin.x) / scale), y: Double((point.y - origin.y) / scale))
    }
}

/// The guide line the person has picked up, and the end they are swinging
/// when they took it by an end grip.
struct CardCenteringGuideSelection: Equatable {
    var guide: CardCenteringGuide
    var end: CardCenteringGuideEnd?
}

/// The photo with both frames over it, edited by dragging the lines
/// themselves.
///
/// It opens zoomed to the card and draws the lines at a constant width at any
/// zoom, so zooming in always makes placement finer. A dragged line shows a
/// magnifier clear of the finger and settles on the nearest straight edge in
/// the photo; dragging past the edge releases it.
struct CardCenteringCanvas: View {
    let image: UIImage
    let measurement: CardCenteringMeasurement
    let rotationDegrees: Double
    let imageRevision: Int
    let lumaField: CardCenteringLumaField?
    @Binding var selection: CardCenteringGuideSelection?
    /// Called once before a drag changes the guides, so it can be undone.
    let onBeginEdit: () -> Void
    let onEdit: (CardCenteringMeasurement) -> Void
    /// Moves the selected guide by one step, for VoiceOver's adjustable action.
    let onAccessibilityNudge: (Double) -> Void
    var initialZoomMultiplier: CGFloat = 1
    /// How much of the bottom of the view the control bar covers. The card is
    /// framed in the space above it, and the view itself never resizes when
    /// the bar changes, so the photo cannot jump under a finger.
    var bottomInset: CGFloat = 0
    var onFrameChange: (CGRect) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var fittedKey: FitKey?
    @State private var isAtCardFit = true
    @State private var hasInteracted = false
    @State private var interaction: Interaction?
    @State private var pinch: PinchStart?
    @State private var loupe: LoupeState?
    @State private var lastTap: TapRecord?
    @State private var snapFeedback = 0
    @State private var squareFeedback = 0

    private static let tapSlop: CGFloat = 4
    private static let snapRadius: CGFloat = 10
    private static let lineHitRadius: CGFloat = 22
    private static let endHitRadius: CGFloat = 26

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let base = baseProjection(in: size)
            let projection = projected(base, in: size)
            let _ = onFrameChange(imageRect(projection))
            ZStack(alignment: .topLeading) {
                Color.black
                CardCenteringPhoto(
                    image: image,
                    measurement: measurement,
                    rotationDegrees: rotationDegrees,
                    base: base,
                    projection: projection
                )
                Canvas { context, canvasSize in
                    CardCenteringGuideRenderer.draw(
                        in: &context,
                        measurement: measurement,
                        projection: projection,
                        selection: selection,
                        visible: CGRect(origin: .zero, size: canvasSize),
                        showsHandles: true
                    )
                }
                .allowsHitTesting(false)

                if let loupe {
                    CardCenteringLoupe(
                        image: image,
                        measurement: measurement,
                        rotationDegrees: rotationDegrees,
                        base: base,
                        focus: loupe.focus,
                        scale: loupe.scale,
                        selection: selection
                    )
                    .position(loupe.position)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }

                if case let .guide(drag)? = interaction, drag.lastSnap != nil {
                    Label("Snapped to edge", systemImage: "scope")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.62), in: Capsule())
                        // Along the bottom, clear of the tilt readout at the top.
                        .frame(width: size.width, height: max(size.height - bottomInset - 14, 0), alignment: .bottom)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(
                SimultaneousGesture(
                    magnifyGesture(size: size, base: base),
                    dragGesture(size: size, base: base)
                )
            )
            .clipped()
            .onAppear { fitIfNeeded(size: size, base: base) }
            .onChange(of: FitKey(revision: imageRevision, size: size)) {
                fitIfNeeded(size: size, base: base)
            }
            .onChange(of: bottomInset) {
                // Frame the card again once the bar has its size, but never
                // after the person has started working.
                guard !hasInteracted, isAtCardFit else { return }
                let fit = cardFit(size: size, base: base)
                zoom = fit.zoom
                pan = fit.pan
            }
        }
        .sensoryFeedback(.selection, trigger: snapFeedback)
        .sensoryFeedback(.impact(weight: .light), trigger: squareFeedback)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(selection.map { Self.name(of: $0.guide) } ?? "")
        .accessibilityHint("Drag a line to move it. Pinch to zoom. More options has Exact Values for typed positions.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onAccessibilityNudge(1)
            case .decrement: onAccessibilityNudge(-1)
            @unknown default: break
            }
        }
        .accessibilityActions {
            ForEach(CardCenteringGuide.all, id: \.self) { guide in
                if measurement.segment(for: guide) != nil {
                    Button("Select \(Self.name(of: guide))") {
                        selection = CardCenteringGuideSelection(guide: guide)
                    }
                }
            }
        }
    }

    static func name(of guide: CardCenteringGuide) -> String {
        "\(guide.side.rawValue) \(guide.frame == .outer ? "card edge" : "inner frame")"
    }

    private var accessibilityLabel: String {
        measurement.geometryInnerQuad == nil
            ? "Card image with outer red guides; inner guide unavailable"
            : measurement.requiresManualFrameConfirmation
                ? "Card image with unconfirmed red outer and cyan inner guides"
                : "Card image with outer red guides and inner cyan guides"
    }

    // MARK: Projection

    private struct FitKey: Equatable {
        let revision: Int
        let size: CGSize
    }

    private var imageSize: CGSize {
        CGSize(width: max(measurement.imageWidth, 1), height: max(measurement.imageHeight, 1))
    }

    /// The whole photo fitted into the view: zoom 1.
    private func baseProjection(in size: CGSize) -> CardCenteringProjection {
        let scale = max(min(size.width / imageSize.width, size.height / imageSize.height), 1e-6)
        return CardCenteringProjection(
            origin: CGPoint(
                x: (size.width - imageSize.width * scale) / 2,
                y: (size.height - imageSize.height * scale) / 2
            ),
            scale: scale
        )
    }

    private func projected(
        _ base: CardCenteringProjection,
        in size: CGSize,
        zoom: CGFloat? = nil,
        pan: CGSize? = nil
    ) -> CardCenteringProjection {
        let zoom = zoom ?? self.zoom, pan = pan ?? self.pan
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return CardCenteringProjection(
            origin: CGPoint(
                x: center.x + pan.width + zoom * (base.origin.x - center.x),
                y: center.y + pan.height + zoom * (base.origin.y - center.y)
            ),
            scale: base.scale * zoom
        )
    }

    private func imageRect(_ projection: CardCenteringProjection) -> CGRect {
        CGRect(
            origin: projection.origin,
            size: CGSize(width: imageSize.width * projection.scale, height: imageSize.height * projection.scale)
        )
    }

    /// Never closer than eight screen points per photo pixel.
    private func maximumZoom(_ base: CardCenteringProjection) -> CGFloat {
        max(2, min(24, 8 / base.scale))
    }

    /// Far enough out to show the whole photo above the control bar.
    private func minimumZoom(_ base: CardCenteringProjection, size: CGSize) -> CGFloat {
        min(1, visibleHeight(size) / max(imageSize.height * base.scale, 1))
    }

    private func visibleHeight(_ size: CGSize) -> CGFloat {
        max(size.height - bottomInset, size.height * 0.4)
    }

    /// The zoom and pan that frame the red card edge with a little room for
    /// its grips.
    private func cardFit(size: CGSize, base: CardCenteringProjection) -> (zoom: CGFloat, pan: CGSize) {
        let corners = measurement.geometryOuterQuad.points.map { base.screen($0) }
        guard let minX = corners.map(\.x).min(), let maxX = corners.map(\.x).max(),
              let minY = corners.map(\.y).min(), let maxY = corners.map(\.y).max(),
              maxX - minX > 1, maxY - minY > 1,
              [minX, maxX, minY, maxY].allSatisfy(\.isFinite) else { return (1, .zero) }
        let inset: CGFloat = 0.045
        let visibleHeight = visibleHeight(size)
        let fitted = min(
            size.width * (1 - 2 * inset) / (maxX - minX),
            visibleHeight * (1 - 2 * inset) / (maxY - minY)
        )
        let zoom = min(max(fitted * initialZoomMultiplier, minimumZoom(base, size: size)), maximumZoom(base))
        // Centre the card in the visible space: screen = c + pan + zoom·(b − c).
        let middle = center(size)
        let target = CGPoint(x: size.width / 2, y: visibleHeight / 2)
        let pan = CGSize(
            width: target.x - middle.x - zoom * ((minX + maxX) / 2 - middle.x),
            height: target.y - middle.y - zoom * ((minY + maxY) / 2 - middle.y)
        )
        return (zoom, clampedPan(pan, zoom: zoom, size: size, base: base))
    }

    private func fitIfNeeded(size: CGSize, base: CardCenteringProjection) {
        guard size.width > 1, size.height > 1 else { return }
        let key = FitKey(revision: imageRevision, size: size)
        guard key != fittedKey else { return }
        let isNewImage = fittedKey?.revision != imageRevision
        fittedKey = key
        guard isNewImage || isAtCardFit else {
            pan = clampedPan(pan, zoom: zoom, size: size, base: base)
            return
        }
        let fit = cardFit(size: size, base: base)
        zoom = fit.zoom
        pan = fit.pan
        isAtCardFit = true
    }

    /// Keeps the photo in view: centred in the space above the bar along any
    /// axis it does not fill, and covering at least a quarter of it otherwise.
    private func clampedPan(_ pan: CGSize, zoom: CGFloat, size: CGSize, base: CardCenteringProjection) -> CGSize {
        let rect = imageRect(projected(base, in: size, zoom: zoom, pan: pan))
        let height = visibleHeight(size)
        var result = pan
        if rect.width <= size.width + 0.5 {
            result.width += size.width / 2 - rect.midX
        } else {
            if rect.maxX < size.width * 0.25 { result.width += size.width * 0.25 - rect.maxX }
            if rect.minX > size.width * 0.75 { result.width -= rect.minX - size.width * 0.75 }
        }
        if rect.height <= height + 0.5 {
            result.height += height / 2 - rect.midY
        } else {
            if rect.maxY < height * 0.25 { result.height += height * 0.25 - rect.maxY }
            if rect.minY > height * 0.75 { result.height -= rect.minY - height * 0.75 }
        }
        return result
    }

    // MARK: Gestures

    private struct PinchStart {
        let zoom: CGFloat
        let pan: CGSize
        let anchor: CGPoint
    }

    private struct TapRecord {
        let time: Date
        let location: CGPoint
    }

    private struct LoupeState {
        let focus: CardCenteringPoint
        let position: CGPoint
        let scale: CGFloat
    }

    private struct GuideDrag {
        let selection: CardCenteringGuideSelection
        let startMeasurement: CardCenteringMeasurement
        /// From the finger to the point it holds, in image pixels: a point on
        /// the line for a slide, the swinging end for a pivot.
        let grab: CardCenteringPoint
        var lastSnap: CardCenteringPoint?
        var isSquare: Bool
    }

    private enum Interaction {
        /// Down but not yet far enough to be a drag; it may still be a tap.
        case pending(CardCenteringGuideSelection?)
        case guide(GuideDrag)
        case pan(CGSize)
        /// A pinch took over; the rest of this drag is ignored.
        case cancelled
    }

    private func center(_ size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func magnifyGesture(size: CGSize, base: CardCenteringProjection) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .onChanged { value in
                if pinch == nil {
                    hasInteracted = true
                    cancelGuideDrag()
                    pinch = PinchStart(zoom: zoom, pan: pan, anchor: value.startLocation)
                }
                guard let pinch else { return }
                let newZoom = min(max(pinch.zoom * value.magnification, minimumZoom(base, size: size)), maximumZoom(base))
                let anchor = pinch.anchor, middle = center(size)
                let ratio = newZoom / pinch.zoom
                zoom = newZoom
                pan = CGSize(
                    width: anchor.x - middle.x - ratio * (anchor.x - middle.x - pinch.pan.width),
                    height: anchor.y - middle.y - ratio * (anchor.y - middle.y - pinch.pan.height)
                )
                isAtCardFit = false
            }
            .onEnded { _ in
                pinch = nil
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                    pan = clampedPan(pan, zoom: zoom, size: size, base: base)
                }
            }
    }

    private func dragGesture(size: CGSize, base: CardCenteringProjection) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in dragChanged(value, size: size, base: base) }
            .onEnded { value in dragEnded(value, size: size, base: base) }
    }

    private func dragChanged(_ value: DragGesture.Value, size: CGSize, base: CardCenteringProjection) {
        guard pinch == nil else { return }
        let projection = projected(base, in: size)
        if interaction == nil {
            hasInteracted = true
            interaction = .pending(hitTest(value.startLocation, projection: projection, size: size))
        }
        if case let .pending(hit)? = interaction {
            guard hypot(value.translation.width, value.translation.height) >= Self.tapSlop else { return }
            if let hit, let drag = beginGuideDrag(hit, at: value.startLocation, projection: projection) {
                onBeginEdit()
                selection = hit
                interaction = .guide(drag)
            } else {
                interaction = .pan(pan)
            }
        }
        switch interaction {
        case var .guide(drag)?:
            updateGuideDrag(&drag, location: value.location, projection: projection, size: size)
            interaction = .guide(drag)
        case let .pan(start)?:
            pan = clampedPan(
                CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height),
                zoom: zoom, size: size, base: base
            )
            isAtCardFit = false
        default:
            break
        }
    }

    private func dragEnded(_ value: DragGesture.Value, size: CGSize, base: CardCenteringProjection) {
        defer {
            interaction = nil
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { loupe = nil }
        }
        switch interaction {
        case let .pending(hit)?:
            handleTap(at: value.location, hit: hit, size: size, base: base)
        case .none:
            handleTap(
                at: value.location,
                hit: hitTest(value.location, projection: projected(base, in: size), size: size),
                size: size, base: base
            )
        default:
            break
        }
    }

    private func handleTap(
        at location: CGPoint,
        hit: CardCenteringGuideSelection?,
        size: CGSize,
        base: CardCenteringProjection
    ) {
        let now = Date()
        if let lastTap, now.timeIntervalSince(lastTap.time) < 0.32,
           hypot(location.x - lastTap.location.x, location.y - lastTap.location.y) < 30 {
            self.lastTap = nil
            toggleZoom(at: location, size: size, base: base)
            return
        }
        lastTap = TapRecord(time: now, location: location)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) { selection = hit }
    }

    /// Double-tap: in to two and a half times the card at the tap, or back to
    /// the whole card.
    private func toggleZoom(at location: CGPoint, size: CGSize, base: CardCenteringProjection) {
        let fit = cardFit(size: size, base: base)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
            if zoom > fit.zoom * 1.2 {
                zoom = fit.zoom
                pan = fit.pan
                isAtCardFit = true
            } else {
                let target = min(maximumZoom(base), fit.zoom * 2.5)
                let middle = center(size), ratio = target / zoom
                let zoomed = CGSize(
                    width: location.x - middle.x - ratio * (location.x - middle.x - pan.width),
                    height: location.y - middle.y - ratio * (location.y - middle.y - pan.height)
                )
                zoom = target
                pan = clampedPan(zoomed, zoom: target, size: size, base: base)
                isAtCardFit = false
            }
        }
    }

    private func cancelGuideDrag() {
        if case let .guide(drag)? = interaction {
            onEdit(drag.startMeasurement)
        }
        // The finger that started the pinch keeps its drag going; nothing it
        // does counts until it lifts.
        interaction = .cancelled
        loupe = nil
    }

    // MARK: Guide drags

    private func beginGuideDrag(
        _ hit: CardCenteringGuideSelection,
        at location: CGPoint,
        projection: CardCenteringProjection
    ) -> GuideDrag? {
        guard let line = measurement.segment(for: hit.guide) else { return nil }
        let finger = projection.image(location)
        let held: CardCenteringPoint
        if let end = hit.end {
            held = end == .start ? line.start : line.end
        } else {
            let dx = line.end.x - line.start.x, dy = line.end.y - line.start.y
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared > 1e-9 else { return nil }
            let along = ((finger.x - line.start.x) * dx + (finger.y - line.start.y) * dy) / lengthSquared
            held = CardCenteringPoint(x: line.start.x + dx * along, y: line.start.y + dy * along)
        }
        return GuideDrag(
            selection: hit,
            startMeasurement: measurement,
            grab: CardCenteringPoint(x: held.x - finger.x, y: held.y - finger.y),
            lastSnap: nil,
            isSquare: abs(measurement.innerTiltDegrees ?? 0) < CardCenteringMeasurement.innerTiltDetentDegrees
        )
    }

    private func updateGuideDrag(
        _ drag: inout GuideDrag,
        location: CGPoint,
        projection: CardCenteringProjection,
        size: CGSize
    ) {
        let finger = projection.image(location)
        let target = CardCenteringPoint(x: finger.x + drag.grab.x, y: finger.y + drag.grab.y)
        let guide = drag.selection.guide
        guard let line = drag.startMeasurement.segment(for: guide) else { return }
        let radius = Double(Self.snapRadius / projection.scale)
        var edited = drag.startMeasurement
        var snapped: CardCenteringPoint?
        let focus: CardCenteringPoint

        if let end = drag.selection.end {
            let fixed = end == .start ? line.end : line.start
            let moving = end == .start ? line.start : line.end
            let reach = hypot(target.x - fixed.x, target.y - fixed.y)
            guard reach > 1 else { return }
            let length = hypot(moving.x - fixed.x, moving.y - fixed.y)
            var swung = CardCenteringPoint(
                x: fixed.x + (target.x - fixed.x) / reach * length,
                y: fixed.y + (target.y - fixed.y) / reach * length
            )
            if let snap = snap(start: fixed, end: swung, pivots: true, radius: radius) {
                let normal = Self.normal(from: fixed, to: swung)
                swung = CardCenteringPoint(x: swung.x + normal.x * snap.offset, y: swung.y + normal.y * snap.offset)
                snapped = swung
            }
            edited.pivotGuide(guide, movingEnd: end, toward: swung)
            if guide.frame == .inner {
                let isSquare = abs(edited.innerTiltDegrees ?? 0) < CardCenteringMeasurement.innerTiltDetentDegrees
                if isSquare {
                    edited.squareInnerFrameToCardEdge()
                    if !drag.isSquare { squareFeedback &+= 1 }
                }
                drag.isSquare = isSquare
            }
            let settled = edited.segment(for: guide) ?? line
            focus = end == .start ? settled.start : settled.end
        } else {
            let normal = Self.normal(from: line.start, to: line.end)
            let offset = (target.x - line.start.x) * normal.x + (target.y - line.start.y) * normal.y
            var point = target
            if let snap = snap(
                start: CardCenteringPoint(x: line.start.x + normal.x * offset, y: line.start.y + normal.y * offset),
                end: CardCenteringPoint(x: line.end.x + normal.x * offset, y: line.end.y + normal.y * offset),
                pivots: false,
                radius: radius
            ) {
                point = CardCenteringPoint(x: target.x + normal.x * snap.offset, y: target.y + normal.y * snap.offset)
                snapped = point
            }
            edited.moveGuide(guide, through: point)
            let settled = edited.segment(for: guide) ?? line
            let dx = settled.end.x - settled.start.x, dy = settled.end.y - settled.start.y
            let lengthSquared = max(dx * dx + dy * dy, 1e-9)
            let along = min(0.98, max(0.02, ((target.x - settled.start.x) * dx + (target.y - settled.start.y) * dy) / lengthSquared))
            focus = CardCenteringPoint(x: settled.start.x + dx * along, y: settled.start.y + dy * along)
        }

        onEdit(edited)
        if let snapped {
            let moved = drag.lastSnap.map { hypot($0.x - snapped.x, $0.y - snapped.y) * Double(projection.scale) } ?? .infinity
            if moved > 2 { snapFeedback &+= 1 }
        }
        drag.lastSnap = snapped
        loupe = LoupeState(
            focus: focus,
            position: loupePosition(for: location, in: size),
            scale: min(projection.scale * 3, max(projection.scale * 1.5, 6))
        )
    }

    private func snap(
        start: CardCenteringPoint,
        end: CardCenteringPoint,
        pivots: Bool,
        radius: Double
    ) -> CardCenteringEdgeSnapper.Snap? {
        guard let lumaField else { return nil }
        return CardCenteringEdgeSnapper.snap(
            start: start,
            end: end,
            pivotsOnStart: pivots,
            radius: radius,
            field: lumaField,
            photoRotationDegrees: rotationDegrees,
            imageSize: CardCenteringSize(width: Double(measurement.imageWidth), height: Double(measurement.imageHeight))
        )
    }

    private static func normal(from start: CardCenteringPoint, to end: CardCenteringPoint) -> CardCenteringPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = max(hypot(dx, dy), 1e-9)
        return CardCenteringPoint(x: -dy / length, y: dx / length)
    }

    /// Above the finger, or below it near the top, and never off the side.
    private func loupePosition(for finger: CGPoint, in size: CGSize) -> CGPoint {
        let radius = CardCenteringLoupe.diameter / 2
        let lift = radius + 52
        let y = finger.y - lift >= radius + 8 ? finger.y - lift : finger.y + lift
        return CGPoint(
            x: min(max(finger.x, radius + 8), max(radius + 8, size.width - radius - 8)),
            y: min(y, max(radius + 8, size.height - bottomInset - radius - 8))
        )
    }

    // MARK: Hit testing

    private func hitTest(
        _ location: CGPoint,
        projection: CardCenteringProjection,
        size: CGSize
    ) -> CardCenteringGuideSelection? {
        let visible = CGRect(origin: .zero, size: size)
        if let selection,
           let handles = CardCenteringGuideHandles(
               guide: selection.guide, measurement: measurement, projection: projection, visible: visible
           ) {
            for (end, point) in handles.ends
            where hypot(location.x - point.x, location.y - point.y) <= Self.endHitRadius {
                return CardCenteringGuideSelection(guide: selection.guide, end: end)
            }
        }
        var best: (guide: CardCenteringGuide, distance: CGFloat)?
        for guide in CardCenteringGuide.all {
            guard let handles = CardCenteringGuideHandles(
                guide: guide, measurement: measurement, projection: projection, visible: visible
            ) else { continue }
            var distance = min(
                Self.distance(from: location, toSegment: handles.start, handles.end),
                hypot(location.x - handles.grip.x, location.y - handles.grip.y) - 6
            )
            if guide == selection?.guide { distance -= 4 }
            if distance <= Self.lineHitRadius, distance < (best?.distance ?? .infinity) {
                best = (guide, distance)
            }
        }
        return best.map { CardCenteringGuideSelection(guide: $0.guide) }
    }

    private static func distance(from point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x, dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 1e-6 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return hypot(point.x - (start.x + dx * t), point.y - (start.y + dy * t))
    }
}

extension CardCenteringMeasurement {
    /// Within this tilt the inner frame snaps square to the card edge, and no
    /// tilt is reported.
    static let innerTiltDetentDegrees = 0.04

    var hasReportableInnerTilt: Bool {
        abs(innerTiltDegrees ?? 0) >= Self.innerTiltDetentDegrees
    }
}

extension CardCenteringGuideSelection {
    init(guide: CardCenteringGuide) {
        self.init(guide: guide, end: nil)
    }
}

/// Where one guide's line and grips sit on screen. Grips follow the visible
/// part of the line, so they stay reachable however far the photo is zoomed.
struct CardCenteringGuideHandles {
    let start: CGPoint
    let end: CGPoint
    /// The drag grip: outside the red line, inside the cyan one, so a finger
    /// can take either even where the two lines run close together.
    let grip: CGPoint
    let angle: CGFloat
    /// The end grips for swinging the line, where they fit.
    let ends: [(CardCenteringGuideEnd, CGPoint)]

    init?(
        guide: CardCenteringGuide,
        measurement: CardCenteringMeasurement,
        projection: CardCenteringProjection,
        visible: CGRect
    ) {
        guard let line = measurement.segment(for: guide),
              let quad = guide.frame == .outer ? measurement.geometryOuterQuad : measurement.geometryInnerQuad
        else { return nil }
        let start = projection.screen(line.start), end = projection.screen(line.end)
        guard [start.x, start.y, end.x, end.y].allSatisfy(\.isFinite) else { return nil }
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 1, let interval = Self.visibleInterval(start, end, in: visible.insetBy(dx: 18, dy: 18)) else {
            return nil
        }
        func point(_ t: CGFloat) -> CGPoint {
            CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
        }
        let corners = quad.points.map { projection.screen($0) }
        let middle = CGPoint(x: corners.map(\.x).reduce(0, +) / 4, y: corners.map(\.y).reduce(0, +) / 4)
        var outward = CGPoint(x: -(end.y - start.y) / length, y: (end.x - start.x) / length)
        let mid = point((interval.0 + interval.1) / 2)
        if outward.x * (mid.x - middle.x) + outward.y * (mid.y - middle.y) < 0 {
            outward = CGPoint(x: -outward.x, y: -outward.y)
        }
        let offset: CGFloat = guide.frame == .outer ? 11 : -11
        self.start = start
        self.end = end
        self.grip = CGPoint(x: mid.x + outward.x * offset, y: mid.y + outward.y * offset)
        self.angle = atan2(end.y - start.y, end.x - start.x)
        let startT = min(max(0.1, interval.0), interval.1)
        let endT = max(min(0.9, interval.1), interval.0)
        self.ends = (endT - startT) * length >= 90
            ? [(.start, point(startT)), (.end, point(endT))]
            : []
    }

    /// The part of the segment inside `rect`, as fractions along it.
    private static func visibleInterval(_ start: CGPoint, _ end: CGPoint, in rect: CGRect) -> (CGFloat, CGFloat)? {
        var lower: CGFloat = 0, upper: CGFloat = 1
        let dx = end.x - start.x, dy = end.y - start.y
        for (p, q) in [(-dx, start.x - rect.minX), (dx, rect.maxX - start.x),
                       (-dy, start.y - rect.minY), (dy, rect.maxY - start.y)] {
            if abs(p) < 1e-9 {
                if q < 0 { return nil }
                continue
            }
            let r = q / p
            if p < 0 { lower = max(lower, r) } else { upper = min(upper, r) }
            if lower > upper { return nil }
        }
        return (lower, upper)
    }
}

/// Draws both frames, the selected line and its grips in screen space, so the
/// lines stay hairline-thin at any zoom.
enum CardCenteringGuideRenderer {
    static func draw(
        in context: inout GraphicsContext,
        measurement: CardCenteringMeasurement,
        projection: CardCenteringProjection,
        selection: CardCenteringGuideSelection?,
        visible: CGRect,
        showsHandles: Bool
    ) {
        let frames: [(CardCenteringGuide.Frame, CardCenteringQuad?, Color)] = [
            (.outer, measurement.geometryOuterQuad, .red),
            (.inner, measurement.geometryInnerQuad, .cyan)
        ]
        let dimmed = selection != nil
        for (_, quad, color) in frames {
            guard let quad else { continue }
            let path = Self.path(quad, projection)
            context.stroke(path, with: .color(.black.opacity(0.45)), lineWidth: 3.5)
            context.stroke(path, with: .color(color.opacity(dimmed ? 0.7 : 1)), lineWidth: 1.5)
        }

        if let selection, let line = measurement.segment(for: selection.guide) {
            let color: Color = selection.guide.frame == .outer ? .red : .cyan
            var path = Path()
            path.move(to: projection.screen(line.start))
            path.addLine(to: projection.screen(line.end))
            if selection.guide.frame == .inner, measurement.hasReportableInnerTilt {
                var square = measurement
                square.squareInnerFrameToCardEdge()
                if let ghost = square.segment(for: selection.guide) {
                    var dashed = Path()
                    dashed.move(to: projection.screen(ghost.start))
                    dashed.addLine(to: projection.screen(ghost.end))
                    context.stroke(dashed, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            context.stroke(path, with: .color(color.opacity(0.35)), lineWidth: 10)
            context.stroke(path, with: .color(.black.opacity(0.5)), lineWidth: 4.5)
            context.stroke(path, with: .color(color), lineWidth: 2.5)
        }

        guard showsHandles else { return }
        for guide in CardCenteringGuide.all {
            guard let handles = CardCenteringGuideHandles(
                guide: guide, measurement: measurement, projection: projection, visible: visible
            ) else { continue }
            let isSelected = guide == selection?.guide
            let color: Color = guide.frame == .outer ? .red : .cyan
            let size = isSelected ? CGSize(width: 32, height: 8) : CGSize(width: 24, height: 6)
            let grip = Path(
                roundedRect: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height),
                cornerRadius: size.height / 2
            ).applying(
                CGAffineTransform(rotationAngle: handles.angle)
                    .concatenating(CGAffineTransform(translationX: handles.grip.x, y: handles.grip.y))
            )
            context.fill(grip, with: .color(color.opacity(dimmed && !isSelected ? 0.7 : 1)))
            context.stroke(grip, with: .color(.white), lineWidth: 1.5)

            guard isSelected, let selection else { continue }
            for (end, point) in handles.ends {
                let isActive = selection.end == end
                let radius: CGFloat = isActive ? 13 : 11
                let circle = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius))
                context.fill(circle, with: .color(color))
                context.stroke(circle, with: .color(.white), lineWidth: isActive ? 2.5 : 2)
                var glyph = context.resolve(Image(systemName: "arrow.clockwise"))
                glyph.shading = .color(.white)
                context.draw(glyph, in: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
            }
        }
    }

    private static func path(_ quad: CardCenteringQuad, _ projection: CardCenteringProjection) -> Path {
        let points = quad.points.map { projection.screen($0) }
        var path = Path()
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }), let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}

/// The photo placed by a projection, turned by the person's straightening
/// rotation about its centre.
private struct CardCenteringPhoto: View {
    let image: UIImage
    let measurement: CardCenteringMeasurement
    let rotationDegrees: Double
    let base: CardCenteringProjection
    let projection: CardCenteringProjection

    var body: some View {
        let width = CGFloat(max(measurement.imageWidth, 1)), height = CGFloat(max(measurement.imageHeight, 1))
        Image(uiImage: image)
            .resizable()
            .frame(width: width * base.scale, height: height * base.scale)
            .rotationEffect(.degrees(rotationDegrees))
            .scaleEffect(projection.scale / base.scale)
            .position(projection.screen(CardCenteringPoint(x: Double(width) / 2, y: Double(height) / 2)))
            .accessibilityHidden(true)
    }
}

/// A magnified view of the photo around the line being dragged, centred on
/// it, so the edge stays visible under the finger.
private struct CardCenteringLoupe: View {
    static let diameter: CGFloat = 128

    let image: UIImage
    let measurement: CardCenteringMeasurement
    let rotationDegrees: Double
    let base: CardCenteringProjection
    let focus: CardCenteringPoint
    let scale: CGFloat
    let selection: CardCenteringGuideSelection?

    var body: some View {
        let diameter = Self.diameter
        let projection = CardCenteringProjection(
            origin: CGPoint(x: diameter / 2 - CGFloat(focus.x) * scale, y: diameter / 2 - CGFloat(focus.y) * scale),
            scale: scale
        )
        ZStack(alignment: .topLeading) {
            Color.black
            CardCenteringPhoto(
                image: image,
                measurement: measurement,
                rotationDegrees: rotationDegrees,
                base: base,
                projection: projection
            )
            Canvas { context, size in
                CardCenteringGuideRenderer.draw(
                    in: &context,
                    measurement: measurement,
                    projection: projection,
                    selection: selection,
                    visible: CGRect(origin: .zero, size: size),
                    showsHandles: false
                )
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .accessibilityHidden(true)
    }
}
