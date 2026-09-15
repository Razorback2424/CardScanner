import Foundation
import Photos

/// Adds finished listing photos to the user's photo library, in listing order.
/// Kept separate from `EbayListingPhotoExport` so the export pipeline stays free
/// of photo-library authorization and its UI-facing failure modes.
enum ListingPhotoLibrarySaver {
    enum SaveError: Swift.Error, LocalizedError {
        case notAuthorized
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Photos access is off. Turn on Add Photos Only for this app in Settings to save listing photos."
            case let .saveFailed(reason):
                return "The listing photos could not be saved to Photos: \(reason)"
            }
        }
    }

    /// Adds every URL as a photo asset. Throws without writing anything if the
    /// user declines, and writes all or nothing otherwise: `performChanges`
    /// applies the whole block atomically.
    static func save(_ urls: [URL]) async throws {
        guard !urls.isEmpty else { return }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw SaveError.notAuthorized
        }

        // Photos orders by creation date, and assets added inside one change
        // block otherwise land on the same timestamp in an arbitrary order.
        // Spacing them one second apart is what preserves 01…10 in the library,
        // since the numbered filenames themselves are not kept.
        let base = Date()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                for (index, url) in urls.enumerated() {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    // The export owns these files and deletes them itself.
                    options.shouldMoveFile = false
                    options.originalFilename = url.lastPathComponent
                    request.addResource(with: .photo, fileURL: url, options: options)
                    request.creationDate = base.addingTimeInterval(Double(index))
                }
            }
        } catch {
            throw SaveError.saveFailed(error.localizedDescription)
        }
    }
}
