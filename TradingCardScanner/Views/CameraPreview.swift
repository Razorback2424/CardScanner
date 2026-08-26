import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var scanner: CardScanner
    /// Observed so an iPad's preview and guide overlays re-lay-out when the window
    /// turns. On iPhone this never changes value.
    @ObservedObject private var rotationTracker: CameraRotationTracker
    /// Increments once per successful add. The band itself acknowledging the
    /// card is the cheapest possible way to say "consumed, give me the next
    /// one" without moving the user anywhere.
    var successCount: Int

    init(scanner: CardScanner, successCount: Int) {
        self.scanner = scanner
        self.successCount = successCount
        _rotationTracker = ObservedObject(wrappedValue: scanner.rotation)
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = scanner.session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.rotation = scanner.rotation
        view.syncSuccessCount(successCount)
#if DEBUG
        view.debugVisionBoxes = scanner.debugVisionBoxes
#endif
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = scanner.session
        uiView.rotation = scanner.rotation
        uiView.syncSuccessCount(successCount)
#if DEBUG
        uiView.debugVisionBoxes = scanner.debugVisionBoxes
#endif
        uiView.setNeedsLayout()
    }
}

final class PreviewView: UIView {
    /// Told to the scanner so Vision reads the frame the same way up the preview
    /// shows it. Set from this view's own window during layout — a view's window is
    /// the authority on how the view is turned.
    var rotation: CameraRotationTracker?

    private var rotationAngle = CameraRotationTracker.defaultAngle

    private let cardRegionLayer = CAShapeLayer()
    private let scanRegionLayer = CALayer()
    private var lastSuccessCount = 0
#if DEBUG
    private var debugBoxLayers: [CAShapeLayer] = []
    var debugVisionBoxes: [CGRect] = [] {
        didSet { setNeedsLayout() }
    }
#endif

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
        scanRegionLayer.frame = previewLayer.layerRectConverted(
            fromMetadataOutputRect: CardFramingRegion.metadataRect(
                fromVisionRect: CardFramingRegion.visionRect,
                rotationAngle: rotationAngle
            )
        )
        let cardRect = previewLayer.layerRectConverted(
            fromMetadataOutputRect: CardFramingRegion.metadataRect(
                fromVisionRect: CardFramingRegion.cardVisionRect,
                rotationAngle: rotationAngle
            )
        )
        cardRegionLayer.frame = cardRect
        cardRegionLayer.path = UIBezierPath(
            roundedRect: cardRegionLayer.bounds,
            cornerRadius: 14
        ).cgPath

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
