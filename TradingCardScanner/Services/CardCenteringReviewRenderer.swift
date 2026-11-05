import CoreImage
import UIKit

/// Optional display-only resampling. Ratios always use the point transform;
/// no measurement is derived from this raster and no corrected image is saved.
enum CardCenteringReviewRenderer {
    struct Output: @unchecked Sendable {
        let photo: UIImage
        let rectified: UIImage
        let rectifiedSize: CardCenteringSize
        let revision: CardCenteringGeometryRevision
    }

    static func render(image: UIImage, measurement: CardCenteringMeasurement,
                       rotationDegrees: Double) throws -> Output {
        try Task.checkCancellation()
        guard rotationDegrees.isFinite, let spatial = measurement.spatialMeasurement,
              image.cgImage != nil else { throw CardCenteringAnalyzerError.renderFailed }
        let width = CGFloat(measurement.imageWidth), height = CGFloat(measurement.imageHeight)
        let workingScale = min(1, 1200 / max(width, height))
        // Work only with the existing presentation raster, never native camera
        // bytes. Match the current photo's rotation about its canvas centre.
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let photo = UIGraphicsImageRenderer(size: CGSize(width: width * workingScale, height: height * workingScale), format: format).image { context in
            context.cgContext.scaleBy(x: workingScale, y: workingScale)
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.cgContext.translateBy(x: width / 2, y: height / 2)
            context.cgContext.rotate(by: rotationDegrees * .pi / 180)
            image.draw(in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        }
        try Task.checkCancellation()
        guard let cg = photo.cgImage else { throw CardCenteringAnalyzerError.renderFailed }
        func vector(_ p: CardCenteringPoint) -> CIVector {
            .init(x: p.x * workingScale, y: (Double(height) - p.y) * workingScale)
        }
        let outer = measurement.geometryOuterQuad
        let input = CIImage(cgImage: cg)
        let corrected = input.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": vector(outer.topLeft), "inputTopRight": vector(outer.topRight),
            "inputBottomRight": vector(outer.bottomRight), "inputBottomLeft": vector(outer.bottomLeft)
        ])
        let extent = corrected.extent
        guard !extent.isNull, !extent.isInfinite, extent.width > 0, extent.height > 0 else {
            throw CardCenteringAnalyzerError.renderFailed
        }
        let target = spatial.rectification.targetSize
        let scale = min(1, 1200 / max(target.width, target.height))
        let outputWidth = max(1, (target.width * scale).rounded())
        let outputHeight = max(1, (target.height * scale).rounded())
        // Core Image chooses its own rectangle extent. Scaling that rectangle
        // to our target establishes the same four-corner mapping used by the
        // measurement, including nonstandard card aspects.
        let normalized = corrected.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: outputWidth / extent.width, y: outputHeight / extent.height))
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let result = context.createCGImage(normalized, from: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)) else {
            throw CardCenteringAnalyzerError.renderFailed
        }
        try Task.checkCancellation()
        return .init(photo: photo, rectified: UIImage(cgImage: result), rectifiedSize: target, revision: spatial.revision)
    }
}
