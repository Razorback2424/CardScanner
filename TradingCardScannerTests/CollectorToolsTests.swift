import XCTest
import Compression
import StoreKit
import StoreKitTest
import UIKit
@testable import TradingCardScanner

@MainActor
final class CollectorToolsTests: XCTestCase {
    private final class Client: CollectorToolsClient {
        var owned = false
        var price: String? = "€11,99"
        var fail = false
        var result: CollectorToolsPurchaseResult = .cancelled
        var purchases = 0
        var finishes: Set<UInt64> = []
        var syncs = 0
        var purchaseWait: CheckedContinuation<Void, Never>?
        var suspendPurchase = false
        var suspendOwnership = false
        var ownershipWaits: [CheckedContinuation<Bool, Never>] = []
        var continuation: AsyncStream<CollectorToolsDelivery>.Continuation?
        func loadPrice() async throws -> String? {
            if fail { throw Failure.test }
            return price
        }
        func purchase() async throws -> CollectorToolsPurchaseResult {
            purchases += 1
            if suspendPurchase { await withCheckedContinuation { purchaseWait = $0 } }
            if fail { throw Failure.test }
            if case .delivery(let delivery) = result, delivery.isVerified, delivery.isIntendedProduct { owned = true }
            return result
        }
        func currentOwnership() async -> Bool {
            if suspendOwnership {
                return await withCheckedContinuation { ownershipWaits.append($0) }
            }
            return owned
        }
        func updates() -> AsyncStream<CollectorToolsDelivery> {
            AsyncStream { continuation = $0 }
        }
        func finish(_ delivery: CollectorToolsDelivery) async { finishes.insert(delivery.id) }
        func sync() async throws { syncs += 1; if fail { throw Failure.test } }
        enum Failure: Error { case test }
    }

    func testLoadingIsDistinctAndOneCardIsAlwaysFree() async {
        let client = Client()
        let store = CollectorToolsStore(client: client)
        XCTAssertEqual(store.ownership, .loading)
        XCTAssertTrue(store.canPreparePhotos(cardCount: 1))
        XCTAssertFalse(store.canPreparePhotos(cardCount: 2))
        XCTAssertFalse(store.canUseCentering)
        await store.reconcile()
        XCTAssertEqual(store.ownership, .unowned)
        XCTAssertEqual(client.syncs, 0)
    }

    func testCancelledPendingFailedAndUnverifiedDoNotUnlock() async {
        let client = Client()
        let store = CollectorToolsStore(client: client)
        await store.reconcile()
        await store.loadProduct()
        for result in [CollectorToolsPurchaseResult.cancelled, .pending,
                       .delivery(.init(id: 1, isVerified: false, isIntendedProduct: true)),
                       .delivery(.init(id: 2, isVerified: true, isIntendedProduct: false))] {
            client.result = result
            await store.purchase()
            XCTAssertFalse(store.isOwned)
            XCTAssertFalse(store.canUseCentering)
            XCTAssertTrue(store.canPreparePhotos(cardCount: 1))
        }
        client.fail = true
        await store.purchase()
        XCTAssertFalse(store.isOwned)
        XCTAssertNotNil(store.message)
        XCTAssertTrue(client.finishes.isEmpty)
    }

    func testPurchaseUnlocksBothToolsAndDuplicateDeliveryCannotRestoreRevokedOwnership() async {
        let client = Client()
        let store = CollectorToolsStore(client: client)
        await store.reconcile()
        await store.loadProduct()
        store.start()
        let delivery = CollectorToolsDelivery(id: 7, isVerified: true, isIntendedProduct: true)
        client.result = .delivery(delivery)
        await store.purchase()
        XCTAssertTrue(store.canUseCentering)
        XCTAssertTrue(store.canPreparePhotos(cardCount: 12))
        XCTAssertEqual(client.finishes, [7])
        await store.purchase()
        XCTAssertEqual(client.purchases, 1)
        client.owned = false
        client.continuation?.yield(delivery)
        for _ in 0..<30 { await Task.yield() }
        XCTAssertFalse(store.isOwned)
        XCTAssertEqual(client.finishes, [7])
        XCTAssertTrue(store.canPreparePhotos(cardCount: 1))
    }

