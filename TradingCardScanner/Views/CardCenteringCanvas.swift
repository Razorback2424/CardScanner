import SwiftUI
import UIKit

/// A pinch hands off the displayed, bounded pan and the existing drag checkpoint.
struct CardCenteringPanHandoff {
    let pan: CGSize
    let translation: CGSize

    init(pan: CGSize, translation: CGSize, clamp: (CGSize) -> CGSize) {
        self.pan = clamp(pan)
        self.translation = translation
    }
}
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

/// The photo with both frames over it, edited by dragging edges or corners.
///
/// It opens zoomed to the card and draws the lines at a constant width at any
/// zoom, so zooming in always makes placement finer. A dragged line shows a
/// magnifier clear of the finger.
struct CardCenteringCanvas: View {
    let image: UIImage
    let measurement: CardCenteringMeasurement
    let rotationDegrees: Double
    let imageRevision: Int
    @Binding var selection: CardCenteringGuideSelection?
    /// Called once before a drag changes the guides, so it can be undone.
    let onBeginEdit: () -> Void
    let onEdit: (CardCenteringMeasurement) -> Void
    /// Moves the selected guide by one step, for VoiceOver's adjustable action.
    let onAccessibilityNudge: (Double) -> Void
    var initialZoomMultiplier: CGFloat = 1
    /// How much of the canvas the control bar covers. At card fit, the photo
    /// reframes above the bar after any active gesture ends.
    var bottomInset: CGFloat = 0
    var onFrameChange: (CGRect) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var fittedKey: FitKey?
    @State private var isAtCardFit = true
    @State private var needsRefit = false
    @State private var interaction: Interaction?
    @State private var pinch: PinchStart?
    @State private var pinchMagnification: CGFloat = 1
    /// The finger the drag gesture tracks, so a pinch can pan with it.
    @State private var dragLocation: CGPoint?
    @State private var dragTranslation: CGSize = .zero
    @State private var loupe: LoupeState?
    @State private var lastTap: TapRecord?

