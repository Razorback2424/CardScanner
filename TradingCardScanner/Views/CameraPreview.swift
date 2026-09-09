import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var scanner: CardScanner
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

    init(scanner: CardScanner, successCount: Int, recognitionCount: Int = 0) {
        self.scanner = scanner
        self.successCount = successCount
        self.recognitionCount = recognitionCount
#if DEBUG
        _debugVisionOverlay = ObservedObject(wrappedValue: scanner.debugVisionOverlay)
#endif
        _rotationTracker = ObservedObject(wrappedValue: scanner.rotation)
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = scanner.session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.rotation = scanner.rotation
        view.slabFraming = scanner.slabFraming
        view.slabGuideHint = scanner.slabGuideHint
        view.syncRecognitionCount(recognitionCount)
        view.syncSuccessCount(successCount)
#if DEBUG
        view.debugVisionBoxes = debugVisionOverlay.boxes
#endif
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        let rotationChanged = uiView.rotation !== scanner.rotation
            || uiView.rotation?.previewAngle != scanner.rotation.previewAngle
        let slabFramingChanged = uiView.slabFraming != scanner.slabFraming
        let slabGuideHintChanged = uiView.slabGuideHint != scanner.slabGuideHint
#if DEBUG
        let debugBoxesChanged = uiView.debugVisionBoxes != debugVisionOverlay.boxes
#endif
        uiView.previewLayer.session = scanner.session
        if rotationChanged { uiView.rotation = scanner.rotation }
        if slabFramingChanged { uiView.slabFraming = scanner.slabFraming }
        if slabGuideHintChanged { uiView.slabGuideHint = scanner.slabGuideHint }
        uiView.syncRecognitionCount(recognitionCount)
        uiView.syncSuccessCount(successCount)
#if DEBUG
        if debugBoxesChanged { uiView.debugVisionBoxes = debugVisionOverlay.boxes }
#endif
#if DEBUG
        let needsLayout = rotationChanged || slabFramingChanged || slabGuideHintChanged || debugBoxesChanged
#else
        let needsLayout = rotationChanged || slabFramingChanged || slabGuideHintChanged
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

    private var rotationAngle = CameraRotationTracker.defaultAngle

    private let cardRegionLayer = CAShapeLayer()
    private let slabCardRegionLayer = CAShapeLayer()
    private let scanRegionLayer = CALayer()
    private var lastSuccessCount = 0
    private var lastRecognitionCount = 0
#if DEBUG
    private var debugBoxLayers: [CAShapeLayer] = []
    var debugVisionBoxes: [CGRect] = [] {
        didSet { setNeedsLayout() }
    }
#endif

    var slabFraming: GradedSlabEvidence?
    var slabGuideHint: GradingCompany?

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
        let scanVisionRect: CGRect
        let outerVisionRect: CGRect
        let innerVisionRect: CGRect?
        let isProvisionalSlabGuide: Bool
        if let slabFraming {
            // Success belongs to the card footer that established the catalog
            // identity. The label outline remains part of the slab guide, but
            // the green flash must not point at a different OCR band.
            scanVisionRect = SlabFramingRegion.footerVisionRect(for: slabFraming.company)
            outerVisionRect = SlabFramingRegion.slabVisionRect(for: slabFraming.company)
            innerVisionRect = SlabFramingRegion.cardWindowVisionRect(for: slabFraming.company)
            isProvisionalSlabGuide = false
        } else if slabGuideHint != nil {
            // A company token is enough to tell the user where the slab label
            // belongs, but not enough to claim that the slab identity is known.
            // Keep this envelope generic until the confirmation window closes.
            scanVisionRect = SlabFramingRegion.footerVisionRect(for: nil)
            outerVisionRect = SlabFramingRegion.slabVisionRect(for: nil)
            innerVisionRect = SlabFramingRegion.cardWindowVisionRect(for: nil)
            isProvisionalSlabGuide = true
        } else {
            scanVisionRect = CardFramingRegion.visionRect
            outerVisionRect = CardFramingRegion.cardVisionRect
            innerVisionRect = nil
            isProvisionalSlabGuide = false
        }

        scanRegionLayer.frame = previewLayer.layerRectConverted(
            fromMetadataOutputRect: CardFramingRegion.metadataRect(
                fromVisionRect: scanVisionRect,
                rotationAngle: rotationAngle
            )
        )
        let cardRect = previewLayer.layerRectConverted(
            fromMetadataOutputRect: CardFramingRegion.metadataRect(
                fromVisionRect: outerVisionRect,
                rotationAngle: rotationAngle
            )
        )
        cardRegionLayer.frame = cardRect
        cardRegionLayer.path = UIBezierPath(
            roundedRect: cardRegionLayer.bounds,
            cornerRadius: innerVisionRect == nil ? 14 : 18
        ).cgPath
        cardRegionLayer.strokeColor = UIColor.white
            .withAlphaComponent(isProvisionalSlabGuide ? 0.42 : 0.78)
            .cgColor
        cardRegionLayer.lineDashPattern = isProvisionalSlabGuide ? [4, 8] : [8, 6]
        slabCardRegionLayer.strokeColor = UIColor.white
            .withAlphaComponent(isProvisionalSlabGuide ? 0.28 : 0.52)
            .cgColor
        scanRegionLayer.backgroundColor = UIColor.systemGreen
            .withAlphaComponent(isProvisionalSlabGuide ? 0.07 : 0.14)
            .cgColor
        scanRegionLayer.borderColor = UIColor.systemGreen
            .withAlphaComponent(isProvisionalSlabGuide ? 0.62 : 1)
            .cgColor

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
                cornerRadius: 8
            ).cgPath
        } else {
            slabCardRegionLayer.isHidden = true
        }

