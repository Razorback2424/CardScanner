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

    private let cardRegionLayer = CAShapeLayer()
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
    /// so the green guide and the debug boxes cannot drift from the real ROI.
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
        let cardRect = previewRect(for: outerVisionRect)
        cardRegionLayer.frame = cardRect
        cardRegionLayer.path = UIBezierPath(
            roundedRect: cardRegionLayer.bounds,
            cornerRadius: innerVisionRect == nil ? 14 : 18
        ).cgPath
        cardRegionLayer.strokeColor = UIColor.white.withAlphaComponent(0.78).cgColor
        cardRegionLayer.lineDashPattern = subjectMode == .slab ? nil : [8, 6]
        slabCardRegionLayer.strokeColor = UIColor.white.withAlphaComponent(0.52).cgColor
        slabCardRegionLayer.lineDashPattern = nil
        scanRegionLayer.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.14).cgColor
        scanRegionLayer.borderColor = UIColor.systemGreen.cgColor

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
                cornerRadius: 8
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
        let didReset = count < lastRecognitionCount
        lastRecognitionCount = count
        guard !didReset else { return }

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