    private static let tapSlop: CGFloat = 4

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
                CardCenteringGuideOverlay(measurement: measurement, projection: projection, selection: selection)
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
                refitAbovePanel(size: size, base: base)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(measurement.hasObservedPaths ? "Detected curved edges" : selection.map { Self.name(of: $0.guide) } ?? "")
        .accessibilityHint(measurement.hasObservedPaths
            ? "Pinch to inspect the curved guides. Confirm after review, or choose Adjust with straight guides to edit."
            : "Select a guide to adjust it. Corners and Exact Values are in More options.")
        .modifier(CardCenteringAdjustmentAccessibility(enabled: !measurement.hasObservedPaths,
                                                       nudge: onAccessibilityNudge))
        .accessibilityActions {
            if selection != nil {
                Button("Deselect guide") { selection = nil }
            }
            ForEach(CardCenteringGuide.all, id: \.self) { guide in
                if !measurement.hasObservedPaths, measurement.segment(for: guide) != nil {
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

    private func refitAbovePanel(size: CGSize, base: CardCenteringProjection) {
        guard isAtCardFit else {
            needsRefit = false
            return
        }
        needsRefit = interaction != nil || pinch != nil
        guard !needsRefit else { return }
        let fit = cardFit(size: size, base: base)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            zoom = fit.zoom
            pan = fit.pan
        }
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
        /// Where the tracked finger was, so moving both fingers pans.
        let finger: CGPoint?
        let magnification: CGFloat
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
        let hit: CardCenteringGuideHit
        /// From the finger to the held point on the guide, in image pixels.
        let grab: CardCenteringPoint
        var session: CardCenteringGuideDragSession
    }

    private enum Interaction {
        /// Down but not yet far enough to be a drag; it may still be a tap.
        case pending(CardCenteringGuideHit?)
        case guide(GuideDrag)
        /// The pan when it began, and the drag translation at that moment.
        case pan(CGSize, from: CGSize)
        /// A pinch took over; the drag finger pans with it until it ends.
        case cancelled
    }

    private func center(_ size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func magnifyGesture(size: CGSize, base: CardCenteringProjection) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .onChanged { value in
                pinchMagnification = value.magnification
                if pinch == nil {
                    cancelGuideDrag()
                    pinch = PinchStart(zoom: zoom, pan: pan, anchor: value.startLocation,
                                       finger: dragLocation, magnification: value.magnification)
                }
                applyPinch(size: size, base: base)
            }
            .onEnded { _ in
                pinch = nil
                let handoff = CardCenteringPanHandoff(pan: pan, translation: dragTranslation) {
                    clampedPan($0, zoom: zoom, size: size, base: base)
                }
                // A finger still down carries on as a one-finger pan.
                if case .cancelled? = interaction, dragLocation != nil {
                    interaction = .pan(handoff.pan, from: handoff.translation)
                }
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                    pan = handoff.pan
                }
            }
    }

    /// Zooms about the pinch's start point and follows the tracked finger, so
    /// two fingers moving together pan the photo.
    private func applyPinch(size: CGSize, base: CardCenteringProjection) {
        guard let pinch else { return }
        let newZoom = min(
            max(pinch.zoom * pinchMagnification / max(pinch.magnification, 1e-6), minimumZoom(base, size: size)),
            maximumZoom(base)
        )
        let anchor = pinch.anchor, middle = center(size)
        let ratio = newZoom / pinch.zoom
        let moved = pinch.finger.flatMap { start in
            dragLocation.map { CGSize(width: $0.x - start.x, height: $0.y - start.y) }
        } ?? .zero
        zoom = newZoom
        pan = CGSize(
            width: anchor.x - middle.x - ratio * (anchor.x - middle.x - pinch.pan.width) + moved.width,
            height: anchor.y - middle.y - ratio * (anchor.y - middle.y - pinch.pan.height) + moved.height
        )
        isAtCardFit = false
    }

    /// Restarts the pinch from where it is, for when the tracked finger lifts
    /// or is first seen mid-pinch, so the photo does not jump.
    private func rebasePinch() {
        guard let pinch else { return }
        let moved = pinch.finger.flatMap { start in
            dragLocation.map { CGSize(width: $0.x - start.x, height: $0.y - start.y) }
        } ?? .zero
        self.pinch = PinchStart(
            zoom: zoom, pan: pan,
            anchor: CGPoint(x: pinch.anchor.x + moved.width, y: pinch.anchor.y + moved.height),
            finger: dragLocation, magnification: pinchMagnification
        )
    }

    private func dragGesture(size: CGSize, base: CardCenteringProjection) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in dragChanged(value, size: size, base: base) }
            .onEnded { value in dragEnded(value, size: size, base: base) }
    }

    private func dragChanged(_ value: DragGesture.Value, size: CGSize, base: CardCenteringProjection) {
        let isFirstSample = dragLocation == nil
        dragLocation = value.location
        dragTranslation = value.translation
        if let pinch {
            if isFirstSample || pinch.finger == nil {
                rebasePinch()
            } else {
                applyPinch(size: size, base: base)
            }
            return
        }
        let projection = projected(base, in: size)
        if interaction == nil {
            interaction = .pending(CardCenteringGuideHitTester.hit(
                at: value.startLocation, measurement: measurement, projection: projection, size: size, selection: selection
            ))
        }
        if case let .pending(hit)? = interaction {
            guard hypot(value.translation.width, value.translation.height) >= Self.tapSlop else { return }
            if let hit, let drag = beginGuideDrag(hit, at: value.startLocation, projection: projection) {
                if let lineSelection = hit.lineSelection { selection = lineSelection }
                interaction = .guide(drag)
            } else {
                interaction = .pan(pan, from: .zero)
            }
        }
        switch interaction {
        case let .guide(drag)?:
            updateGuideDrag(drag, location: value.location, projection: projection, size: size)
        case let .pan(start, from)?:
            pan = clampedPan(
                CGSize(width: start.width + value.translation.width - from.width,
                       height: start.height + value.translation.height - from.height),
                zoom: zoom, size: size, base: base
            )
            isAtCardFit = false
        default:
            break
        }
    }

    private func dragEnded(_ value: DragGesture.Value, size: CGSize, base: CardCenteringProjection) {
        if pinch != nil {
            // Keep the pinch going on the other finger without a jump.
            dragLocation = nil
            rebasePinch()
        }
        dragLocation = nil
        defer {
            interaction = nil
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { loupe = nil }
            if needsRefit { refitAbovePanel(size: size, base: base) }
        }
        switch interaction {
        case let .pending(hit)?:
            handleTap(at: value.location, hit: hit, size: size, base: base)
        case .none:
            handleTap(
                at: value.location,
                hit: CardCenteringGuideHitTester.hit(
                    at: value.location, measurement: measurement, projection: projected(base, in: size),
                    size: size, selection: selection
                ),
                size: size, base: base
            )
        default:
            break
        }
    }

    private func handleTap(
        at location: CGPoint,
        hit: CardCenteringGuideHit?,
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
        if case .corner? = hit { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) { selection = hit?.lineSelection }
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
        if case let .guide(drag)? = interaction, drag.session.lastEdit != nil {
            onEdit(drag.session.start)
        }
        // The finger that started the pinch keeps its drag going; nothing it
        // does counts until it lifts.
        interaction = .cancelled
        loupe = nil
    }

    // MARK: Guide drags

    private func beginGuideDrag(
        _ hit: CardCenteringGuideHit,
        at location: CGPoint,
        projection: CardCenteringProjection
    ) -> GuideDrag? {
        let finger = projection.image(location)
        let held: CardCenteringPoint
        switch hit {
        case let .corner(frame, corner):
            guard let quad = measurement.guideQuad(for: frame) else { return nil }
            held = quad[corner]
        case let .line(selection):
            guard let line = measurement.segment(for: selection.guide) else { return nil }
            if let end = selection.end {
                held = end == .start ? line.start : line.end
            } else {
                let dx = line.end.x - line.start.x, dy = line.end.y - line.start.y
                let lengthSquared = dx * dx + dy * dy
                guard lengthSquared > 1e-9 else { return nil }
                let along = ((finger.x - line.start.x) * dx + (finger.y - line.start.y) * dy) / lengthSquared
                held = CardCenteringPoint(x: line.start.x + dx * along, y: line.start.y + dy * along)
            }
        }
        return GuideDrag(
            hit: hit,
            grab: CardCenteringPoint(x: held.x - finger.x, y: held.y - finger.y),
            session: CardCenteringGuideDragSession(start: measurement)
        )
    }

    private func updateGuideDrag(
        _ drag: GuideDrag,
        location: CGPoint,
        projection: CardCenteringProjection,
        size: CGSize
    ) {
        let finger = projection.image(location)
        let target = CardCenteringPoint(x: finger.x + drag.grab.x, y: finger.y + drag.grab.y)
        var edited = drag.session.start
        let focus: CardCenteringPoint

        switch drag.hit {
        case let .corner(frame, corner):
            edited = CardCenteringCornerDrag.resolve(
                start: drag.session.start, previous: drag.session.lastEdit ?? drag.session.start,
                frame: frame, corner: corner, target: target
            )
            guard let quad = edited.guideQuad(for: frame) else { return }
            focus = quad[corner]
        case let .line(selection):
            let guide = selection.guide
            guard let line = edited.segment(for: guide) else { return }
            if let end = selection.end {
                let fixed = end == .start ? line.end : line.start
                let moving = end == .start ? line.start : line.end
                let reach = hypot(target.x - fixed.x, target.y - fixed.y)
                guard reach > 1 else { return }
                let length = hypot(moving.x - fixed.x, moving.y - fixed.y)
                let swung = CardCenteringPoint(
                    x: fixed.x + (target.x - fixed.x) / reach * length,
                    y: fixed.y + (target.y - fixed.y) / reach * length
                )
                edited.pivotGuide(guide, movingEnd: end, toward: swung)
                let settled = edited.segment(for: guide) ?? line
                focus = end == .start ? settled.start : settled.end
            } else {
                edited.moveGuide(guide, through: target)
                let settled = edited.segment(for: guide) ?? line
                let dx = settled.end.x - settled.start.x, dy = settled.end.y - settled.start.y
                let lengthSquared = max(dx * dx + dy * dy, 1e-9)
                let along = min(0.98, max(0.02, ((target.x - settled.start.x) * dx + (target.y - settled.start.y) * dy) / lengthSquared))
                focus = CardCenteringPoint(x: settled.start.x + dx * along, y: settled.start.y + dy * along)
            }
        }

        var updated = drag
        let edit = updated.session.accept(edited)
        if edit.changed {
            if edit.isFirstChange { onBeginEdit() }
            interaction = .guide(updated)
            onEdit(edited)
        }

        loupe = LoupeState(
            focus: focus,
            position: loupePosition(for: location, in: size),
            scale: Self.loupeScale(for: projection.scale)
        )
    }

    /// Screen points per photo pixel in the loupe: always enough to see
    /// single pixels, and at least twice the view it magnifies.
    static func loupeScale(for viewScale: CGFloat) -> CGFloat {
        max(viewScale * 2, 5)
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
}

