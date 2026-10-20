import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    let scanner: CardScanner
    @ObservedObject private var scannerState: CardScannerUIState
#if DEBUG
    @ObservedObject private var debugVisionOverlay: ScannerDebugVisionOverlay
#endif
    /// Observed so an iPad's preview and guide overlays re-lay-out when the window
    /// turns. On iPhone this never changes value.
    @ObservedObject private var rotationTracker: CameraRotationTracker
    /// Increments once per successful add. The band itself acknowledging the
    /// card is the cheapest possible way to say "consumed, give me the next
    /// one" without moving the user anywhere.
    var successCount: Int
    /// Increments at OCR confirmation, before catalog resolution and persistence.
    /// This is the immediate "recognized" pulse, distinct from the green add pulse.
    var recognitionCount: Int
    var onFooterGuideFrameChange: ((CGRect) -> Void)? = nil

    init(scanner: CardScanner, successCount: Int, recognitionCount: Int = 0,
         onFooterGuideFrameChange: ((CGRect) -> Void)? = nil) {
        self.scanner = scanner
        self.successCount = successCount
        self.recognitionCount = recognitionCount
        self.onFooterGuideFrameChange = onFooterGuideFrameChange
        _scannerState = ObservedObject(wrappedValue: scanner.uiState)
#if DEBUG
        _debugVisionOverlay = ObservedObject(wrappedValue: scanner.debugVisionOverlay)
#endif
        _rotationTracker = ObservedObject(wrappedValue: scanner.rotation)
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        // Keep white camera controls readable before a frame arrives and when
        // the camera is stopped in the isolated review route.
        view.backgroundColor = .black
        view.previewLayer.session = scanner.session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.rotation = scanner.rotation
        view.onFooterGuideFrameChange = onFooterGuideFrameChange
        view.subjectMode = scannerState.subjectMode
        view.slabFraming = scannerState.slabFraming
        view.footerVisionRect = scannerState.footerRegionOfInterest
        view.syncRecognitionCount(recognitionCount)
        view.syncSuccessCount(successCount)
#if DEBUG
        view.debugVisionBoxes = debugVisionOverlay.boxes
#endif
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.onFooterGuideFrameChange = onFooterGuideFrameChange
        let rotationChanged = uiView.rotation !== scanner.rotation
            || uiView.rotation?.previewAngle != scanner.rotation.previewAngle
        let subjectModeChanged = uiView.subjectMode != scannerState.subjectMode
        let slabFramingChanged = uiView.slabFraming != scannerState.slabFraming
        let footerROIChanged = uiView.footerVisionRect != scannerState.footerRegionOfInterest
#if DEBUG
        let debugBoxesChanged = uiView.debugVisionBoxes != debugVisionOverlay.boxes
#endif
        if uiView.previewLayer.session !== scanner.session {
            uiView.previewLayer.session = scanner.session
        }
        if rotationChanged { uiView.rotation = scanner.rotation }
        if subjectModeChanged { uiView.subjectMode = scannerState.subjectMode }
        if slabFramingChanged { uiView.slabFraming = scannerState.slabFraming }
        if footerROIChanged { uiView.footerVisionRect = scannerState.footerRegionOfInterest }
        uiView.syncRecognitionCount(recognitionCount)
        uiView.syncSuccessCount(successCount)
#if DEBUG
        if debugBoxesChanged { uiView.debugVisionBoxes = debugVisionOverlay.boxes }
#endif
#if DEBUG
        let needsLayout = rotationChanged || subjectModeChanged || slabFramingChanged || footerROIChanged || debugBoxesChanged
#else
        let needsLayout = rotationChanged || subjectModeChanged || slabFramingChanged || footerROIChanged
#endif
        if needsLayout {
            uiView.setNeedsLayout()
        }
    }
}

final class PreviewView: UIView {
    /// Told to the scanner so Vision reads the frame the same way up the preview
    /// shows it. Set from this view's own window during layout — a view's window is
    /// the authority on how the view is turned.
    var rotation: CameraRotationTracker?
    var subjectMode: ScanSubjectMode = .raw

    private var rotationAngle = CameraRotationTracker.defaultAngle

    /// Dims everything outside the card so the frame reads as the subject and
    /// the floating chrome sits on a calmer surface.
    private let scrimLayer = CAShapeLayer()
    /// A hairline of the full card frame; the corner brackets carry the shape.
    private let cardRegionLayer = CAShapeLayer()
    private let cardCornerLayer = CAShapeLayer()
    private let slabCardRegionLayer = CAShapeLayer()
    private let scanRegionLayer = CALayer()
    private var lastSuccessCount = 0
    private var lastRecognitionCount = 0
    var onFooterGuideFrameChange: ((CGRect) -> Void)?
    private var lastFooterGuideFrame: CGRect?
#if DEBUG
    private var debugBoxLayers: [CAShapeLayer] = []
    var debugVisionBoxes: [CGRect] = [] {
        didSet { setNeedsLayout() }
    }
#endif

