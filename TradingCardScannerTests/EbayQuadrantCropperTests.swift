import XCTest
import CoreGraphics
import CryptoKit
import ImageIO
import UIKit
import UniformTypeIdentifiers
@testable import TradingCardScanner

final class EbayQuadrantCropperTests: XCTestCase {
    func testHandedOffPhotoAndArchiveSurviveWorkflowCleanup() throws {
        for archive in [false, true] {
            let directory = try EbayListingPhotoExport.makeBatchDirectory()
            let run = EbayListingPhotoExport.container(of: directory)
            defer { try? FileManager.default.removeItem(at: run) }
            let file = archive ? run.appendingPathComponent("photos.zip") : directory.appendingPathComponent("01.jpg")
            try Data("shared artifact".utf8).write(to: file)
            EbayListingPhotoExport.retainForShare(file)
            EbayListingPhotoExport.removeRunContainer(forContentDirectory: directory)
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path),
                "Delayed share readers still own this file after the screen exits")

            let unshared = try EbayListingPhotoExport.makeBatchDirectory()
            let unsharedRun = EbayListingPhotoExport.container(of: unshared)
            EbayListingPhotoExport.removeRunContainer(forContentDirectory: unshared)
            XCTAssertFalse(FileManager.default.fileExists(atPath: unsharedRun.path),
                "Retaining one share must not retain unrelated cancelled or superseded runs")
        }
    }

    /// The crop geometry preserves the Python tool's truncation instead of
    /// rounding each dimension up.
    func testCropRectsTruncateLikeTheOriginalTool() throws {
        let rects = try EbayQuadrantCropper.cropRects(
            imageWidth: 1_001,
            imageHeight: 1_401,
            ratio: 0.60
        )

        XCTAssertEqual(rects[.topLeft]?.width, 600)
        XCTAssertEqual(rects[.topLeft]?.height, 840)
    }

    /// The four corner crops use the expected origins and overlap their
    /// neighbors so edge wear can appear in more than one listing photo.
    func testRealisticFrontRectsHaveExpectedOriginsAndOverlap() throws {
        let rects = try EbayQuadrantCropper.cropRects(
            imageWidth: 900,
            imageHeight: 1_260,
            ratio: 0.60
        )

        XCTAssertEqual(rects[.topLeft], CGRect(x: 0, y: 0, width: 540, height: 756))
        XCTAssertEqual(rects[.topRight], CGRect(x: 360, y: 0, width: 540, height: 756))
        XCTAssertEqual(rects[.bottomRight], CGRect(x: 360, y: 504, width: 540, height: 756))
        XCTAssertEqual(rects[.bottomLeft], CGRect(x: 0, y: 504, width: 540, height: 756))

        XCTAssertTrue(rects[.topLeft]!.intersection(rects[.topRight]!).width > 0)
        XCTAssertTrue(rects[.topRight]!.intersection(rects[.bottomRight]!).height > 0)
        XCTAssertTrue(rects[.bottomRight]!.intersection(rects[.bottomLeft]!).width > 0)
        XCTAssertTrue(rects[.bottomLeft]!.intersection(rects[.topLeft]!).height > 0)
    }

    /// Both production ratios produce four in-bounds rectangles for a card
    /// frame.
    func testFrontAndBackRectsStayInsideTheirSourceBounds() throws {
        for (ratio, width, height) in [
            (EbayQuadrantCropper.frontRatio, 900, 1_260),
            (EbayQuadrantCropper.backRatio, 900, 1_260)
        ] {
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            let rects = try EbayQuadrantCropper.cropRects(
                imageWidth: width,
                imageHeight: height,
                ratio: ratio
            )

            XCTAssertEqual(rects.count, 4)
            for quadrant in EbayQuadrantCropper.Quadrant.allCases {
                XCTAssertTrue(bounds.contains(rects[quadrant]!), "\(quadrant) escaped the source bounds")
            }
        }
    }

    /// The native-resolution case is locked to integer truncation so a future
    /// rounding refactor cannot silently change the exported pixel dimensions.
    func testFortyEightMegapixelFrameKeepsTruncatedCropDimensions() throws {
        let rects = try EbayQuadrantCropper.cropRects(
            imageWidth: 8_064,
            imageHeight: 6_048,
            ratio: 0.60
        )

        XCTAssertEqual(rects[.topLeft]?.width, 4_838)
        XCTAssertEqual(rects[.topLeft]?.height, 3_628)
        for rect in rects.values {
            XCTAssertTrue(CGRect(x: 0, y: 0, width: 8_064, height: 6_048).contains(rect))
        }
    }

    /// Quadrant ordering is the listing-order contract for outputs 02–05 and
    /// 07–10.
    func testQuadrantAllCasesIsListingOrder() {
        XCTAssertEqual(
            EbayQuadrantCropper.Quadrant.allCases,
            [.topLeft, .topRight, .bottomRight, .bottomLeft]
        )
    }

    /// Ratios outside the supported range are rejected instead of silently
    /// clamped by the crop primitive.
    func testUnsupportedRatiosThrow() {
        for ratio in [0.49, 0.91] {
            XCTAssertThrowsError(
                try EbayQuadrantCropper.cropRects(
                    imageWidth: 100,
                    imageHeight: 100,
                    ratio: ratio
                )
            ) { error in
                XCTAssertEqual(error as? EbayQuadrantCropper.CropError, .unsupportedRatio)
            }
        }
    }

    /// Zero-sized sources and ratios that truncate a crop dimension to zero
    /// are rejected as degenerate rather than producing invalid rectangles.
    func testDegenerateImagesThrow() {
        for arguments in [(0, 100, 0.60), (100, 0, 0.60), (1, 1, 0.50)] {
            XCTAssertThrowsError(
                try EbayQuadrantCropper.cropRects(
                    imageWidth: arguments.0,
                    imageHeight: arguments.1,
                    ratio: arguments.2
                )
            ) { error in
                XCTAssertEqual(error as? EbayQuadrantCropper.CropError, .degenerateImage)
            }
        }
    }

    /// Each crop comes from the physical corner it names, not merely from a
    /// rectangle of the right size.
    func testCropPixelComesFromItsNamedCorner() throws {
        let image = try XCTUnwrap(cornerFixture().cgImage)
        let rects = try EbayQuadrantCropper.cropRects(
            imageWidth: image.width,
            imageHeight: image.height,
            ratio: 0.60
        )

        let topLeft = try EbayQuadrantCropper.crop(image, to: rects[.topLeft]!)
        let topRight = try EbayQuadrantCropper.crop(image, to: rects[.topRight]!)
        let bottomRight = try EbayQuadrantCropper.crop(image, to: rects[.bottomRight]!)
        let bottomLeft = try EbayQuadrantCropper.crop(image, to: rects[.bottomLeft]!)

        let topLeftColor = sample(topLeft, x: 0, y: 0)
        let topRightColor = sample(topRight, x: topRight.width - 1, y: 0)
        let bottomRightColor = sample(bottomRight, x: bottomRight.width - 1, y: bottomRight.height - 1)
        let bottomLeftColor = sample(bottomLeft, x: 0, y: bottomLeft.height - 1)
        XCTAssertTrue(isRed(topLeftColor), "Unexpected TL color: \(topLeftColor)")
        XCTAssertTrue(isGreen(topRightColor), "Unexpected TR color: \(topRightColor)")
        XCTAssertTrue(isBlue(bottomRightColor), "Unexpected BR color: \(bottomRightColor)")
        XCTAssertTrue(isYellow(bottomLeftColor), "Unexpected BL color: \(bottomLeftColor)")
    }

    /// Cropping never resamples: the returned pixel dimensions equal the
    /// integer geometry primitive's rectangle dimensions.
    func testCropPixelDimensionsMatchTheirRects() throws {
        let image = try XCTUnwrap(cornerFixture(width: 101, height: 141).cgImage)
        let rects = try EbayQuadrantCropper.cropRects(
            imageWidth: image.width,
            imageHeight: image.height,
            ratio: 0.63
        )

        for quadrant in EbayQuadrantCropper.Quadrant.allCases {
            let rect = try XCTUnwrap(rects[quadrant])
            let crop = try EbayQuadrantCropper.crop(image, to: rect)
            XCTAssertEqual(crop.width, Int(rect.width))
            XCTAssertEqual(crop.height, Int(rect.height))
        }
    }

    private func cornerFixture(width: Int = 100, height: Int = 100) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            let cornerWidth = min(35, width / 3)
            let cornerHeight = min(35, height / 3)
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: cornerWidth, height: cornerHeight))
            UIColor.green.setFill()
            context.fill(CGRect(
                x: width - cornerWidth,
                y: 0,
                width: cornerWidth,
                height: cornerHeight
            ))
            UIColor.blue.setFill()
            context.fill(CGRect(
                x: width - cornerWidth,
                y: height - cornerHeight,
                width: cornerWidth,
                height: cornerHeight
            ))
            UIColor.yellow.setFill()
            context.fill(CGRect(
                x: 0,
                y: height - cornerHeight,
                width: cornerWidth,
                height: cornerHeight
            ))
        }
    }

    private func sample(_ image: CGImage, x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &bytes,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
    }

    private func isRed(_ color: (red: UInt8, green: UInt8, blue: UInt8)) -> Bool {
        color.red > 200 && color.green < 80 && color.blue < 80
    }

    private func isGreen(_ color: (red: UInt8, green: UInt8, blue: UInt8)) -> Bool {
        color.red < 80 && color.green > 100 && color.blue < 80
    }

    private func isBlue(_ color: (red: UInt8, green: UInt8, blue: UInt8)) -> Bool {
        color.red < 80 && color.green < 80 && color.blue > 100
    }

    private func isYellow(_ color: (red: UInt8, green: UInt8, blue: UInt8)) -> Bool {
        color.red > 180 && color.green > 180 && color.blue < 80
    }
}

