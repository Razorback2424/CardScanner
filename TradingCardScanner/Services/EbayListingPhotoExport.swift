import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import zlib

/// Builds five native-resolution JPEGs per supplied side of an eBay card listing.
/// Decoding and pixel work stay inside a detached task so the main actor only
/// receives URLs, metadata, and already-rendered grid previews.
enum EbayListingPhotoExport {
    private static let shareLock = NSLock()
    private static var sharedRunContainers: Set<URL> = []

    /// A share extension can read after its source screen has disappeared.
    /// Keep handed-off runs for this process; the next launch's sweep retires them.
    static func retainForShare(_ file: URL) {
        let file = file.standardizedFileURL
        for name in ["EbayListingPhotos", "EbayListingPhotoBatches"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
                .standardizedFileURL
            guard file.path.hasPrefix(root.path + "/") else { continue }
            let relative = file.path.dropFirst(root.path.count + 1)
            guard let runID = relative.split(separator: "/").first,
                  UUID(uuidString: String(runID)) != nil else { return }
            shareLock.lock()
            sharedRunContainers.insert(root.appendingPathComponent(String(runID), isDirectory: true))
            shareLock.unlock()
            return
        }
    }

    static let maximumJPEGByteCount = 12_000_000
    static let previewMaximumPixelDimension = 320
    /// The readable root folder preserved inside every ZIP.
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
        /// Empty when the caller opts out of grid previews.
        let previews: [UIImage]
        let pixelDimensions: [PixelDimensions]
        let reducedQualityNames: [String]

        /// Every file in `urls` shares this parent.
        var contentDirectory: URL? { urls.first?.deletingLastPathComponent() }
    }

    enum Error: Swift.Error, LocalizedError {
        case decodeFailed(side: String)
        case encodeFailed(name: String)
        case writeFailed(name: String)
        case byteBudgetExceeded(name: String, byteCount: Int)
        case emptyBatch
        case missingSource
        case invalidOrder

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
            case .missingSource:
                return "Add a front or back photo to generate listing photos."
            case .invalidOrder:
                return "The photo order is incomplete. Generate the photos again."
            }
        }
    }

    /// Produces five files per supplied side in listing order, preserving the
    /// original numbering (01–05 front, 06–10 back) for side-only replacements.
    /// Returns small previews plus Sendable metadata to the caller. File-only
    /// batch callers can skip rendering previews from the already-decoded images.
    static func makeListingPhotos(
        frontData: Data?,
        backData: Data?,
        maximumByteCount: Int = maximumJPEGByteCount,
        includePreviews: Bool = true
    ) async throws -> Output {
        try await runListingPhotos(
            frontData: frontData, backData: backData,
            maximumByteCount: maximumByteCount, includePreviews: includePreviews,
            afterFrontWritten: nil
        )
    }

#if DEBUG
    /// Per-call test checkpoint at the existing between-sides cancellation boundary.
    static func makeListingPhotos(
        frontData: Data,
        backData: Data,
        includePreviews: Bool,
        afterFrontWritten: @escaping @Sendable (URL) throws -> Void
    ) async throws -> Output {
        try await runListingPhotos(
            frontData: frontData, backData: backData,
            maximumByteCount: maximumJPEGByteCount, includePreviews: includePreviews,
            afterFrontWritten: afterFrontWritten
        )
    }
