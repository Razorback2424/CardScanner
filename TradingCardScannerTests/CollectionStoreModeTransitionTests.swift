import Foundation
import SwiftData
import XCTest

#if canImport(SQLite3)
import SQLite3
#endif

@testable import TradingCardScanner

/// Permanent disk-backed evidence for the fact that the collection store is
/// the same SQLite identity when SwiftData mirroring is toggled. The test is
/// intentionally separate from policy tests: policy must not claim a safe
/// local transition until these bytes have survived the real close/reopen
/// boundaries.
@MainActor
final class CollectionStoreModeTransitionTests: XCTestCase {
    private let storeID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let fixedDate = Date(timeIntervalSinceReferenceDate: 1234)

    private struct TestStore {
        let rootURL: URL
        let paths: CollectionStoragePaths
        let manifestStore: CollectionStoreManifestStore
    }

    private func makeStore() throws -> TestStore {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(
                "CardScannerModeTransitionTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let collectionDirectory = rootURL.appendingPathComponent(
            "CollectionStorage",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: collectionDirectory,
            withIntermediateDirectories: true
        )
        let paths = CollectionStoragePaths(
            applicationSupportURL: rootURL,
            collectionStorageDirectoryURL: collectionDirectory,
            structuredStoreURL: collectionDirectory.appendingPathComponent(
                "CardScannerCollection.store"
            ),
            portfolioStoreURL: collectionDirectory.appendingPathComponent(
                "PortfolioLocal.store"
            )
        )
        return TestStore(
            rootURL: rootURL,
            paths: paths,
            manifestStore: CollectionStoreManifestStore(
                directoryURL: collectionDirectory
            )
        )
    }

    private func open(
        _ store: TestStore,
        mode: CollectionStorageMode
    ) throws -> ModelContainer {
        try CollectionStorageBootstrapDependencies.makeContainer(
            paths: store.paths,
            mode: mode
        )
    }

    private func seed(
        _ store: TestStore,
        label: String = "baseline",
        quantity: Int = 2,
        mode: CollectionStorageMode = .onDevice
    ) throws {
        do {
            let container = try open(store, mode: mode)
            try insertFixture(
                in: container.mainContext,
                label: label,
                quantity: quantity
            )
        }
    }

    private func insertFixture(
        in context: ModelContext,
        label: String,
        quantity: Int
    ) throws {
        let prefix = "a4-\(label.lowercased())"
        let card = CollectedCard(
            collectionKey: "\(prefix):pokemon:001:normal",
            game: .pokemon,
            providerID: "\(prefix)-card",
            name: "A4 fixture \(label)",
            setName: "A4 test set",
            setCode: "A4",
            cardNumber: "001",
            rarity: "Common",
            imageURL: nil,
            thumbnailURL: nil,
            variant: .normal,
            variantResolution: .uniqueInCatalog,
            quantity: quantity,
            dateAdded: fixedDate
        )
        let price = PriceRecord(
            key: "\(prefix)-price",
            game: .pokemon,
            printingID: "\(prefix)-printing",
            variantID: PhysicalVariant.normal.id
        )
        price.unitMarketPriceUSD = 4.25
        price.currencyCode = "USD"
        price.fetchedAt = fixedDate
        let identity = ProductIdentity(
            key: price.key,
            vendor: .justTCG,
            vendorCardID: "\(prefix)-vendor-card",
            vendorVariantID: "\(prefix)-vendor-variant",
            resolvedAt: fixedDate
        )
        let activity = CollectionActivity(
            card: card,
            source: .scan,
            quantity: quantity,
            occurredAt: fixedDate
        )
        let event = InventoryEvent(
            operationID: UUID(),
            leg: nil,
            kind: .acquire,
            source: .scan,
            collectionKey: card.collectionKey,
            priceStorageKey: price.key,
            deltaQuantity: quantity,
            occurredAt: fixedDate,
            recordedAt: fixedDate,
            valuation: .unpriced
        )
        for row in [card, price, identity, activity, event] as [any PersistentModel] {
            context.insert(row)
        }
        try context.save()
    }

