import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Builds the ten native-resolution JPEGs used for one eBay card listing.
/// Decoding and pixel work stay inside a detached task so the main actor only
/// receives URLs, metadata, and already-rendered grid previews.
enum EbayListingPhotoExport {
    static let maximumJPEGByteCount = 12_000_000
    static let previewMaximumPixelDimension = 320
    /// The folder name every archive expands to. `NSFileCoordinator`'s
    /// `.forUploading` zips the directory it is handed and names the archive's
    /// single root entry after it, so this name — not a UUID — is what the
    /// person who opens the ZIP sees.
    static let archiveRootName = "eBay Listing Photos"
    /// The inspector's decode ceiling on the long edge. Roughly twice the pixel
    /// density of the largest iPhone screen, so a fitted image is already
    /// oversampled and stays sharp through the zoom range a corner check needs,
    /// while peak memory stays near 50 MB instead of the ~195 MB a 48 MP source
    /// would cost. Raise this only with a device memory check.
    static let inspectionMaximumPixelDimension = 4096

    struct PixelDimensions: Equatable, Sendable {
        let width: Int
        let height: Int
    }

    struct Output: @unchecked Sendable {
        let urls: [URL]
        let previews: [UIImage]
        let pixelDimensions: [PixelDimensions]
        let reducedQualityNames: [String]

        /// Where the ten files live. Every file in `urls` shares this parent.
        var contentDirectory: URL? { urls.first?.deletingLastPathComponent() }
    }

    enum Error: Swift.Error, LocalizedError {
        case decodeFailed(side: String)
        case encodeFailed(name: String)
        case writeFailed(name: String)
        case byteBudgetExceeded(name: String, byteCount: Int)
        case emptyBatch

        var errorDescription: String? {
            switch self {
            case let .decodeFailed(side):
                return "The \(side) photo could not be decoded at its native resolution."
            case let .encodeFailed(name):
                return "The \(name) image could not be encoded as a JPEG."
            case let .writeFailed(name):
                return "The \(name) image could not be written to temporary storage."
            case let .byteBudgetExceeded(name, byteCount):
                return "\(name) is still \(byteCount) bytes after the allowed JPEG quality steps, above eBay's 12 MB limit."
            case .emptyBatch:
                return "No card in the batch produced listing photos."
            }
        }
    }

    /// Decodes one front/back pair, produces ten files in listing order, and
    /// returns only small previews plus Sendable metadata to the caller.
    static func makeListingPhotos(
        frontData: Data,
        backData: Data,
        maximumByteCount: Int = maximumJPEGByteCount
    ) async throws -> Output {
        let directory = try await RunDirectoryStore.shared.beginRun()
        do {
            let worker = Task.detached(priority: .userInitiated) {
                try makeListingPhotosSynchronously(
                    frontData: frontData,
                    backData: backData,
                    directory: directory,
                    maximumByteCount: maximumByteCount
                )
            }

            return try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
        } catch {
            removeRun(at: container(of: directory))
            throw error
        }
    }