enum CardCenteringGuideHit: Equatable {
    case line(CardCenteringGuideSelection)
    case corner(CardCenteringGuide.Frame, CardCenteringQuad.Corner)

    var lineSelection: CardCenteringGuideSelection? {
        if case let .line(selection) = self { return selection }
        return nil
    }
}

enum CardCenteringGuideHitTester {
    /// Unselected lines take a narrow band, leaving room to pan between them.
    private static let lineHitRadius: CGFloat = 14
    private static let generousHitBonus: CGFloat = 10
    private static let endHitRadius: CGFloat = 26
    private static let cornerGripHitRadius: CGFloat = 22
    private static let cornerVertexHitRadius: CGFloat = 10

    static func hit(
        at location: CGPoint,
        measurement: CardCenteringMeasurement,
        projection: CardCenteringProjection,
        size: CGSize,
        selection: CardCenteringGuideSelection?
    ) -> CardCenteringGuideHit? {
        guard !measurement.hasObservedPaths else { return nil }
        let visible = CGRect(origin: .zero, size: size)
        var closestGrip: (hit: CardCenteringGuideHit, distance: CGFloat)?
        for handle in CardCenteringCornerHandle.visibleHandles(
            measurement: measurement, projection: projection, visible: visible, selectedFrame: selection?.guide.frame
        ) {
            let gripDistance = hypot(location.x - handle.grip.x, location.y - handle.grip.y)
            let vertexDistance = hypot(location.x - handle.vertex.x, location.y - handle.vertex.y)
            let distance = vertexDistance <= Self.cornerVertexHitRadius ? min(vertexDistance, gripDistance) : gripDistance
            if distance <= Self.cornerGripHitRadius, distance < (closestGrip?.distance ?? .infinity) {
                closestGrip = (.corner(handle.frame, handle.corner), distance)
            }
        }
        if let selection,
           let handles = CardCenteringGuideHandles(
               guide: selection.guide, measurement: measurement, projection: projection, visible: visible
           ) {
            for (end, point) in handles.ends {
                let distance = hypot(location.x - point.x, location.y - point.y)
                if distance <= Self.endHitRadius, distance < (closestGrip?.distance ?? .infinity) {
                    closestGrip = (.line(CardCenteringGuideSelection(guide: selection.guide, end: end)), distance)
                }
            }
        }
        if let closestGrip { return closestGrip.hit }
        var best: (guide: CardCenteringGuide, distance: CGFloat)?
        for guide in CardCenteringGuide.all {
            guard let handles = CardCenteringGuideHandles(
                guide: guide, measurement: measurement, projection: projection, visible: visible
            ) else { continue }
            let line = Self.distance(from: location, toSegment: handles.start, handles.end)
            let distance = min(
                guide == selection?.guide ? line - Self.generousHitBonus : line,
                hypot(location.x - handles.grip.x, location.y - handles.grip.y) - Self.generousHitBonus
            )
            if distance <= Self.lineHitRadius, distance < (best?.distance ?? .infinity) {
                best = (guide, distance)
            }
        }
        return best.map { .line(CardCenteringGuideSelection(guide: $0.guide)) }
    }

