import Foundation
import XCTest
@testable import TradingCardScanner

final class PrivacyAndSupportSurfaceTests: XCTestCase {
    func testConfiguredURLRequiresHTTPSAndTheExpectedPath() {
        let privacy = CardScannerExternalLinks.configuredURL(
            forInfoKey: "PrivacyPolicyURL",
            requiredPath: "/privacy",
            infoDictionary: ["PrivacyPolicyURL": "https://cards.example/privacy"]
        )
        XCTAssertNil(privacy, "placeholder hosts must not pass the release gate")

        let valid = CardScannerExternalLinks.configuredURL(
            forInfoKey: "PrivacyPolicyURL",
            requiredPath: "/privacy",
            infoDictionary: ["PrivacyPolicyURL": "https://cardscanner.test/privacy"]
        )
        XCTAssertEqual(valid?.scheme, "https")
        XCTAssertEqual(valid?.path, "/privacy")
    }

    func testSupportPathIsValidated() {
        XCTAssertNil(CardScannerExternalLinks.configuredURL(
            forInfoKey: "SupportURL",
            requiredPath: "/support",
            infoDictionary: ["SupportURL": "http://cardscanner.test/support"]
        ))
        XCTAssertNil(CardScannerExternalLinks.configuredURL(
            forInfoKey: "SupportURL",
            requiredPath: "/support",
            infoDictionary: ["SupportURL": "https://cardscanner.test/contact"]
        ))
    }

    func testExactDeviceLocalArtworkDisclosureIsStable() throws {
        let source = try String(
            contentsOf: sourceURL(
                "TradingCardScanner/Views/PrivacyAndSupportSettingsView.swift",
                relativeTo: #filePath
            ),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains(
            "Custom artwork is stored on this device and is not currently synced with iCloud."
        ))
        XCTAssertTrue(source.contains("Value History"))
        XCTAssertTrue(source.contains("removes its card records and current ownership"))
        XCTAssertTrue(source.contains("Removal activity, price records, and Value History remain on this device."))
        XCTAssertFalse(source.contains("removes its local card records and history"))
    }

    func testPrivacyManifestCarriesBothRequiredReasonCategories() throws {
        let source = try String(
            contentsOf: sourceURL(
                "TradingCardScanner/PrivacyInfo.xcprivacy",
                relativeTo: #filePath
            ),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("NSPrivacyAccessedAPICategoryUserDefaults"))
        XCTAssertTrue(source.contains("CA92.1"))
        XCTAssertTrue(source.contains("NSPrivacyAccessedAPICategoryFileTimestamp"))
        XCTAssertTrue(source.contains("C617.1"))
    }

    func testSettingsDoesNotContainLegacyAccountProxyCopy() throws {
        let source = try String(
            contentsOf: sourceURL(
                "TradingCardScanner/Views/ScannerSettingsView.swift",
                relativeTo: #filePath
            ),
            encoding: .utf8
        )
        XCTAssertFalse(source.contains("SignInWithApple"))
        XCTAssertFalse(source.contains("AppleAccountCredentials"))
        XCTAssertFalse(source.contains("AuthenticationServices"))
    }

    func testCollectionStorageStatusDistinguishesTransientLocalFallback() throws {
        let source = try String(
            contentsOf: sourceURL(
                "TradingCardScanner/Views/ScannerSettingsView.swift",
                relativeTo: #filePath
            ),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("iCloud account"))
        XCTAssertTrue(source.contains("Attachment"))
        XCTAssertTrue(source.contains("Temporarily unavailable"))
        XCTAssertTrue(source.contains("visibly unverified for syncing"))
    }

    private func sourceURL(_ relativePath: String, relativeTo testFilePath: String) -> URL {
        URL(fileURLWithPath: testFilePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
    }
}