    var slabFraming: GradedSlabEvidence?
    /// The band the scanner told us it is reading. Mirrored rather than derived
    /// so the read band and the debug boxes cannot drift from the real ROI.
    var footerVisionRect = CardFramingRegion.visionRect.union(
        SlabFramingRegion.footerVisionRect(for: nil)
    )

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureScanRegionLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureScanRegionLayer()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Layout is also what runs on rotation, so this is where the angle is
        // re-read rather than in a separate orientation observer.
        rotationAngle = cameraRotationAngle
        rotation?.report(rotationAngle)
        // Only on iPad. This view never wrote to the preview connection before —
        // `AVCaptureVideoPreviewLayer` applies its own orientation, and on a
        // portrait-locked phone that is already right. Writing 90 here would
        // almost certainly be the same value, and "almost certainly" is not a
        // reason to start writing to a connection that worked untouched.
        if CameraRotationTracker.tracksInterfaceRotation {
            applyRotationAngle()
        }

        // Sublayers of the preview layer animate frame/path changes implicitly over
        // ~0.25s. At roughly four OCR passes per second that smears the debug boxes
        // behind the text, which is the opposite of useful when reading positions.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // ScanRegion explicitly converts Vision's portrait/bottom-left ROI into
        // AVFoundation's unrotated-landscape/top-left metadata coordinates first.
        // The preview layer then applies orientation and aspect-fill geometry.
        let scanVisionRect = footerVisionRect
        let outerVisionRect: CGRect
        let innerVisionRect: CGRect?
        if subjectMode == .slab {
            let company = slabFraming?.company
            outerVisionRect = SlabFramingRegion.slabVisionRect(for: company)
            innerVisionRect = SlabFramingRegion.cardWindowVisionRect(for: company)
        } else {
            outerVisionRect = CardFramingRegion.cardVisionRect
            innerVisionRect = nil
        }

        scanRegionLayer.frame = previewRect(for: scanVisionRect)
        scanRegionLayer.shadowPath = Self.ringPath(
            in: scanRegionLayer.bounds,
            cornerRadius: scanRegionLayer.cornerRadius,
            lineWidth: scanRegionLayer.borderWidth
        )
        let cardRect = previewRect(for: outerVisionRect)
        let cardCornerRadius: CGFloat = innerVisionRect == nil ? 16 : 20
        cardRegionLayer.frame = cardRect
        cardRegionLayer.path = UIBezierPath(
            roundedRect: cardRegionLayer.bounds,
            cornerRadius: cardCornerRadius
        ).cgPath
        cardCornerLayer.frame = cardRect
        let cornerPath = Self.cornerBracketPath(
            in: cardCornerLayer.bounds,
            cornerRadius: cardCornerRadius,
            armLength: min(34, cardRect.width * 0.16)
        )
        cardCornerLayer.path = cornerPath
        cardCornerLayer.shadowPath = cornerPath.copy(
            strokingWithWidth: cardCornerLayer.lineWidth,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 0
        )

        let scrimPath = UIBezierPath(rect: bounds)
        if !cardRect.isEmpty {
            scrimPath.append(UIBezierPath(roundedRect: cardRect, cornerRadius: cardCornerRadius))
        }
        scrimLayer.frame = bounds
        scrimLayer.path = scrimPath.cgPath

        // Share the rendered band, including aspect-fill cropping, with the
        // SwiftUI chrome. Receipts must fit below it; controls stay above it.
        let footerFrame = convert(scanRegionLayer.frame, to: nil)
        if window != nil, !footerFrame.isEmpty, footerFrame != lastFooterGuideFrame {
            lastFooterGuideFrame = footerFrame
            DispatchQueue.main.async { [weak self] in
                self?.onFooterGuideFrameChange?(footerFrame)
            }
        }