    private static func distance(from point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x, dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 1e-6 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return hypot(point.x - (start.x + dx * t), point.y - (start.y + dy * t))
    }
}

enum CardCenteringCornerDrag {
    static func resolve(
        start: CardCenteringMeasurement,
        previous: CardCenteringMeasurement,
        frame: CardCenteringGuide.Frame,
        corner: CardCenteringQuad.Corner,
        target: CardCenteringPoint
    ) -> CardCenteringMeasurement {
        guard target.x.isFinite, target.y.isFinite else { return previous }
        // Clamp each axis independently so a corner can slide along the photo edge.
        let bounded = CardCenteringPoint(
            x: min(max(0, target.x), Double(start.imageWidth)),
            y: min(max(0, target.y), Double(start.imageHeight))
        )
        var edited = start
        // A fold keeps the last accepted geometry and loupe focus.
        return edited.moveCorner(corner, of: frame, to: bounded) ? edited : previous
    }
}

struct CardCenteringGuideDragSession {
    let start: CardCenteringMeasurement
    private(set) var lastEdit: CardCenteringMeasurement?

    init(start: CardCenteringMeasurement) {
        self.start = start
    }

    mutating func accept(_ edited: CardCenteringMeasurement) -> (changed: Bool, isFirstChange: Bool) {
        guard edited != (lastEdit ?? start) else { return (false, false) }
        let isFirstChange = lastEdit == nil
        lastEdit = edited
        return (true, isFirstChange)
    }
}

