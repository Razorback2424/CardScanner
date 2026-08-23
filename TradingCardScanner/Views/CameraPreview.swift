import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var scanner: CardScanner

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = scanner.session
        view.previewLayer.videoGravity = .resizeAspectFill
#if DEBUG
        view.debugVisionBoxes = scanner.debugVisionBoxes
#endif
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = scanner.session
#if DEBUG
        uiView.debugVisionBoxes = scanner.debugVisionBoxes
#endif
        uiView.setNeedsLayout()
    }
}

final class PreviewView: UIView {
    private let scanRegionLayer = CALayer()
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
            fromMetadataOutputRect: ScanRegion.metadataRect
        )

#if DEBUG
        layoutDebugVisionBoxes()
#endif
    }

    private func configureScanRegionLayer() {
        // The preview is decoration: it must never take a touch, or a UIKit gesture
        // here will compete with the SwiftUI controls layered above it.
        isUserInteractionEnabled = false

        scanRegionLayer.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.14).cgColor
        scanRegionLayer.borderColor = UIColor.systemYellow.cgColor
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
            let metadataRect = ScanRegion.metadataRect(fromVisionRect: fullFrameRect)
            let layerRect = previewLayer.layerRectConverted(fromMetadataOutputRect: metadataRect)

            layer.isHidden = false
            layer.path = UIBezierPath(rect: layerRect).cgPath
        }
    }
#endif
}