    /// Makes a review thumbnail without decoding a full-size image into the
    /// UI. Batch review uses this before the native-resolution export pass.
    static func makeInputPreview(
        data: Data,
        maximumPixelDimension: Int = 160
    ) async throws -> UIImage {
        let worker = Task.detached(priority: .userInitiated) {
            try inputPreviewSynchronously(
                data: data,
                maximumPixelDimension: maximumPixelDimension
            )
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// Decodes one exported file for on-screen review, capped at
    /// `inspectionMaximumPixelDimension`. Reads through a URL-backed image
    /// source so the JPEG is streamed from disk instead of being loaded whole.
    static func makeInspectionImage(at url: URL) async throws -> UIImage {
        let worker = Task.detached(priority: .userInitiated) {
            try inspectionImageSynchronously(at: url)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// Creates the temporary package used by the batch workflow and returns the
    /// directory the card folders go into. Its parent is the run container, so
    /// the archive can sit beside it and one delete cleans up the whole run.
    static func makeBatchDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EbayListingPhotoBatches", isDirectory: true)
        do {
            let directory = root
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(archiveRootName, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory
        } catch {
            throw Error.writeFailed(name: "the batch directory (\(error.localizedDescription))")
        }
    }

    /// Moves one completed pair into its batch folder, releasing the single
    /// pair directory before the next pair is decoded.
    private static func moveOutputSynchronously(_ output: Output, to cardDirectory: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: cardDirectory,
                withIntermediateDirectories: true
            )
            for url in output.urls {
                let destination = cardDirectory.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination)
            }
            removeRunContainer(forContentDirectory: output.contentDirectory)
        } catch {
            // A move can fail after some files have crossed into the card
            // directory. The pair is skipped as a unit, so do not leave a
            // partial folder in the archive.
            removeRun(at: cardDirectory)
            throw Error.writeFailed(name: "the batch card directory (\(error.localizedDescription))")
        }
    }

    /// Coordinates a directory read using Foundation's uploading intent, then
    /// keeps the generated zip in the same temporary batch root for sharing.
    private static func makeArchiveSynchronously(at contentDirectory: URL) throws -> URL {
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: contentDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw Error.writeFailed(name: "the batch archive source (\(error.localizedDescription))")
        }
        guard !children.isEmpty else { throw Error.emptyBatch }

        let archiveURL = container(of: contentDirectory)
            .appendingPathComponent("\(contentDirectory.lastPathComponent).zip")
        do {
            if FileManager.default.fileExists(atPath: archiveURL.path) {
                try FileManager.default.removeItem(at: archiveURL)
            }
        } catch {
            throw Error.writeFailed(name: "the previous batch archive (\(error.localizedDescription))")
        }

        var coordinationError: NSError?
        var copyError: Swift.Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: contentDirectory,
            options: .forUploading,
            error: &coordinationError
        ) { uploadingURL in
            do {
                try FileManager.default.copyItem(at: uploadingURL, to: archiveURL)
            } catch {
                copyError = error
            }
        }