extension CardCenteringMeasurement {
    private static let minimumReportableInnerTiltDegrees = 0.04

    var hasReportableInnerTilt: Bool {
        !hasObservedPaths && innerEdgeTiltDegrees?.contains { abs($0) >= Self.minimumReportableInnerTiltDegrees } == true
    }

    var innerFrameIsSquare: Bool {
        innerEdgeTiltDegrees?.allSatisfy { abs($0) <= Self.innerTiltEpsilonDegrees } == true
    }
}

extension CardCenteringGuideSelection {
    init(guide: CardCenteringGuide) {
        self.init(guide: guide, end: nil)
    }
}

private struct CardCenteringCornerHandle {
    static let radius: CGFloat = 7
    let frame: CardCenteringGuide.Frame
    let corner: CardCenteringQuad.Corner
    let vertex: CGPoint
    let grip: CGPoint

    static func visibleHandles(
        measurement: CardCenteringMeasurement,
        projection: CardCenteringProjection,
        visible: CGRect,
        selectedFrame: CardCenteringGuide.Frame?
    ) -> [Self] {
        let gripBounds = visible.insetBy(dx: radius + 1, dy: radius + 1)
        guard !gripBounds.isEmpty else { return [] }
        let frames = selectedFrame.map { [$0] } ?? [.outer, .inner]
        return frames.flatMap { frame -> [Self] in
            guard let quad = measurement.guideQuad(for: frame) else { return [] }
            let points = quad.points.map(projection.screen)
            let center = CGPoint(x: points.map(\.x).reduce(0, +) / 4, y: points.map(\.y).reduce(0, +) / 4)
            return CardCenteringQuad.Corner.allCases.compactMap { corner in
                let vertex = projection.screen(quad[corner])
                guard visible.contains(vertex) else { return nil }
                // Offset red grips outward and cyan grips inward to separate close frames.
                let dx = vertex.x - center.x, dy = vertex.y - center.y
                let distance = hypot(dx, dy)
                guard distance.isFinite, distance > 0 else { return nil }
                let offset: CGFloat = frame == .outer ? 16 : -16
                let grip = CGPoint(
                    x: min(max(vertex.x + offset * dx / distance, gripBounds.minX), gripBounds.maxX),
                    y: min(max(vertex.y + offset * dy / distance, gripBounds.minY), gripBounds.maxY)
                )
                return Self(frame: frame, corner: corner, vertex: vertex, grip: grip)
            }
        }
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
              let quad = measurement.guideQuad(for: guide.frame)
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
        // Allow for the corner grip's 16 pt offset, both radii, and a 4 pt gap.
        let cornerClearance = 40 / length
        let startT = min(max(0.1, cornerClearance, interval.0), interval.1)
        let endT = max(min(0.9, 1 - cornerClearance, interval.1), interval.0)
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
private struct CardCenteringAdjustmentAccessibility: ViewModifier {
    let enabled: Bool
    let nudge: (Double) -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: nudge(1)
                case .decrement: nudge(-1)
                @unknown default: break
                }
            }
        } else {
            content
        }
    }
}