private actor ListingArchiveGate {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func waitForRelease() async {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

/// Blocks only the injected test worker, with a deadline and a sticky release
/// so early cancellation, assertion failure, or release-before-arrival cannot hang it.
private final class ListingFrontCheckpoint: @unchecked Sendable {
    let reached = XCTestExpectation(description: "Five front JPEGs written")
    private let condition = NSCondition()
    private var directory: URL?
    private var released = false

    var contentDirectory: URL? {
        condition.lock()
        defer { condition.unlock() }
        return directory
    }

    func pause(at directory: URL) throws {
        condition.lock()
        defer { condition.unlock() }
        self.directory = directory
        reached.fulfill()
        let deadline = Date().addingTimeInterval(30)
        while !released {
            guard condition.wait(until: deadline) else { throw CheckpointError.timedOut }
        }
    }

    func release() {
        condition.lock()
        defer { condition.unlock() }
        released = true
        condition.broadcast()
    }

    private enum CheckpointError: Error { case timedOut }
}

final class EbayListingPhotoExportTests: XCTestCase {
    func testStoredArchivePreservesBytesNamesAndChecksumsAcrossChunks() async throws {
        let directory = try EbayListingPhotoExport.makeBatchDirectory()
        defer { EbayListingPhotoExport.removeRunContainer(forContentDirectory: directory) }
        let folder = directory.appendingPathComponent(".Card-é", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let photo = Data((0..<2_100_013).map { UInt8(truncatingIfNeeded: $0) })
        try photo.write(to: folder.appendingPathComponent("01.jpg"))
        try Data().write(to: folder.appendingPathComponent("02.jpg"))
        let archive = try await EbayListingPhotoExport.makeArchive(at: directory)
        let bytes = try Data(contentsOf: archive)
        func number(_ offset: Int, _ width: Int) -> Int {
            (0..<width).reduce(0) { $0 | (Int(bytes[offset + $1]) << ($1 * 8)) }
        }
        // Read through the central directory, as an independent ZIP reader does.
        let end = bytes.count - 22
        XCTAssertEqual(number(end, 4), 0x06054b50)
        XCTAssertEqual(number(end + 10, 2), 2)
        var cursor = number(end + 16, 4)
        for (index, expected) in [photo, Data()].enumerated() {
            XCTAssertEqual(number(cursor, 4), 0x02014b50)
            XCTAssertEqual(number(cursor + 10, 2), 0, "JPEGs must be stored without recompression")
            XCTAssertEqual(number(cursor + 8, 2), 0x0808, "UTF-8 names and streaming descriptor")
            let nameLength = number(cursor + 28, 2)
            let name = String(decoding: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
            XCTAssertEqual(name, "eBay Listing Photos/.Card-é/0\(index + 1).jpg")
            XCTAssertEqual(number(cursor + 24, 4), expected.count)
            let local = number(cursor + 42, 4)
            XCTAssertEqual(number(local, 4), 0x04034b50)
            let start = local + 30 + number(local + 26, 2) + number(local + 28, 2)
            XCTAssertEqual(bytes.subdata(in: start..<(start + expected.count)), expected)
            let descriptor = start + expected.count
            XCTAssertEqual(number(descriptor, 4), 0x08074b50)
            XCTAssertEqual(number(descriptor + 4, 4), number(cursor + 16, 4))
            // CRC32 independently calculated from the original bytes (IEEE polynomial).
            var crc = UInt32.max
            for byte in expected {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xedb88320) }
            }
            XCTAssertEqual(number(cursor + 16, 4), Int(crc ^ UInt32.max))
            cursor += 46 + nameLength + number(cursor + 30, 2) + number(cursor + 32, 2)
        }
        XCTAssertEqual(cursor, end)
    }

    func testCancelledArchiveDoesNotLeavePartialZIP() async throws {
        let directory = try EbayListingPhotoExport.makeBatchDirectory()
        defer { EbayListingPhotoExport.removeRunContainer(forContentDirectory: directory) }
        try Data("photo".utf8).write(to: directory.appendingPathComponent("01.jpg"))
        let destination = EbayListingPhotoExport.container(of: directory).appendingPathComponent("cancelled.zip")
        let worker = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            try ListingPhotoZIPWriter.write(directory: directory, to: destination)
        }
        do {
            try await worker.value
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    @MainActor
    func testSupersededArchiveSuccessAndFailureCleanOnlyTheirOwnRun() async throws {
        for (fails, cancels) in [(false, false), (true, false), (false, true), (true, true)] {
            let oldDirectory = try EbayListingPhotoExport.makeBatchDirectory()
            let newDirectory = try EbayListingPhotoExport.makeBatchDirectory()
            defer { EbayListingPhotoExport.removeRunContainer(forContentDirectory: newDirectory) }
            let gate = ListingArchiveGate()
            var generation = 1
            var loading = true
            var publishedDirectory = newDirectory
            var publishedError: String?
            let task = Task { @MainActor in
                await EbayListingPhotoExport.finishBatchArchive(
                    at: oldDirectory,
                    archive: { directory in
                        await gate.waitForRelease()
                        if fails { throw EbayListingPhotoExport.Error.emptyBatch }
                        let archive = EbayListingPhotoExport.container(of: directory).appendingPathComponent("old.zip")
                        try Data("old archive".utf8).write(to: archive)
                        return archive
                    },
                    isCurrent: { generation == 1 }
                ) { result in
                    loading = false
                    publishedDirectory = oldDirectory
                    if case let .failure(error) = result { publishedError = error.localizedDescription }
                }
            }
            await gate.waitUntilStarted()
            generation = 2
            // The native worker is allowed to finish even after cancellation.
            if cancels { task.cancel() }
            await gate.release()
            await task.value
            XCTAssertTrue(loading)
            XCTAssertEqual(publishedDirectory, newDirectory)
            XCTAssertNil(publishedError)
            XCTAssertFalse(FileManager.default.fileExists(atPath: oldDirectory.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: newDirectory.path))
        }
    }

    @MainActor
    func testCurrentArchiveFailureIsPublishedAfterCleaningItsRun() async throws {
        let directory = try EbayListingPhotoExport.makeBatchDirectory()
        var didPublish = false
        await EbayListingPhotoExport.finishBatchArchive(
            at: directory,
            archive: { _ in throw EbayListingPhotoExport.Error.emptyBatch },
            isCurrent: { true }
        ) { result in
            guard case .failure = result else { return XCTFail("Expected an archive failure") }
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
            didPublish = true
        }
        XCTAssertTrue(didPublish)
    }

    func testRepeatedPreparationPreservesFilesOwnedByAnEarlierBatchRun() async throws {
        let batch = try EbayListingPhotoExport.makeBatchDirectory()
        defer { EbayListingPhotoExport.removeRunContainer(forContentDirectory: batch) }
        let file = batch.appendingPathComponent("pending-photos-save.jpg")
        let data = Data("still owned by a save".utf8)
        try data.write(to: file)
        // A reopened screen, or another batch, shares the process lifetime.
        EbayListingPhotoExport.prepareTemporaryDirectories()
        let other = try EbayListingPhotoExport.makeBatchDirectory()
        defer { EbayListingPhotoExport.removeRunContainer(forContentDirectory: other) }
        EbayListingPhotoExport.prepareTemporaryDirectories()
        XCTAssertEqual(try Data(contentsOf: file), data)
    }
    func testNewExportPreservesPreviousFilesAndArchive() async throws {
        let data = try jpegData(for: XCTUnwrap(sourceFixture().cgImage))
        let first = try await EbayListingPhotoExport.makeListingPhotos(frontData: data, backData: data)
        defer { EbayListingPhotoExport.removeRunContainer(forContentDirectory: first.contentDirectory) }
        let archive = try await EbayListingPhotoExport.makeArchive(at: XCTUnwrap(first.contentDirectory))
        let previousFiles = try first.urls.map { try Data(contentsOf: $0) }
        let previousArchive = try Data(contentsOf: archive)
        let second = try await EbayListingPhotoExport.makeListingPhotos(frontData: data, backData: data)
        defer { EbayListingPhotoExport.removeRunContainer(forContentDirectory: second.contentDirectory) }
        XCTAssertNotEqual(first.contentDirectory, second.contentDirectory)
        XCTAssertEqual(try first.urls.map { try Data(contentsOf: $0) }, previousFiles)
        XCTAssertEqual(try Data(contentsOf: archive), previousArchive)
    }

    /// A small JPEG with identity orientation passes its full images through
    /// byte-for-byte while the four crops retain their native pixel sizes.
    func testExportPreservesAnUpOrientedJPEGFullImageAndCreatesListingOrder() async throws {
        let sourceImage = try XCTUnwrap(sourceFixture().cgImage)
        let sourceData = try jpegData(for: sourceImage)
        let output = try await EbayListingPhotoExport.makeListingPhotos(
            frontData: sourceData,
            backData: sourceData
        )
        defer {
            EbayListingPhotoExport.removeRunContainer(
                forContentDirectory: output.contentDirectory
            )
        }

        XCTAssertEqual(output.urls.count, 10)
        XCTAssertEqual(output.previews.count, 10)
        XCTAssertEqual(output.pixelDimensions.count, 10)
        XCTAssertEqual(
            output.urls.map(\.lastPathComponent),
            [
                "01-Front.jpg", "02-Front-TL.jpg", "03-Front-TR.jpg",
                "04-Front-BR.jpg", "05-Front-BL.jpg", "06-Back.jpg",
                "07-Back-TL.jpg", "08-Back-TR.jpg", "09-Back-BR.jpg",
                "10-Back-BL.jpg"
            ]
        )
        XCTAssertEqual(try Data(contentsOf: output.urls[0]), sourceData)
        XCTAssertEqual(output.pixelDimensions[0].width, 100)
        XCTAssertEqual(output.pixelDimensions[0].height, 140)
        XCTAssertEqual(output.pixelDimensions[1].width, 60)
        XCTAssertEqual(output.pixelDimensions[1].height, 84)
        XCTAssertEqual(output.pixelDimensions[6].width, 63)
        XCTAssertEqual(output.pixelDimensions[6].height, 88)
    }

    func testFilesOnlyExportMatchesPreviewExportForUprightAndRotatedSources() async throws {
        let front = try XCTUnwrap(cornerFixtureImage(width: 100, height: 140).cgImage)
        let back = try XCTUnwrap(sourceFixture().cgImage)
        for orientation in [CGImagePropertyOrientation.up, .right] {
            let frontData = try jpegData(for: front, orientation: orientation)
            let backData = try jpegData(for: back, orientation: orientation)
            let previewOutput = try await EbayListingPhotoExport.makeListingPhotos(
                frontData: frontData, backData: backData
            )
            defer { EbayListingPhotoExport.removeRunContainer(forContentDirectory: previewOutput.contentDirectory) }
            let filesOnlyOutput = try await EbayListingPhotoExport.makeListingPhotos(
                frontData: frontData, backData: backData, includePreviews: false
            )
            defer { EbayListingPhotoExport.removeRunContainer(forContentDirectory: filesOnlyOutput.contentDirectory) }

            XCTAssertEqual(previewOutput.previews.count, 10)
            for preview in previewOutput.previews {
                let image = try XCTUnwrap(preview.cgImage)
                XCTAssertGreaterThan(min(image.width, image.height), 0)
                XCTAssertLessThanOrEqual(max(image.width, image.height), EbayListingPhotoExport.previewMaximumPixelDimension)
            }
            XCTAssertTrue(filesOnlyOutput.previews.isEmpty)
            XCTAssertEqual(filesOnlyOutput.urls.count, 10)
            XCTAssertEqual(filesOnlyOutput.urls.map(\.lastPathComponent), previewOutput.urls.map(\.lastPathComponent))
            XCTAssertEqual(filesOnlyOutput.pixelDimensions, previewOutput.pixelDimensions)
            XCTAssertEqual(filesOnlyOutput.reducedQualityNames, previewOutput.reducedQualityNames)
            // Full JPEG equality covers pixels, orientation and all encoded metadata.
            XCTAssertEqual(
                try filesOnlyOutput.urls.map { try Data(contentsOf: $0) },
                try previewOutput.urls.map { try Data(contentsOf: $0) }
            )
            XCTAssertNotEqual(try Data(contentsOf: filesOnlyOutput.urls[0]), try Data(contentsOf: filesOnlyOutput.urls[5]))
        }
    }

    func testFilesOnlyFailureAndCancellationCleanOnlyTheirPartialRun() async throws {
        let data = try jpegData(for: XCTUnwrap(sourceFixture().cgImage))
        let existing = try await EbayListingPhotoExport.makeListingPhotos(frontData: data, backData: data)
        defer { EbayListingPhotoExport.removeRunContainer(forContentDirectory: existing.contentDirectory) }
        let directory = try XCTUnwrap(existing.contentDirectory)
        let archive = try await EbayListingPhotoExport.makeArchive(at: directory)
        let originalFiles = try existing.urls.map { try Data(contentsOf: $0) }
        let originalArchive = try Data(contentsOf: archive)
        let runRoot = EbayListingPhotoExport.container(of: directory).deletingLastPathComponent()
        let originalRuns = try FileManager.default.contentsOfDirectory(atPath: runRoot.path).sorted()

        // Front files are already written when decoding the invalid back fails.
        do {
            _ = try await EbayListingPhotoExport.makeListingPhotos(
                frontData: data, backData: Data(), includePreviews: false
            )
            XCTFail("Expected a back decode failure")
        } catch EbayListingPhotoExport.Error.decodeFailed(side: "back") {
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: runRoot.path).sorted(), originalRuns)

        let gate = ListingArchiveGate()
        let task = Task {
            await gate.waitForRelease()
            return try await EbayListingPhotoExport.makeListingPhotos(
                frontData: data, backData: data, includePreviews: false
            )
        }
        await gate.waitUntilStarted()
        task.cancel()
        await gate.release()
        do {
            let unexpected = try await task.value
            EbayListingPhotoExport.removeRunContainer(forContentDirectory: unexpected.contentDirectory)
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: runRoot.path).sorted(), originalRuns)
        XCTAssertEqual(try existing.urls.map { try Data(contentsOf: $0) }, originalFiles)
        XCTAssertEqual(try Data(contentsOf: archive), originalArchive)
    }

#if DEBUG
    func testFilesOnlyMidOperationCancellationRetryPreservesOwnedOutputs() async throws {
        let frontData = try jpegData(for: XCTUnwrap(cornerFixtureImage(width: 100, height: 140).cgImage))
        let backData = try jpegData(for: XCTUnwrap(sourceFixture().cgImage))
        XCTAssertNotEqual(frontData, backData)
        // Earlier export is also the retry's reference. Swap the inputs for the
        // old worker so a stale overwrite cannot accidentally match the retry.
        let earlier = try await EbayListingPhotoExport.makeListingPhotos(
            frontData: backData, backData: frontData, includePreviews: false
        )
        defer { EbayListingPhotoExport.removeRunContainer(forContentDirectory: earlier.contentDirectory) }
        let earlierDirectory = try XCTUnwrap(earlier.contentDirectory)
        let archive = try await EbayListingPhotoExport.makeArchive(at: earlierDirectory)
        let earlierBytes = try earlier.urls.map { try Data(contentsOf: $0) }
        let archiveBytes = try Data(contentsOf: archive)
        let names = [
            "01-Front.jpg", "02-Front-TL.jpg", "03-Front-TR.jpg",
            "04-Front-BR.jpg", "05-Front-BL.jpg", "06-Back.jpg",
            "07-Back-TL.jpg", "08-Back-TR.jpg", "09-Back-BR.jpg", "10-Back-BL.jpg"
        ]
        let runRoot = EbayListingPhotoExport.container(of: earlierDirectory).deletingLastPathComponent()
        let originalRuns = try FileManager.default.contentsOfDirectory(atPath: runRoot.path).sorted()
        let checkpoint = ListingFrontCheckpoint()
        let old = Task {
            try await EbayListingPhotoExport.makeListingPhotos(
                frontData: frontData, backData: backData, includePreviews: false,
                afterFrontWritten: { try checkpoint.pause(at: $0) }
            )
        }
        defer {
            old.cancel()
            checkpoint.release()
            EbayListingPhotoExport.removeRunContainer(forContentDirectory: checkpoint.contentDirectory)
        }
        await fulfillment(of: [checkpoint.reached], timeout: 10)
        let partial = try XCTUnwrap(checkpoint.contentDirectory)
        XCTAssertNotEqual(partial, earlierDirectory)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: partial.path).sorted(), Array(names.prefix(5)))
        let partialBytes = try names.prefix(5).map { try Data(contentsOf: partial.appendingPathComponent($0)) }
        XCTAssertTrue(partialBytes.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(partialBytes[0], frontData)

        old.cancel()
        // Use the real allocator: fresh UUID container, same listing filenames.
        // Finish the retry before releasing the old worker to stress late cleanup.
        let retry = try await EbayListingPhotoExport.makeListingPhotos(
            frontData: backData, backData: frontData, includePreviews: false
        )
        defer { EbayListingPhotoExport.removeRunContainer(forContentDirectory: retry.contentDirectory) }
        let retryDirectory = try XCTUnwrap(retry.contentDirectory)
        XCTAssertNotEqual(retryDirectory, partial)
        XCTAssertNotEqual(retryDirectory, earlierDirectory)
        XCTAssertEqual(retry.urls.map(\.lastPathComponent), names)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: retryDirectory.path).sorted(), names)
        XCTAssertTrue(retry.previews.isEmpty)
        let retryBytes = try retry.urls.map { try Data(contentsOf: $0) }
        XCTAssertEqual(retryBytes, earlierBytes)
        XCTAssertEqual(retryBytes[0], backData)
        XCTAssertEqual(retryBytes[5], frontData)
        for (index, data) in retryBytes.enumerated() {
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, index % 5 == 0 ? 100 : (index < 5 ? 60 : 63))
            XCTAssertEqual(image.height, index % 5 == 0 ? 140 : (index < 5 ? 84 : 88))
        }
        // The old output is still present when the complete retry is captured.
        XCTAssertEqual(try names.prefix(5).map { try Data(contentsOf: partial.appendingPathComponent($0)) }, partialBytes)
        checkpoint.release()
        do {
            let unexpected = try await old.value
            EbayListingPhotoExport.removeRunContainer(forContentDirectory: unexpected.contentDirectory)
            XCTFail("Old worker reported success after mid-operation cancellation")
        } catch is CancellationError {
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: EbayListingPhotoExport.container(of: partial).path))
        XCTAssertEqual(try retry.urls.map { try Data(contentsOf: $0) }, retryBytes)
        XCTAssertEqual(try earlier.urls.map { try Data(contentsOf: $0) }, earlierBytes)
        XCTAssertEqual(try Data(contentsOf: archive), archiveBytes)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: runRoot.path).sorted(),
            (originalRuns + [EbayListingPhotoExport.container(of: retryDirectory).lastPathComponent]).sorted()
        )
        func hashes(_ data: [Data]) -> [String] {
            data.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
        }
        let evidence = XCTAttachment(string: """
        Sequence: five front JPEGs written and checked -> cancel old -> complete retry -> release old -> CancellationError -> old container absent.
        Distinct UUID containers; identical filenames; retry reverses old front/back identities; zero previews.
        Ordered names: \(names)
        Old partial SHA256: \(hashes(partialBytes))
        Earlier files SHA256 (unchanged): \(hashes(earlierBytes))
        Earlier archive SHA256 (unchanged): \(hashes([archiveBytes]))
        Retry SHA256 (before/after old cleanup identical): \(hashes(retryBytes))
        """)
        evidence.name = "Mid-operation cancellation and retry identity evidence"
        evidence.lifetime = .keepAlways
        add(evidence)
    }
