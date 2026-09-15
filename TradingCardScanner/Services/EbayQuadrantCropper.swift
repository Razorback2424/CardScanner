import CoreGraphics
import Foundation

/// Computes and applies the four overlapping corner crops used by the eBay
/// listing-photo workflow. This type deliberately knows nothing about image
/// decoding, persistence, or files.
enum EbayQuadrantCropper {
    /// The order is the listing order for the four corner crops.
    enum Quadrant: CaseIterable, Hashable, Sendable {
        case topLeft
        case topRight
        case bottomRight
        case bottomLeft
    }

    enum CropError: Error, Equatable, LocalizedError {
        case unsupportedRatio
        case degenerateImage

        var errorDescription: String? {
            switch self {
            case .unsupportedRatio:
                return "The listing-photo crop ratio must be between 0.5 and 0.9."
            case .degenerateImage:
                return "The source image cannot produce a non-empty listing-photo crop."
            }
        }
    }

    static let frontRatio = 0.60
    static let backRatio = 0.63

    /// Returns integer-pixel rectangles matching the original Python tool's
    /// `int()` truncation exactly. `Quadrant.allCases` is intentionally in
    /// listing order; downstream numbering depends on it.
    static func cropRects(
        imageWidth: Int,
        imageHeight: Int,
        ratio: Double
    ) throws -> [Quadrant: CGRect] {
        guard (0.5...0.9).contains(ratio) else {
            throw CropError.unsupportedRatio
        }

        guard imageWidth > 0, imageHeight > 0 else {
            throw CropError.degenerateImage
        }

        let cropWidth = Int(Double(imageWidth) * ratio)
        let cropHeight = Int(Double(imageHeight) * ratio)
        guard cropWidth > 0, cropHeight > 0 else {
            throw CropError.degenerateImage
        }

        return [
            .topLeft: CGRect(x: 0, y: 0, width: cropWidth, height: cropHeight),
            .topRight: CGRect(
                x: imageWidth - cropWidth,
                y: 0,
                width: cropWidth,
                height: cropHeight
            ),
            .bottomRight: CGRect(
                x: imageWidth - cropWidth,
                y: imageHeight - cropHeight,
                width: cropWidth,
                height: cropHeight
            ),
            .bottomLeft: CGRect(
                x: 0,
                y: imageHeight - cropHeight,
                width: cropWidth,
                height: cropHeight
            )
        ]
    }

    /// Returns a non-copying `CGImage` view into `image`. Keeping that laziness
    /// is the memory strategy: the parent image remains the only decoded side,
    /// and each crop costs only its JPEG encode buffer.
    static func crop(_ image: CGImage, to rect: CGRect) throws -> CGImage {
        guard rect.width > 0, rect.height > 0,
              let cropped = image.cropping(to: rect) else {
            throw CropError.degenerateImage
        }
        return cropped
    }
}
