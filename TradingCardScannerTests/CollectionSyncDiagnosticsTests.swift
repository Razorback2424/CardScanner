import Foundation
import XCTest
@testable import TradingCardScanner

final class CollectionSyncDiagnosticsTests: XCTestCase {
    private let digest = CollectionStoreDigest(
        formatVersion: 1,
        storeIDSuffix: "eeeeeeee",
        collectedCardCount: 3,
        totalQuantity: 4,
        priceRecordCount: 2,
        productIdentityCount: 1,
        collectionActivityCount: 5,
        inventoryEventCount: 5,
        materialSHA256: String(repeating: "a", count: 64)
    )

    func testDiagnosticsJSONRoundTripsTypedFacts() throws {
        let snapshot = CloudSyncDiagnosticsSnapshot(
            schemaVersion: 1,
            appVersion: "1.0",
            buildNumber: "1",
            osVersion: "iOS test",
            deviceClass: "iPhone",
            storageModeRaw: CollectionStorageMode.cloudKit.rawValue,
            cloudAccountStatusRaw: "available",
            attachmentStateRaw: CloudAttachmentState.attached.rawValue,
            storeIDSuffix: "eeeeeeee",
            digest: digest,
            lastBootstrapErrorCategory: "none",
            generatedAt: Date(timeIntervalSince1970: 10)
        )

        let data = try CollectionStoreDigester.redactedJSON(for: snapshot)
        let decoded = try JSONDecoder().decode(CloudSyncDiagnosticsSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testDiagnosticsJSONContainsOnlyRedactedFacts() throws {
        let snapshot = CloudSyncDiagnosticsSnapshot(
            schemaVersion: 1,
            appVersion: "1.0",
            buildNumber: "1",
            osVersion: "iOS test",
            deviceClass: "iPhone",
            storageModeRaw: CollectionStorageMode.onDevice.rawValue,
            cloudAccountStatusRaw: "noAccount",
            attachmentStateRaw: CloudAttachmentState.suspended.rawValue,
            storeIDSuffix: "eeeeeeee",
            digest: digest,
            lastBootstrapErrorCategory: "account-conflict",
            generatedAt: Date(timeIntervalSince1970: 10)
        )
        let json = String(
            data: try CollectionStoreDigester.redactedJSON(for: snapshot),
            encoding: .utf8
        )!

        for forbidden in [
            "Eevee",
            "Prismatic Evolutions",
            "074",
            "certification-number",
            "raw-record-name",
            "iCloud.com.seankeller.CardScanner",
            "vendor-key",
            "artwork.jpg",
            "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        ] {
            XCTAssertFalse(json.contains(forbidden), "diagnostics leaked \(forbidden)")
        }
        XCTAssertTrue(json.contains("materialSHA256"))
        XCTAssertTrue(json.contains("eeeeeeee"))
    }

    func testDiagnosticsDoNotUseFullStoreIdentity() throws {
        let json = String(
            data: try CollectionStoreDigester.redactedJSON(for: CloudSyncDiagnosticsSnapshot(
                schemaVersion: 1,
                appVersion: "1.0",
                buildNumber: "1",
                osVersion: "test",
                deviceClass: "iPad",
                storageModeRaw: "onDevice",
                cloudAccountStatusRaw: "restricted",
                attachmentStateRaw: "suspended",
                storeIDSuffix: "12345678",
                digest: digest,
                lastBootstrapErrorCategory: nil,
                generatedAt: .now
            )),
            encoding: .utf8
        )!
        XCTAssertTrue(json.contains("12345678"))
        XCTAssertFalse(json.contains("\"storeID\""))
    }
}