    func testRestoreRelaunchAndProductFailureAreIndependent() async {
        let client = Client()
        client.owned = true
        let store = CollectorToolsStore(client: client)
        await store.reconcile()
        await store.loadProduct()
        XCTAssertEqual(store.displayPrice, "€11,99")
        client.fail = true
        await store.loadProduct()
        XCTAssertNil(store.displayPrice)
        XCTAssertTrue(store.isOwned)
        await store.restore()
        XCTAssertTrue(store.isOwned)
        client.fail = false
        let relaunched = CollectorToolsStore(client: client)
        await relaunched.restore()
        XCTAssertTrue(relaunched.isOwned)
        XCTAssertEqual(client.syncs, 2)
        client.owned = false
        await relaunched.reconcile()
        XCTAssertFalse(relaunched.isOwned)
    }

    func testOverlappingPurchaseRequestsAreIgnored() async {
        let client = Client()
        client.suspendPurchase = true
        let store = CollectorToolsStore(client: client)
        await store.reconcile()
        await store.loadProduct()
        let first = Task { await store.purchase() }
        while client.purchaseWait == nil { await Task.yield() }
        await store.purchase()
        await store.restore()
        XCTAssertEqual(client.purchases, 1)
        XCTAssertEqual(client.syncs, 0)
        client.purchaseWait?.resume()
        await first.value
        XCTAssertFalse(store.isBusy)
    }

    func testShareFileDeliveryRechecksOwnershipAndKeepsSingleCardFree() async throws {
        let client = Client()
        let store = CollectorToolsStore(client: client)
        let url = URL(fileURLWithPath: "/tmp/example.zip")
        let batch = CollectorToolsPhotoArchive(url: url, cardCount: 2)
        let single = CollectorToolsPhotoArchive(url: url, cardCount: 1)
        XCTAssertEqual(try single.authorizedURL(using: store), url)
        XCTAssertThrowsError(try batch.authorizedURL(using: store))
        client.owned = true
        await store.reconcile()
        XCTAssertEqual(try batch.authorizedURL(using: store), url)
        client.owned = false
        await store.reconcile()
        XCTAssertThrowsError(try batch.authorizedURL(using: store))
        XCTAssertEqual(try single.authorizedURL(using: store), url)
    }

    func testOlderOwnershipSnapshotCannotOverrideCompletedRevocation() async {
        let client = Client()
        client.suspendOwnership = true
        let store = CollectorToolsStore(client: client)
        let older = Task { await store.reconcile() }
        while client.ownershipWaits.count < 1 { await Task.yield() }
        let newer = Task { await store.reconcile() }
        while client.ownershipWaits.count < 2 { await Task.yield() }
        client.ownershipWaits[1].resume(returning: false)
        await newer.value
        XCTAssertEqual(store.ownership, .unowned)
        client.ownershipWaits[0].resume(returning: true)
        await older.value
        XCTAssertEqual(store.ownership, .unowned)
    }

    /// Real local StoreKit, with no App Store Connect or live purchase involved.
    func testLocalStoreKitPurchaseStoreReconstructionRestoreRefundAndPhotoZIP() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "CollectorTools", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let store = CollectorToolsStore()
        await store.reconcile()
        await store.loadProduct()
        store.start()
        XCTAssertFalse(store.isOwned)
        _ = try XCTUnwrap(store.displayPrice, "Local StoreKit must return a product before purchase/restore acceptance")
        let products = try await Product.products(for: [CollectorToolsStore.productID])
        XCTAssertEqual(store.displayPrice, products.first?.displayPrice)
        let product = try XCTUnwrap(products.first, "Check the scheme's local StoreKit configuration")
        XCTAssertEqual(product.price, Decimal(string: "9.99"))
        await store.purchase()
        XCTAssertTrue(store.canUseCentering)
        XCTAssertTrue(store.canPreparePhotos(cardCount: 2))