        if let coordinationError {
            throw Error.writeFailed(name: "the batch archive (\(coordinationError.localizedDescription))")
        }
        if let copyError {
            throw Error.writeFailed(name: "the batch archive (\(copyError.localizedDescription))")
        }
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw Error.writeFailed(name: "the batch archive")
        }
        return archiveURL
    }

    /// Moves one completed pair into its batch folder off the main actor.
    /// A rename is usually cheap, but a cross-volume fallback copy is not, and
    /// this runs once per card while the progress view must stay responsive.
    static func moveOutput(_ output: Output, to cardDirectory: URL) async throws {
        let worker = Task.detached(priority: .userInitiated) {
            try moveOutputSynchronously(output, to: cardDirectory)
        }
        try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// Zips the batch off the main actor. Compressing and copying a multi-card
    /// batch of native-resolution JPEGs is a multi-second operation; running it
    /// on the main actor froze the progress view until it finished.
    static func makeArchive(at contentDirectory: URL) async throws -> URL {
        let worker = Task.detached(priority: .userInitiated) {
            try makeArchiveSynchronously(at: contentDirectory)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// Deletes everything both temporary roots hold. Call once per app launch:
    /// a run that ended in a crash or jetsam leaves native-resolution JPEGs
    /// behind that no in-process bookkeeping can reclaim.
    static func removeOrphanedTemporaryDirectories() {
        for name in ["EbayListingPhotos", "EbayListingPhotoBatches"] {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent(name, isDirectory: true)
            removeRun(at: root)
        }
    }

    static func removeRun(at directory: URL?) {
        guard let directory else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            // Temporary cleanup is best effort. Processing errors are never
            // swallowed; this path only runs after a result is superseded or
            // the view has dismissed.
        }
    }

    /// The UUID directory that owns a content directory, its card folders, and
    /// any archive built beside it. Deleting it cleans up the whole run.
    static func container(of contentDirectory: URL) -> URL {
        contentDirectory.deletingLastPathComponent()
    }

    /// Deletes the whole run container that owns `contentDirectory`.
    static func removeRunContainer(forContentDirectory contentDirectory: URL?) {
        guard let contentDirectory else { return }
        removeRun(at: container(of: contentDirectory))
    }

    private enum Side: Equatable, Sendable {
        case front
        case back

        var label: String {
            switch self {
            case .front: return "front"
            case .back: return "back"
            }
        }

        var ratio: Double {
            switch self {
            case .front: return EbayQuadrantCropper.frontRatio
            case .back: return EbayQuadrantCropper.backRatio
            }
        }

        var fullName: String {
            switch self {
            case .front: return "01-Front.jpg"
            case .back: return "06-Back.jpg"
            }
        }

        func cropName(for quadrant: EbayQuadrantCropper.Quadrant) -> String {
            let prefix: String
            switch self {
            case .front: prefix = "Front"
            case .back: prefix = "Back"
            }
            let number: String
            let suffix: String
            switch quadrant {
            case .topLeft:
                number = self == .front ? "02" : "07"
                suffix = "TL"
            case .topRight:
                number = self == .front ? "03" : "08"
                suffix = "TR"
            case .bottomRight:
                number = self == .front ? "04" : "09"
                suffix = "BR"
            case .bottomLeft:
                number = self == .front ? "05" : "10"
                suffix = "BL"
            }
            return "\(number)-\(prefix)-\(suffix).jpg"
        }
    }

    private struct SideOutput {
        var urls: [URL] = []
        var previews: [UIImage] = []
        var pixelDimensions: [PixelDimensions] = []
        var reducedQualityNames: [String] = []
    }

    private static func makeListingPhotosSynchronously(
        frontData: Data,
        backData: Data,
        directory: URL,
        maximumByteCount: Int
    ) throws -> Output {
        try checkCancellation()
        let front = try processSide(
            data: frontData,
            side: .front,
            directory: directory,
            maximumByteCount: maximumByteCount
        )
        try checkCancellation()
        let back = try processSide(
            data: backData,
            side: .back,
            directory: directory,
            maximumByteCount: maximumByteCount
        )
        return Output(
            urls: front.urls + back.urls,
            previews: front.previews + back.previews,
            pixelDimensions: front.pixelDimensions + back.pixelDimensions,
            reducedQualityNames: front.reducedQualityNames + back.reducedQualityNames
        )
    }

    private static func processSide(
        data: Data,
        side: Side,
        directory: URL,
        maximumByteCount: Int
    ) throws -> SideOutput {
        try checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw Error.decodeFailed(side: side.label)
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
              let sourceWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let sourceHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              sourceWidth > 0,
              sourceHeight > 0 else {
            throw Error.decodeFailed(side: side.label)
        }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value
            ?? CGImagePropertyOrientation.up.rawValue
        let sourceIsJPEG = CGImageSourceGetType(source).map {
            $0 == (UTType.jpeg.identifier as CFString)
        } ?? false
        let sourceIsIdentityOriented = orientation == CGImagePropertyOrientation.up.rawValue

        let image = try decodeNativeImage(
            source: source,
            maximumPixelSize: max(sourceWidth, sourceHeight),
            side: side
        )
        try checkCancellation()
        let dimensions = PixelDimensions(width: image.width, height: image.height)
        var output = SideOutput()

        try autoreleasepool {
            try checkCancellation()
            let fullName = side.fullName
            let fullData: Data
            var reducedQuality = false
            if sourceIsJPEG, sourceIsIdentityOriented, data.count <= maximumByteCount {
                // This is the only path that preserves the original JPEG
                // bytes and therefore avoids another generation-loss pass.
                fullData = data
            } else {
                let encoded = try encodedJPEG(
                    image: image,
                    name: fullName,
                    maximumByteCount: maximumByteCount
                )
                fullData = encoded.data
                reducedQuality = encoded.reducedQuality
            }
            let fullURL = try write(fullData, named: fullName, to: directory)
            output.urls.append(fullURL)
            output.previews.append(
                try preview(for: image, maximumPixelDimension: previewMaximumPixelDimension)
            )
            output.pixelDimensions.append(dimensions)
            if reducedQuality {
                output.reducedQualityNames.append(fullName)
            }
        }

        let rects = try EbayQuadrantCropper.cropRects(
            imageWidth: image.width,
            imageHeight: image.height,
            ratio: side.ratio
        )
        for quadrant in EbayQuadrantCropper.Quadrant.allCases {
            try autoreleasepool {
                try checkCancellation()
                guard let rect = rects[quadrant] else {
                    throw EbayQuadrantCropper.CropError.degenerateImage
                }
                let crop = try EbayQuadrantCropper.crop(image, to: rect)
                let name = side.cropName(for: quadrant)
                let encoded = try encodedJPEG(
                    image: crop,
                    name: name,
                    maximumByteCount: maximumByteCount
                )
                let url = try write(encoded.data, named: name, to: directory)
                output.urls.append(url)
                output.previews.append(
                    try preview(for: crop, maximumPixelDimension: previewMaximumPixelDimension)
                )
                output.pixelDimensions.append(
                    PixelDimensions(width: crop.width, height: crop.height)
                )
                if encoded.reducedQuality {
                    output.reducedQualityNames.append(name)
                }
            }
        }

        return output
    }

    private static func decodeNativeImage(
        source: CGImageSource,
        maximumPixelSize: Int,
        side: Side
    ) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Error.decodeFailed(side: side.label)
        }
        return image
    }

    private static func encodedJPEG(
        image: CGImage,
        name: String,
        maximumByteCount: Int
    ) throws -> (data: Data, reducedQuality: Bool) {
        // The ladder must be able to bring the largest image this app can
        // produce under the budget. The camera path captures at the sensor's
        // maximum photo dimensions (48 MP on recent devices), and a 48 MP JPEG
        // of a foil card can still exceed 12 MB at 0.75. Stopping there made a
        // single oversized image discard the whole ten-photo set.
        let qualities: [CGFloat] = [0.95, 0.85, 0.75, 0.65, 0.55, 0.45]
        var lastByteCount = 0
        for (index, quality) in qualities.enumerated() {
            try checkCancellation()
            guard let data = jpegData(image: image, quality: quality) else {
                throw Error.encodeFailed(name: name)
            }
            lastByteCount = data.count
            if data.count <= maximumByteCount {
                return (data, index > 0)
            }
        }
        throw Error.byteBudgetExceeded(name: name, byteCount: lastByteCount)
    }

    private static func checkCancellation() throws {
        if Task.isCancelled {
            throw CancellationError()
        }
    }

    private static func jpegData(image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func write(_ data: Data, named name: String, to directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw Error.writeFailed(name: name)
        }
    }

    private static func preview(
        for image: CGImage,
        maximumPixelDimension: Int
    ) throws -> UIImage {
        let longestEdge = max(image.width, image.height)
        let scale = min(1, CGFloat(maximumPixelDimension) / CGFloat(max(longestEdge, 1)))
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw Error.encodeFailed(name: "preview")
        }
        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )
        guard let previewImage = context.makeImage() else {
            throw Error.encodeFailed(name: "preview")
        }
        return UIImage(cgImage: previewImage)
    }

    private static func inspectionImageSynchronously(at url: URL) throws -> UIImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw Error.decodeFailed(side: url.lastPathComponent)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: inspectionMaximumPixelDimension
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Error.decodeFailed(side: url.lastPathComponent)
        }
        return UIImage(cgImage: image)
    }

    private static func inputPreviewSynchronously(
        data: Data,
        maximumPixelDimension: Int
    ) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw Error.decodeFailed(side: "selected")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maximumPixelDimension)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Error.decodeFailed(side: "selected")
        }
        return UIImage(cgImage: image)
    }

    private actor RunDirectoryStore {
        static let shared = RunDirectoryStore()
        private var previousContainer: URL?

        func beginRun() throws -> URL {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("EbayListingPhotos", isDirectory: true)
            do {
                try FileManager.default.createDirectory(
                    at: root,
                    withIntermediateDirectories: true
                )
                if let previousContainer {
                    do {
                        try FileManager.default.removeItem(at: previousContainer)
                    } catch {
                        // A prior run may already have been cleaned by the view.
                    }
                }
                let container = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
                let directory = container.appendingPathComponent(archiveRootName, isDirectory: true)
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                previousContainer = container
                return directory
            } catch {
                throw EbayListingPhotoExport.Error.writeFailed(name: "the temporary listing-photo directory")
            }
        }
    }
}