#if DEBUG
        layoutDebugVisionBoxes()
#endif
    }

    /// Flashes the band brightly and lets it settle back to green. Explicitly
    /// animated rather than relying on implicit actions, because `layoutSubviews`
    /// disables those for the debug overlay.
    func syncSuccessCount(_ count: Int) {
        guard count != lastSuccessCount else { return }
        let isFirstSync = lastSuccessCount == 0 && count == 0
        lastSuccessCount = count
        guard !isFirstSync else { return }

        let border = CABasicAnimation(keyPath: "borderColor")
        border.fromValue = UIColor.white.cgColor
        border.toValue = UIColor.systemGreen.cgColor
        border.duration = 0.45

        let fill = CABasicAnimation(keyPath: "backgroundColor")
        fill.fromValue = UIColor.systemGreen.withAlphaComponent(0.3).cgColor
        fill.toValue = UIColor.systemGreen.withAlphaComponent(0.14).cgColor
        fill.duration = 0.45

        scanRegionLayer.add(border, forKey: "successBorderFlash")
        scanRegionLayer.add(fill, forKey: "successFillFlash")
    }

    /// A lighter pulse at recognition confirmation. The later green pulse still
    /// marks the durable add, so a slow catalog or save never gets misread as a
    /// successful collection mutation.
    func syncRecognitionCount(_ count: Int) {
        guard count != lastRecognitionCount else { return }
        let isFirstSync = lastRecognitionCount == 0 && count == 0
        lastRecognitionCount = count
        guard !isFirstSync else { return }

        let border = CABasicAnimation(keyPath: "borderColor")
        border.fromValue = UIColor.white.cgColor
        border.toValue = UIColor.systemCyan.cgColor
        border.duration = 0.24

        let fill = CABasicAnimation(keyPath: "backgroundColor")
        fill.fromValue = UIColor.systemCyan.withAlphaComponent(0.26).cgColor
        fill.toValue = UIColor.systemGreen.withAlphaComponent(0.14).cgColor
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

        cardRegionLayer.fillColor = UIColor.clear.cgColor
        cardRegionLayer.strokeColor = UIColor.white.withAlphaComponent(0.78).cgColor
        cardRegionLayer.lineWidth = 2
        cardRegionLayer.lineDashPattern = [8, 6]
        previewLayer.addSublayer(cardRegionLayer)

        slabCardRegionLayer.fillColor = UIColor.clear.cgColor
        slabCardRegionLayer.strokeColor = UIColor.white.withAlphaComponent(0.52).cgColor
        slabCardRegionLayer.lineWidth = 1.5
        slabCardRegionLayer.lineDashPattern = [5, 5]
        slabCardRegionLayer.isHidden = true
        previewLayer.addSublayer(slabCardRegionLayer)

        scanRegionLayer.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.14).cgColor
        scanRegionLayer.borderColor = UIColor.systemGreen.cgColor
        scanRegionLayer.borderWidth = 2
        scanRegionLayer.cornerRadius = 8
        previewLayer.addSublayer(scanRegionLayer)
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
            // back to full-frame coordinates before converting. Skipping this draws a
            // box inside a 0.72 x 0.16 band at up to full-frame scale.
            let fullFrameRect = ScanRegion.fullFrameVisionRect(
                fromObservationBoundingBox: debugVisionBoxes[index],
                in: ScanRegion.activeVisionROI
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