        let (directory, archive) = try await makeValidatedPhotoZIP()
        defer { EbayListingPhotoExport.removeRunContainer(forContentDirectory: directory) }
        let reconstructed = CollectorToolsStore()
        await reconstructed.reconcile()
        XCTAssertTrue(reconstructed.isOwned)
        await reconstructed.restore()
        XCTAssertTrue(reconstructed.isOwned)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: transaction.identifier)
        for _ in 0..<100 {
            if !store.isOwned { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertFalse(store.isOwned)
        XCTAssertTrue(store.canPreparePhotos(cardCount: 1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
    }

    func testPhotoZIPExtractsExactlyTwentyDecodableJPEGs() async throws {
        let (directory, _) = try await makeValidatedPhotoZIP()
        EbayListingPhotoExport.removeRunContainer(forContentDirectory: directory)
    }

    private func makeValidatedPhotoZIP() async throws -> (URL, URL) {
        // Use the existing full-resolution exporter with a representative two-card pack.
        let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1260)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 1260))
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.95))
        let directory = try EbayListingPhotoExport.makeBatchDirectory()
        var completed = false
        defer { if !completed { EbayListingPhotoExport.removeRunContainer(forContentDirectory: directory) } }
        for name in ["Card-01", "Card-02"] {
            let output = try await EbayListingPhotoExport.makeListingPhotos(frontData: data, backData: data)
            try await EbayListingPhotoExport.moveOutput(output, to: directory.appendingPathComponent(name))
        }
        var archive: URL?
        await EbayListingPhotoExport.finishBatchArchive(at: directory, isCurrent: { true }) { result in
            archive = try? result.get()
        }
        let zip = try Data(contentsOf: XCTUnwrap(archive))
        let extracted = try extractPhotoZIP(zip)
        let filenames = ["01-Front.jpg", "02-Front-TL.jpg", "03-Front-TR.jpg", "04-Front-BR.jpg",
                         "05-Front-BL.jpg", "06-Back.jpg", "07-Back-TL.jpg", "08-Back-TR.jpg",
                         "09-Back-BR.jpg", "10-Back-BL.jpg"]
        let root = EbayListingPhotoExport.archiveRootName
        let expectedFiles = ["Card-01", "Card-02"].flatMap { card in filenames.map { "\(root)/\(card)/\($0)" } }
        XCTAssertEqual(extracted.keys.sorted(), expectedFiles.sorted())
        XCTAssertEqual(extracted.count, 20)
        for name in expectedFiles {
            let bytes = try XCTUnwrap(extracted[name])
            let decoded = try XCTUnwrap(UIImage(data: bytes)?.cgImage, "Archived JPEG must decode: \(name)")
            XCTAssertGreaterThan(decoded.width, 0)
            XCTAssertGreaterThan(decoded.height, 0)
            XCTAssertEqual(bytes, try Data(contentsOf: directory.deletingLastPathComponent().appendingPathComponent(name)))
        }
        let result = try XCTUnwrap(archive)
        completed = true
        return (directory, result)
    }

    /// Bounded test reader for the platform exporter's ordinary ZIP format.
    /// Central-directory sizes also handle local headers using data descriptors.
    private func extractPhotoZIP(_ data: Data) throws -> [String: Data] {
        func integer(_ offset: Int, _ count: Int) throws -> Int {
            guard offset >= 0, count <= data.count, offset <= data.count - count else { throw Client.Failure.test }
            return (0..<count).reduce(0) { $0 | Int(data[offset + $1]) << (8 * $1) }
        }
        let end = try XCTUnwrap(stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1)
            .first { (try? integer($0, 4)) == 0x06054b50 })
        let count = try integer(end + 10, 2)
        var cursor = try integer(end + 16, 4)
        var result: [String: Data] = [:]
        for _ in 0..<count {
            XCTAssertEqual(try integer(cursor, 4), 0x02014b50)
            let method = try integer(cursor + 10, 2)
            let compressedCount = try integer(cursor + 20, 4)
            let expandedCount = try integer(cursor + 24, 4)
            let nameCount = try integer(cursor + 28, 2)
            let extraCount = try integer(cursor + 30, 2)
            let commentCount = try integer(cursor + 32, 2)
            let local = try integer(cursor + 42, 4)
            guard cursor + 46 + nameCount <= data.count, expandedCount <= 12_000_000 else { throw Client.Failure.test }
            let name = try XCTUnwrap(String(data: data.subdata(in: cursor + 46..<cursor + 46 + nameCount), encoding: .utf8))
            XCTAssertNil(result[name], "Duplicate archive entry")
            XCTAssertEqual(try integer(local, 4), 0x04034b50)
            let start = try local + 30 + integer(local + 26, 2) + integer(local + 28, 2)
            guard start >= 0, start + compressedCount <= data.count else { throw Client.Failure.test }
            let compressed = data.subdata(in: start..<start + compressedCount)
            let bytes: Data
            if method == 0 {
                bytes = compressed
            } else if method == 8 && expandedCount > 0 {
                var output = [UInt8](repeating: 0, count: expandedCount)
                let decoded = compressed.withUnsafeBytes { source in
                    compression_decode_buffer(&output, expandedCount,
                        source.bindMemory(to: UInt8.self).baseAddress!, compressedCount, nil, COMPRESSION_ZLIB)
                }
                XCTAssertEqual(decoded, expandedCount)
                bytes = Data(output)
            } else { throw Client.Failure.test }
            XCTAssertEqual(bytes.count, expandedCount)
            result[name] = bytes
            cursor += 46 + nameCount + extraCount + commentCount
        }
        return result
    }
}