enum CardCenteringGuideRenderer {
    static func draw(
        in context: inout GraphicsContext,
        measurement: CardCenteringMeasurement,
        projection: CardCenteringProjection,
        selection: CardCenteringGuideSelection?,
        visible: CGRect,
        showsHandles: Bool
    ) {
        if measurement.hasObservedPaths {
            for (outer,color) in [(true,Color.red),(false,Color.cyan)] {
                for points in measurement.observedGuidePaths(outer: outer) {
                    var path = Path(), connected = false
                    for point in points {
                        guard let point else { connected = false; continue }
                        if connected { path.addLine(to: projection.screen(point)) }
                        else { path.move(to: projection.screen(point)); connected = true }
                    }
                    context.stroke(path,with: .color(color),lineWidth: 1)
                }
            }
            return
        }
        let frames: [(CardCenteringGuide.Frame, CardCenteringQuad?, Color)] = [
            (.outer, measurement.geometryOuterQuad, .red),
            (.inner, measurement.geometryInnerQuad, .cyan)
        ]
        // Every line is one solid stroke with no halo or glow, so its edge is
        // unambiguous: the coloured line itself is the guide.
        let dimmed = selection != nil
        for (_, quad, color) in frames {
            guard let quad else { continue }
            context.stroke(Self.path(quad, projection), with: .color(color.opacity(dimmed ? 0.6 : 1)), lineWidth: 1)
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
            context.stroke(path, with: .color(color), lineWidth: 1.5)
        }

        guard showsHandles else { return }
        for handle in CardCenteringCornerHandle.visibleHandles(
            measurement: measurement, projection: projection, visible: visible, selectedFrame: selection?.guide.frame
        ) {
            let color: Color = handle.frame == .outer ? .red : .cyan
            var stem = Path()
            stem.move(to: handle.vertex)
            stem.addLine(to: handle.grip)
            context.stroke(stem, with: .color(color), lineWidth: 1.5)
            let radius = CardCenteringCornerHandle.radius
            let grip = Path(ellipseIn: CGRect(x: handle.grip.x - radius, y: handle.grip.y - radius,
                                              width: 2 * radius, height: 2 * radius))
            context.fill(grip, with: .color(color))
            context.stroke(grip, with: .color(.white), lineWidth: 1.5)
        }
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

/// Interpolate the projection with the photo while keeping guide strokes and
/// grips a constant size in screen points.
private struct CardCenteringGuideOverlay: View, Animatable {
    let measurement: CardCenteringMeasurement
    var projection: CardCenteringProjection
    let selection: CardCenteringGuideSelection?

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(projection.scale, .init(projection.origin.x, projection.origin.y)) }
        set {
            projection.scale = newValue.first
            projection.origin = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    var body: some View {
        Canvas { context, size in
            CardCenteringGuideRenderer.draw(
                in: &context,
                measurement: measurement,
                projection: projection,
                selection: selection,
                visible: CGRect(origin: .zero, size: size),
                showsHandles: true
            )
        }
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
    /// Draws each photo pixel as a hard-edged square, for the loupe.
    var pixelated = false

    var body: some View {
        let width = CGFloat(max(measurement.imageWidth, 1)), height = CGFloat(max(measurement.imageHeight, 1))
        let photo = Image(uiImage: image).resizable()
        (pixelated ? photo.interpolation(.none) : photo)
            .frame(width: width * base.scale, height: height * base.scale)
            .rotationEffect(.degrees(rotationDegrees))
            .scaleEffect(projection.scale / base.scale)
            .position(projection.screen(CardCenteringPoint(x: Double(width) / 2, y: Double(height) / 2)))
            .accessibilityHidden(true)
    }
}

/// A magnified view of the photo around the line being dragged, centred on
/// it, so the edge stays visible under the finger. It shows photo pixels as
/// squares, so the line can be set against a single pixel.
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
                projection: projection,
                pixelated: true
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