    private func digest(_ store: TestStore, mode: CollectionStorageMode) throws -> CollectionStoreDigest {
        do {
            let container = try open(store, mode: mode)
            return try CollectionStoreDigester.make(
                in: container.mainContext,
                storeID: storeID
            )
        }
    }

    private func privateOpenError(_ store: TestStore) -> String? {
        do {
            do {
                _ = try open(store, mode: .cloudKit)
            }
            return nil
        } catch {
            return String(describing: error)
        }
    }

    private func requirePrivateMode(_ store: TestStore) throws {
        if let error = privateOpenError(store) {
            print("A4 private-mode prerequisite unavailable: \(error)")
            throw XCTSkip("CloudKit-backed ModelContainer is unavailable in this build: \(error)")
        }
    }

    private func digestSummary(_ digest: CollectionStoreDigest) -> String {
        "cards=\(digest.collectedCardCount), quantity=\(digest.totalQuantity), "
            + "prices=\(digest.priceRecordCount), identities=\(digest.productIdentityCount), "
            + "activities=\(digest.collectionActivityCount), events=\(digest.inventoryEventCount), "
            + "materialSHA256=\(digest.materialSHA256)"
    }

    private func sqliteURL(for url: URL) -> URL {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return url
        }
        guard isDirectory.boolValue,
              let enumerator = fileManager.enumerator(
                  at: url,
                  includingPropertiesForKeys: [.isRegularFileKey]
              ) else {
            return url
        }
        for case let childURL as URL in enumerator {
            if (try? childURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                return childURL
            }
        }
        return url
    }

    private func artifactByteCount(for url: URL) -> UInt64 {
        let fileManager = FileManager.default
        let candidates = [
            url,
            URL(fileURLWithPath: "\(url.path)-wal"),
            URL(fileURLWithPath: "\(url.path)-shm")
        ]
        var total: UInt64 = 0
        for candidate in candidates {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                guard let enumerator = fileManager.enumerator(
                    at: candidate,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
                ) else { continue }
                for case let childURL as URL in enumerator {
                    guard let values = try? childURL.resourceValues(
                        forKeys: [.isRegularFileKey, .fileSizeKey]
                    ),
                    values.isRegularFile == true,
                    let size = values.fileSize else { continue }
                    total += UInt64(size)
                }
            } else if let size = try? fileManager.attributesOfItem(atPath: candidate.path)[.size] as? NSNumber {
                total += size.uint64Value
            }
        }
        return total
    }

    private func tableNames(for url: URL) -> [String] {
#if canImport(SQLite3)
        let sqliteURL = sqliteURL(for: url)
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            sqliteURL.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        ) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            return []
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let value = sqlite3_column_text(statement, 0) {
                names.append(String(cString: value))
            }
        }
        return names
#else
        return []