#endif

    /// A source that cannot fit the budget at 0.75 must still export, because a
    /// single oversized image previously discarded all ten outputs.
    func testOversizedSourceStepsBelowQualityPointSevenFiveInsteadOfFailing() async throws {
        let noisy = try XCTUnwrap(noiseFixture(width: 400, height: 560).cgImage)
        let data = try jpegData(for: noisy)
        let output = try await EbayListingPhotoExport.makeListingPhotos(
            frontData: data,
            backData: data,
            maximumByteCount: 20_000
        )
        defer {
            EbayListingPhotoExport.removeRunContainer(
                forContentDirectory: output.contentDirectory
            )
        }

        XCTAssertEqual(output.urls.count, 10)
        for url in output.urls {
            let written = try Data(contentsOf: url)
            XCTAssertLessThanOrEqual(
                written.count,
                20_000,
                "\(url.lastPathComponent) exceeded the export byte budget"
            )
        }
    }

    /// EXIF orientation 6 (rotate 90° CW on display) must be baked in during
    /// the single decode. If it were not, the exported crops would come from
    /// the wrong physical corners and the full image would be transposed.
    func testRotatedSourceIsUprightedBeforeCroppingAndIsNotPassedThrough() async throws {
        // 100 wide x 140 tall stored, tagged .right, so the upright image is
        // 140 wide x 100 tall.
        let stored = try XCTUnwrap(cornerFixtureImage(width: 100, height: 140).cgImage)
        let data = try jpegData(for: stored, orientation: .right)

        let output = try await EbayListingPhotoExport.makeListingPhotos(
            frontData: data,
            backData: data
        )
        defer {
            EbayListingPhotoExport.removeRunContainer(
                forContentDirectory: output.contentDirectory
            )
        }

        // The full image is transcoded, never passed through, because the
        // stored bytes are not upright.
        XCTAssertNotEqual(try Data(contentsOf: output.urls[0]), data)
        XCTAssertEqual(output.pixelDimensions[0].width, 140)
        XCTAssertEqual(output.pixelDimensions[0].height, 100)
        // 02-Front-TL is Int(140 * 0.60) x Int(100 * 0.60).
        XCTAssertEqual(output.pixelDimensions[1].width, 84)
        XCTAssertEqual(output.pixelDimensions[1].height, 60)
    }

    /// Reuses the four-corner colour fixture so the orientation test asserts on
    /// a source whose corners are individually identifiable.
    private func cornerFixtureImage(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let w = width / 3
            let h = height / 3
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            UIColor.green.setFill()
            context.fill(CGRect(x: width - w, y: 0, width: w, height: h))
            UIColor.blue.setFill()
            context.fill(CGRect(x: width - w, y: height - h, width: w, height: h))
            UIColor.yellow.setFill()
            context.fill(CGRect(x: 0, y: height - h, width: w, height: h))
        }
    }

    /// The archive expands to a readable folder name. Before the packaging
    /// change it expanded to the run's raw UUID.
    @MainActor
    func testArchiveIncludesLeadingDotBatchFolders() async throws {
        for names in [[".Card"], ["Card"], [".Card", "Card"]] {
            let directory = try EbayListingPhotoExport.makeBatchDirectory()
            defer { EbayListingPhotoExport.removeRunContainer(forContentDirectory: directory) }
            for name in names {
                let folder = directory.appendingPathComponent(name, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try Data("photo".utf8).write(to: folder.appendingPathComponent("01.jpg"))
            }
            let archive = try await EbayListingPhotoExport.makeArchive(at: directory)
            XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
            let zipped = try Data(contentsOf: archive)
            for name in names {
                XCTAssertNotNil(zipped.range(of: Data("\(name)/01.jpg".utf8)))
            }
        }
    }

    func testArchiveIsNamedForItsContentDirectoryNotTheRunUUID() async throws {
        let sourceData = try jpegData(for: try XCTUnwrap(sourceFixture().cgImage))
        let output = try await EbayListingPhotoExport.makeListingPhotos(
            frontData: sourceData,
            backData: sourceData
        )
        defer {
            EbayListingPhotoExport.removeRunContainer(
                forContentDirectory: output.contentDirectory
            )
        }

        let directory = try XCTUnwrap(output.contentDirectory)
        XCTAssertEqual(directory.lastPathComponent, EbayListingPhotoExport.archiveRootName)

        let archive = try await EbayListingPhotoExport.makeArchive(at: directory)
        XCTAssertEqual(
            archive.lastPathComponent,
            "\(EbayListingPhotoExport.archiveRootName).zip"
        )
        // The archive sits inside the run container, so one delete cleans both.
        XCTAssertEqual(
            archive.deletingLastPathComponent(),
            EbayListingPhotoExport.container(of: directory)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
    }

    /// Deleting the run container removes the content directory and the archive
    /// beside it, which is what the view relies on for cleanup.
    func testRemovingTheRunContainerAlsoRemovesTheArchive() async throws {
        let sourceData = try jpegData(for: try XCTUnwrap(sourceFixture().cgImage))
        let output = try await EbayListingPhotoExport.makeListingPhotos(
            frontData: sourceData,
            backData: sourceData
        )
        let directory = try XCTUnwrap(output.contentDirectory)
        let archive = try await EbayListingPhotoExport.makeArchive(at: directory)

        EbayListingPhotoExport.removeRunContainer(forContentDirectory: directory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: EbayListingPhotoExport.container(of: directory).path
            )
        )
    }

    /// The inspector decode is capped and keeps the source's pixel geometry.
    func testInspectionImageIsCappedOnTheLongEdge() async throws {
        let sourceData = try jpegData(for: try XCTUnwrap(sourceFixture().cgImage))
        let output = try await EbayListingPhotoExport.makeListingPhotos(
            frontData: sourceData,
            backData: sourceData
        )
        defer {
            EbayListingPhotoExport.removeRunContainer(
                forContentDirectory: output.contentDirectory
            )
        }

        let image = try await EbayListingPhotoExport.makeInspectionImage(at: output.urls[0])
        // The fixture is far below the cap, so it comes back at native size.
        XCTAssertEqual(Int(image.size.width), 100)
        XCTAssertEqual(Int(image.size.height), 140)
        XCTAssertLessThanOrEqual(
            Int(max(image.size.width, image.size.height)),
            EbayListingPhotoExport.inspectionMaximumPixelDimension
        )
    }

    private func sourceFixture() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(
            size: CGSize(width: 100, height: 140),
            format: format
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 140))
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 10, y: 10, width: 80, height: 120))
        }
    }

    private func jpegData(for image: CGImage) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                data,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func noiseFixture(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        var generator = SystemRandomNumberGenerator()
        // JPEG encodes 8×8 DCT blocks. Aligned grayscale noise keeps this
        // small fixture fast while still forcing the quality ladder to run.
        let blockSize = 8
        return UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { context in
            for y in stride(from: 0, to: height, by: blockSize) {
                for x in stride(from: 0, to: width, by: blockSize) {
                    UIColor(
                        white: CGFloat(UInt8.random(in: 0...255, using: &generator)) / 255,
                        alpha: 1
                    ).setFill()
                    context.fill(CGRect(x: x, y: y, width: blockSize, height: blockSize))
                }
            }
        }
    }

    private func jpegData(
        for image: CGImage,
        orientation: CGImagePropertyOrientation
    ) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                data,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(
            destination,
            image,
            [
                kCGImageDestinationLossyCompressionQuality: 0.95,
                kCGImagePropertyOrientation: orientation.rawValue
            ] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