        if let innerVisionRect {
            slabCardRegionLayer.isHidden = false
            slabCardRegionLayer.frame = previewLayer.layerRectConverted(
                fromMetadataOutputRect: CardFramingRegion.metadataRect(
                    fromVisionRect: innerVisionRect,
                    rotationAngle: rotationAngle
                )
            )
            slabCardRegionLayer.path = UIBezierPath(
                roundedRect: slabCardRegionLayer.bounds,
                cornerRadius: 10
            ).cgPath
        } else {
            slabCardRegionLayer.isHidden = true
        }

#if DEBUG
        layoutDebugVisionBoxes()
#endif
    }

    private func previewRect(for visionRect: CGRect) -> CGRect {
#if DEBUG
        // A simulator has no camera aperture. Render the same 16:9 source
        // geometry for these isolated layout fixtures only, without OCR input.
        if previewLayer.connection == nil,
           ProcessInfo.processInfo.arguments.contains(where: {
               ["WholeCardScanner", "TrustScanReceipt"].contains($0)
           }) {
            let source = CGSize(width: 9, height: 16)
            let scale = max(bounds.width / source.width, bounds.height / source.height)
            let size = CGSize(width: source.width * scale, height: source.height * scale)
            return CGRect(
                x: (bounds.width - size.width) / 2 + visionRect.minX * size.width,
                y: (bounds.height - size.height) / 2 + (1 - visionRect.maxY) * size.height,
                width: visionRect.width * size.width,
                height: visionRect.height * size.height
            )
        }
#endif
        return previewLayer.layerRectConverted(
            fromMetadataOutputRect: CardFramingRegion.metadataRect(
                fromVisionRect: visionRect, rotationAngle: rotationAngle
            )
        )
    }

    /// Flashes the band brightly and lets it settle back to green. Explicitly
    /// animated rather than relying on implicit actions, because `layoutSubviews`
    /// disables those for the debug overlay.
    func syncSuccessCount(_ count: Int) {
        guard count != lastSuccessCount else { return }
        let didReset = count < lastSuccessCount
        lastSuccessCount = count
        guard !didReset else { return }

        let border = CABasicAnimation(keyPath: "borderColor")
        border.fromValue = UIColor.white.cgColor
        border.toValue = Self.bandBorderColor
        border.duration = 0.45

        let fill = CABasicAnimation(keyPath: "backgroundColor")
        fill.fromValue = UIColor.systemGreen.withAlphaComponent(0.3).cgColor
        fill.toValue = Self.bandFillColor
        fill.duration = 0.45

        // A small exhale of the band: felt in peripheral vision while the eyes
        // are already on the next card, without moving anything that matters.
        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = [1, 1.035, 1]
        pulse.keyTimes = [0, 0.35, 1]
        pulse.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        pulse.duration = 0.4

        // The corners confirm the whole card was consumed, not just its footer.
        let corners = CABasicAnimation(keyPath: "strokeColor")
        corners.fromValue = UIColor.systemGreen.cgColor
        corners.toValue = Self.cornerColor
        corners.duration = 0.55

        scanRegionLayer.add(border, forKey: "successBorderFlash")
        scanRegionLayer.add(fill, forKey: "successFillFlash")
        // Color alone still says "added" with Reduce Motion on.
        if !UIAccessibility.isReduceMotionEnabled {
            scanRegionLayer.add(pulse, forKey: "successScalePulse")
        }
        cardCornerLayer.add(corners, forKey: "successCornerFlash")
    }

    /// A lighter pulse at recognition confirmation. The later green pulse still
    /// marks the durable add, so a slow catalog or save never gets misread as a
    /// successful collection mutation.
    func syncRecognitionCount(_ count: Int) {
        guard count != lastRecognitionCount else { return }
        let didReset = count < lastRecognitionCount
        lastRecognitionCount = count
        guard !didReset else { return }

        let border = CABasicAnimation(keyPath: "borderColor")
        border.fromValue = UIColor.systemCyan.cgColor
        border.toValue = Self.bandBorderColor
        border.duration = 0.24

        let fill = CABasicAnimation(keyPath: "backgroundColor")
        fill.fromValue = UIColor.systemCyan.withAlphaComponent(0.26).cgColor
        fill.toValue = Self.bandFillColor
        fill.duration = 0.24

        scanRegionLayer.add(border, forKey: "recognitionBorderFlash")
        scanRegionLayer.add(fill, forKey: "recognitionFillFlash")
    }

    private func applyRotationAngle() {
        guard let connection = previewLayer.connection,
              connection.isVideoRotationAngleSupported(rotationAngle) else { return }
        guard connection.videoRotationAngle != rotationAngle else { return }
        connection.videoRotationAngle = rotationAngle
    }

    private func configureScanRegionLayer() {
        // The preview is decoration: it must never take a touch, or a UIKit gesture
        // here will compete with the SwiftUI controls layered above it.
        isUserInteractionEnabled = false

        scrimLayer.fillRule = .evenOdd
        scrimLayer.fillColor = UIColor.black.withAlphaComponent(0.34).cgColor
        previewLayer.addSublayer(scrimLayer)

        cardRegionLayer.fillColor = UIColor.clear.cgColor
        cardRegionLayer.strokeColor = UIColor.white.withAlphaComponent(0.22).cgColor
        cardRegionLayer.lineWidth = 1
        previewLayer.addSublayer(cardRegionLayer)

        cardCornerLayer.fillColor = UIColor.clear.cgColor
        cardCornerLayer.strokeColor = Self.cornerColor
        cardCornerLayer.lineWidth = 3.5
        cardCornerLayer.lineCap = .round
        cardCornerLayer.lineJoin = .round
        Self.applyLegibilityShadow(to: cardCornerLayer)
        previewLayer.addSublayer(cardCornerLayer)

        slabCardRegionLayer.fillColor = UIColor.clear.cgColor
        slabCardRegionLayer.strokeColor = UIColor.white.withAlphaComponent(0.42).cgColor
        slabCardRegionLayer.lineWidth = 1
        slabCardRegionLayer.lineDashPattern = [4, 5]
        slabCardRegionLayer.lineCap = .round
        slabCardRegionLayer.isHidden = true
        previewLayer.addSublayer(slabCardRegionLayer)

        // Added last: the band is the one thing the eye should land on, and it
        // must draw above the corners where a short card brings them together.
        scanRegionLayer.backgroundColor = Self.bandFillColor
        scanRegionLayer.borderColor = Self.bandBorderColor
        scanRegionLayer.borderWidth = 1.5
        scanRegionLayer.cornerRadius = 10
        Self.applyLegibilityShadow(to: scanRegionLayer)
        previewLayer.addSublayer(scanRegionLayer)
    }

    // MARK: - Guide styling

    private static let cornerColor = UIColor.white.withAlphaComponent(0.95).cgColor
    private static let bandBorderColor = UIColor.systemGreen.withAlphaComponent(0.92).cgColor
    private static let bandFillColor = UIColor.systemGreen.withAlphaComponent(0.1).cgColor

    /// A soft dark halo keeps white and green guides readable over a white
    /// border, a bright table, or glare, without a heavier stroke.
    private static func applyLegibilityShadow(to layer: CALayer) {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 3
        layer.shadowOffset = .zero
    }

    /// The outline of a ring only, so the shadow never darkens the footer text
    /// inside the band. An explicit path also avoids offscreen shadow passes
    /// over the live preview.
    private static func ringPath(in rect: CGRect, cornerRadius: CGFloat, lineWidth: CGFloat) -> CGPath? {
        guard !rect.isEmpty else { return nil }
        return UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).cgPath.copy(
            strokingWithWidth: lineWidth,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 0
        )
    }

    /// Four rounded corner brackets that follow the frame's corner radius.
    static func cornerBracketPath(in rect: CGRect, cornerRadius: CGFloat, armLength: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard rect.width > 0, rect.height > 0 else { return path }
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        let arm = max(0, min(armLength, rect.width / 2 - radius, rect.height / 2 - radius))
        let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)

        // Each bracket runs from the vertical arm, around the corner, along the
        // horizontal arm.
        path.move(to: CGPoint(x: minX, y: minY + radius + arm))
        path.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX + radius, y: minY), radius: radius)
        path.addLine(to: CGPoint(x: minX + radius + arm, y: minY))

        path.move(to: CGPoint(x: maxX - radius - arm, y: minY))
        path.addArc(tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX, y: minY + radius), radius: radius)
        path.addLine(to: CGPoint(x: maxX, y: minY + radius + arm))

        path.move(to: CGPoint(x: maxX, y: maxY - radius - arm))
        path.addArc(tangent1End: CGPoint(x: maxX, y: maxY), tangent2End: CGPoint(x: maxX - radius, y: maxY), radius: radius)
        path.addLine(to: CGPoint(x: maxX - radius - arm, y: maxY))

        path.move(to: CGPoint(x: minX + radius + arm, y: maxY))
        path.addArc(tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX, y: maxY - radius), radius: radius)
        path.addLine(to: CGPoint(x: minX, y: maxY - radius - arm))
        return path
    }