#endif
    }

    func testS0CloudKitPrivateConfigurationOutcomeIsRecorded() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }

        if let error = privateOpenError(store) {
            print("A4 S0: .private ModelContainer threw: \(error)")
#if !LOCAL_ONLY_SIGNING
            XCTFail("DebugProduction must construct the .private ModelContainer: \(error)")
#endif
        } else {
            print("A4 S0: .private ModelContainer succeeded without an iCloud account")
#if LOCAL_ONLY_SIGNING
            XCTFail("LOCAL_ONLY_SIGNING must not construct a CloudKit-backed ModelContainer")
#endif
        }
    }

    func testS1PrivateModeRecordsSchemaAndByteDeltaWithoutChangingFixture() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        try seed(store)

        let beforeTables = tableNames(for: store.paths.structuredStoreURL)
        let beforeBytes = artifactByteCount(for: store.paths.structuredStoreURL)
        let beforeDigest = try digest(store, mode: .onDevice)
        try requirePrivateMode(store)
        let afterDigest = try digest(store, mode: .cloudKit)
        let afterTables = tableNames(for: store.paths.structuredStoreURL)
        let afterBytes = artifactByteCount(for: store.paths.structuredStoreURL)
        XCTAssertEqual(afterDigest, beforeDigest)
        print(
            "A4 S1: beforeTables=\(beforeTables.isEmpty ? "<unavailable>" : beforeTables.joined(separator: ",")); "
                + "afterTables=\(afterTables.isEmpty ? "<unavailable>" : afterTables.joined(separator: ",")); "
                + "bytes=\(beforeBytes)->\(afterBytes); "
                + "beforeDigest=\(digestSummary(beforeDigest)); "
                + "afterDigest=\(digestSummary(afterDigest))"
        )
    }

    func testS2PrivateToNonePreservesDigestExactly() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        try seed(store)
        let before = try digest(store, mode: .onDevice)
        try requirePrivateMode(store)
        do { _ = try open(store, mode: .cloudKit) }
        let after = try digest(store, mode: .onDevice)
        XCTAssertEqual(after, before)
        print("A4 S2: before=\(digestSummary(before)); after=\(digestSummary(after))")
    }

    func testS3NoneToNoneAcrossClosePreservesDigestExactly() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        try seed(store)
        let before = try digest(store, mode: .onDevice)
        let after = try digest(store, mode: .onDevice)
        XCTAssertEqual(after, before)
        print("A4 S3: digest=\(digestSummary(after))")
    }

    func testS4NonePrivateNoneRoundTripPreservesDigestAtEveryBoundary() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        try seed(store)
        let before = try digest(store, mode: .onDevice)
        try requirePrivateMode(store)
        let duringPrivate = try digest(store, mode: .cloudKit)
        let after = try digest(store, mode: .onDevice)
        XCTAssertEqual(duringPrivate, before)
        XCTAssertEqual(after, before)
        print(
            "A4 S4: noneBefore=\(digestSummary(before)); "
                + "private=\(digestSummary(duringPrivate)); "
                + "noneAfter=\(digestSummary(after))"
        )
    }

    func testS5ModeRoundTripPreservesPathAndStoreFileIdentity() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        try seed(store)
        let originalPath = store.paths.structuredStoreURL.standardizedFileURL
        let beforeIdentity = try store.manifestStore.ensureStoreFileIdentity()
        let beforeDigest = try digest(store, mode: .onDevice)
        try requirePrivateMode(store)
        let privateDigest = try digest(store, mode: .cloudKit)
        let afterDigest = try digest(store, mode: .onDevice)
        let afterIdentity = try store.manifestStore.ensureStoreFileIdentity()
        XCTAssertEqual(store.paths.structuredStoreURL.standardizedFileURL, originalPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalPath.path))
        XCTAssertEqual(afterIdentity, beforeIdentity)
        XCTAssertEqual(privateDigest, beforeDigest)
        XCTAssertEqual(afterDigest, beforeDigest)
        print(
            "A4 S5: identity=\(beforeIdentity); "
                + "noneBefore=\(digestSummary(beforeDigest)); "
                + "private=\(digestSummary(privateDigest)); "
                + "noneAfter=\(digestSummary(afterDigest))"
        )
    }

    func testS6WritesInBothModesSurviveTheTransition() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        try seed(store, label: "A", quantity: 2, mode: .onDevice)
        do {
            let container = try open(store, mode: .cloudKit)
            try insertFixture(in: container.mainContext, label: "B", quantity: 3)
        } catch {
            print("A4 S6: .private write unavailable: \(error)")
            throw XCTSkip("CloudKit-backed ModelContainer is unavailable in this build: \(error)")
        }
        let final = try digest(store, mode: .onDevice)
        XCTAssertEqual(final.collectedCardCount, 2)
        XCTAssertEqual(final.totalQuantity, 5)
        XCTAssertEqual(final.priceRecordCount, 2)
        XCTAssertEqual(final.productIdentityCount, 2)
        XCTAssertEqual(final.collectionActivityCount, 2)
        XCTAssertEqual(final.inventoryEventCount, 2)
        print("A4 S6: final=\(digestSummary(final))")
    }
}