#endif

    private static func runListingPhotos(
        frontData: Data?,
        backData: Data?,
        maximumByteCount: Int,
        includePreviews: Bool,
        afterFrontWritten: (@Sendable (URL) throws -> Void)?
    ) async throws -> Output {
        guard frontData != nil || backData != nil else { throw Error.missingSource }
        let directory = try await RunDirectoryStore.shared.beginRun()
        do {
            let worker = Task.detached(priority: .userInitiated) {
                try makeListingPhotosSynchronously(
                    frontData: frontData,
                    backData: backData,
                    directory: directory,
                    maximumByteCount: maximumByteCount,
                    includePreviews: includePreviews,
                    afterFrontWritten: afterFrontWritten
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

    /// Lightweight source-screen previews use the same ratios and corner order
    /// as the export, without writing JPEGs or decoding camera-sized pixels.
    static func makeStylePreviews(data: Data, isBack: Bool) async throws -> [UIImage] {
        let worker = Task.detached(priority: .userInitiated) {
            let preview = try inputPreviewSynchronously(data: data, maximumPixelDimension: 640)
            guard let image = preview.cgImage else { throw Error.decodeFailed(side: isBack ? "back" : "front") }
            let rects = try EbayQuadrantCropper.cropRects(imageWidth: image.width, imageHeight: image.height,
                                                        ratio: isBack ? EbayQuadrantCropper.backRatio : EbayQuadrantCropper.frontRatio)
            return [preview] + (try EbayQuadrantCropper.Quadrant.allCases.map {
                UIImage(cgImage: try EbayQuadrantCropper.crop(image, to: rects[$0]!))
            })
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    /// Copy into a fresh run so a share extension may keep reading the previous
    /// files. Renumbering is lossless and leaves the original run untouched if a
    /// copy fails or the user leaves the workflow before it finishes.
    static func reorderedCopy(of output: Output, order: [Int]) async throws -> Output {
        guard !order.isEmpty, order.count == output.urls.count, Set(order) == Set(output.urls.indices),
              output.previews.count == order.count, output.pixelDimensions.count == order.count else {
            throw Error.invalidOrder
        }
        let directory = try await RunDirectoryStore.shared.beginRun()
        do {
            let worker = Task.detached(priority: .userInitiated) {
                let firstNumber = output.urls.count == 5 && output.urls.allSatisfy { $0.lastPathComponent.contains("Back") } ? 6 : 1
                var urls: [URL] = []
                var reduced: [String] = []
                for (position, index) in order.enumerated() {
                    try Task.checkCancellation()
                    let name = String(format: "%02d-", firstNumber + position) + output.urls[index].lastPathComponent.dropFirst(3)
                    let url = directory.appendingPathComponent(name)
                    try FileManager.default.copyItem(at: output.urls[index], to: url)
                    urls.append(url)
                    if output.reducedQualityNames.contains(output.urls[index].lastPathComponent) { reduced.append(name) }
                }
                return Output(urls: urls, previews: order.map { output.previews[$0] },
                              pixelDimensions: order.map { output.pixelDimensions[$0] }, reducedQualityNames: reduced)
            }
            return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        } catch {
            removeRun(at: container(of: directory))
            throw error
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
        prepareTemporaryDirectories()
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

    /// JPEGs are already compressed. Stream them directly into a stored ZIP;
    /// upload coordination recompressed them and copied the entire result.
    private static func makeArchiveSynchronously(at contentDirectory: URL) throws -> URL {
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: contentDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
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

        do {
            try ListingPhotoZIPWriter.write(directory: contentDirectory, to: archiveURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Error.writeFailed(name: "the batch archive (\(error.localizedDescription))")
        }
        return archiveURL
    }

    /// The archive worker may outlive cancellation. Clean its captured run, but
    /// publish only while the caller still owns that run. The injected worker
    /// lets delayed success/failure exercise this boundary without native ZIP timing.
    @MainActor
    static func finishBatchArchive(
        at directory: URL,
        archive: @Sendable (URL) async throws -> URL = { try await EbayListingPhotoExport.makeArchive(at: $0) },
        isCurrent: () -> Bool,
        publish: (Result<URL, Swift.Error>) -> Void
    ) async {
        let result: Result<URL, Swift.Error>
        do { result = .success(try await archive(directory)) }
        catch { result = .failure(error) }
        guard !Task.isCancelled, isCurrent() else {
            await Task.detached { removeRunContainer(forContentDirectory: directory) }.value
            return
        }
        if case .failure = result {
            await Task.detached { removeRunContainer(forContentDirectory: directory) }.value
        }
        guard !Task.isCancelled, isCurrent() else { return }
        publish(result)
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

    /// Streams the batch off the main actor and propagates cancellation to the
    /// writer, which removes incomplete archives before returning.
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

    // Swift initializes a static let exactly once, including simultaneous
    // single and batch callers. Sweep before either can own files, never when
    // another screen instance appears during an outstanding Photos save.
    private static let temporaryDirectoriesPrepared: Void = {
        for name in ["EbayListingPhotos", "EbayListingPhotoBatches"] {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent(name, isDirectory: true)
            removeRun(at: root)
        }
    }()

    static func prepareTemporaryDirectories() {
        _ = temporaryDirectoriesPrepared
    }

    static func removeRun(at directory: URL?) {
        guard let directory else { return }
        shareLock.lock()
        let path = directory.standardizedFileURL.path
        guard !sharedRunContainers.contains(where: {
            path == $0.path || path.hasPrefix($0.path + "/")
        }) else { shareLock.unlock(); return }
        // Retire the path while holding the ownership lock, but never hold the
        // lock during recursive deletion: a share callback may need it on UI.
        let retired = directory.deletingLastPathComponent()
            .appendingPathComponent(".retired-\(UUID().uuidString)")
        do { try FileManager.default.moveItem(at: directory, to: retired) }
        catch { shareLock.unlock(); return }
        shareLock.unlock()
        do {
            try FileManager.default.removeItem(at: retired)
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

    /// UI invalidation relinquishes ownership immediately; disk cleanup must
    /// not stall navigation or the next export.
    static func discardRunInBackground(at directory: URL?) {
        Task.detached(priority: .utility) { removeRun(at: directory) }
    }

    static func discardRunContainerInBackground(forContentDirectory directory: URL?) {
        guard let directory else { return }
        discardRunInBackground(at: container(of: directory))
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
        frontData: Data?,
        backData: Data?,
        directory: URL,
        maximumByteCount: Int,
        includePreviews: Bool,
        afterFrontWritten: (@Sendable (URL) throws -> Void)?
    ) throws -> Output {
        try checkCancellation()
        var front = SideOutput()
        if let frontData {
            front = try processSide(
                data: frontData,
                side: .front,
                directory: directory,
                maximumByteCount: maximumByteCount,
                includePreviews: includePreviews
            )
            try afterFrontWritten?(directory)
        }
        try checkCancellation()
        var back = SideOutput()
        if let backData {
            back = try processSide(
                data: backData,
                side: .back,
                directory: directory,
                maximumByteCount: maximumByteCount,
                includePreviews: includePreviews
            )
        }
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
        maximumByteCount: Int,
        includePreviews: Bool
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
            if includePreviews {
                output.previews.append(
                    try preview(for: image, maximumPixelDimension: previewMaximumPixelDimension)
                )
            }
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
                if includePreviews {
                    output.previews.append(
                        try preview(for: crop, maximumPixelDimension: previewMaximumPixelDimension)
                    )
                }
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

        func beginRun() throws -> URL {
            EbayListingPhotoExport.prepareTemporaryDirectories()
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("EbayListingPhotos", isDirectory: true)
            do {
                try FileManager.default.createDirectory(
                    at: root,
                    withIntermediateDirectories: true
                )
                let container = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
                let directory = container.appendingPathComponent(archiveRootName, isDirectory: true)
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                return directory
            } catch {
                throw EbayListingPhotoExport.Error.writeFailed(name: "the temporary listing-photo directory")
            }
        }
    }
}

/// ZIP method 0 (stored), with UTF-8 names, CRC32 and ZIP64 directory offsets.
/// Only one 1 MiB chunk of photo data is resident at a time. Files are app-owned
/// JPEGs (at most 12 MB each); ZIP64 lets the complete batch exceed 4 GB.
enum ListingPhotoZIPWriter {
    private struct Entry {
        let name: Data
        let size: UInt32
        let crc: UInt32
        let offset: UInt64
    }

    static func write(directory: URL, to destination: URL) throws {
        let directory = directory.resolvingSymlinksInPath()
        let manager = FileManager.default
        var enumerationError: Swift.Error?
        guard let enumerator = manager.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            errorHandler: { _, error in enumerationError = error; return false }
        ) else { throw CocoaError(.fileReadUnknown) }
        // Enumerate before creating the destination, which lives outside this tree.
        var files: [URL] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw CocoaError(.fileReadUnsupportedScheme) }
            if values.isRegularFile == true { files.append(url) }
        }
        if let enumerationError { throw enumerationError }
        guard !files.isEmpty else { throw EbayListingPhotoExport.Error.emptyBatch }
        files.sort { $0.path < $1.path }
        guard manager.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var complete = false
        defer { if !complete { try? manager.removeItem(at: destination) } }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var entries: [Entry] = []
        let base = directory.deletingLastPathComponent().path + "/"
        for url in files {
            try Task.checkCancellation()
            let path = url.resolvingSymlinksInPath().path
            guard path.hasPrefix(base) else { throw CocoaError(.fileReadInvalidFileName) }
            let name = Data(path.dropFirst(base.count).utf8)
            guard name.count <= Int(UInt16.max) else { throw CocoaError(.fileWriteInvalidFileName) }
            let offset = try output.offset()
            // Data descriptor supplies CRC and sizes after streaming the bytes.
            try output.write(contentsOf: record([
                (0x04034b50, 4), (20, 2), (0x0808, 2), (0, 2),
                (0, 2), (0x21, 2), (0, 4), (0, 4), (0, 4),
                (UInt64(name.count), 2), (0, 2)
            ]) + name)
            let input = try FileHandle(forReadingFrom: url)
            var crc: uLong = 0
            var size: UInt64 = 0
            do {
                defer { try? input.close() }
                while true {
                    let finished = try autoreleasepool {
                        try Task.checkCancellation()
                        let chunk = try input.read(upToCount: 1_048_576) ?? Data()
                        if chunk.isEmpty { return true }
                        size += UInt64(chunk.count)
                        guard size < UInt64(UInt32.max) else {
                            throw CocoaError(.fileWriteUnknown, userInfo: [
                                NSLocalizedDescriptionKey: "A listing photo exceeds the ZIP per-file size limit."
                            ])
                        }
                        crc = chunk.withUnsafeBytes { bytes in
                            crc32(crc, bytes.bindMemory(to: Bytef.self).baseAddress, uInt(chunk.count))
                        }
                        try output.write(contentsOf: chunk)
                        return false
                    }
                    if finished { break }
                }
            }
            try output.write(contentsOf: record([
                (0x08074b50, 4), (UInt64(crc), 4), (size, 4), (size, 4)
            ]))
            entries.append(Entry(name: name, size: UInt32(size), crc: UInt32(crc), offset: offset))
        }
        let directoryOffset = try output.offset()
        for entry in entries {
            try Task.checkCancellation()
            let needsZIP64 = entry.offset >= UInt64(UInt32.max)
            let extra = needsZIP64 ? record([(1, 2), (8, 2), (entry.offset, 8)]) : Data()
            try output.write(contentsOf: record([
                (0x02014b50, 4), (45, 2), (needsZIP64 ? 45 : 20, 2),
                (0x0808, 2), (0, 2), (0, 2), (0x21, 2),
                (UInt64(entry.crc), 4), (UInt64(entry.size), 4), (UInt64(entry.size), 4),
                (UInt64(entry.name.count), 2), (UInt64(extra.count), 2),
                (0, 2), (0, 2), (0, 2), (0, 4),
                (min(entry.offset, UInt64(UInt32.max)), 4)
            ]) + entry.name + extra)
        }
        let endOffset = try output.offset()
        let directorySize = endOffset - directoryOffset
        let count = UInt64(entries.count)
        if directoryOffset >= UInt64(UInt32.max) || directorySize >= UInt64(UInt32.max)
            || count >= UInt64(UInt16.max) {
            try output.write(contentsOf: record([
                (0x06064b50, 4), (44, 8), (45, 2), (45, 2), (0, 4), (0, 4),
                (count, 8), (count, 8), (directorySize, 8), (directoryOffset, 8),
                (0x07064b50, 4), (0, 4), (endOffset, 8), (1, 4)
            ]))
        }
        try output.write(contentsOf: record([
            (0x06054b50, 4), (0, 2), (0, 2),
            (min(count, UInt64(UInt16.max)), 2), (min(count, UInt64(UInt16.max)), 2),
            (min(directorySize, UInt64(UInt32.max)), 4),
            (min(directoryOffset, UInt64(UInt32.max)), 4), (0, 2)
        ]))
        try Task.checkCancellation()
        try output.close()
        complete = true
    }

    private static func record(_ fields: [(UInt64, Int)]) -> Data {
        var data = Data()
        for (value, width) in fields {
            for byte in 0..<width { data.append(UInt8(truncatingIfNeeded: value >> (byte * 8))) }
        }
        return data
    }
}
