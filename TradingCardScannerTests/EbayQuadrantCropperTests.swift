import XCTest
import CoreGraphics
import ImageIO
import UIKit
import UniformTypeIdentifiers
@testable import TradingCardScanner

final class EbayQuadrantCropperTests: XCTestCase {
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

final class EbayListingPhotoExportTests: XCTestCase {
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