#if DEBUG
    private func layoutDebugVisionBoxes() {
        while debugBoxLayers.count < debugVisionBoxes.count {
            let layer = CAShapeLayer()
            layer.fillColor = UIColor.clear.cgColor
            layer.strokeColor = UIColor.systemGreen.cgColor
            layer.lineWidth = 2
            previewLayer.addSublayer(layer)
            debugBoxLayers.append(layer)
        }

        for (index, layer) in debugBoxLayers.enumerated() {
            guard index < debugVisionBoxes.count else {
                layer.isHidden = true
                continue
            }

            // Vision normalizes these against the request's regionOfInterest, so map
            // back to full-frame coordinates before converting. Use the ROI published
            // by the scanner rather than re-deriving the 0.72 x 0.16 band.
            let fullFrameRect = ScanRegion.fullFrameVisionRect(
                fromObservationBoundingBox: debugVisionBoxes[index],
                in: footerVisionRect
            )
            let metadataRect = ScanRegion.metadataRect(
                fromVisionRect: fullFrameRect,
                rotationAngle: rotationAngle
            )
            let layerRect = previewLayer.layerRectConverted(fromMetadataOutputRect: metadataRect)

            layer.isHidden = false
            layer.path = UIBezierPath(rect: layerRect).cgPath
        }
    }
#endif
}
