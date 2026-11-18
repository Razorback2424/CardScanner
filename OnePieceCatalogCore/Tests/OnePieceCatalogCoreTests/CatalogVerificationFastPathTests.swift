import Foundation
import XCTest
@testable import OnePieceCatalogCore

/// The launch-time fast paths must never change what verification accepts.
/// Each is checked against the formatter/string implementation it replaced.
final class CatalogVerificationFastPathTests: XCTestCase {
    private func formatterAccepts(_ value: String) -> Bool {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return plain.date(from: value) != nil || fractional.date(from: value) != nil
    }

    func testTimestampFastPathOnlyConfirmsWhatFormattersAccept() {
        let accepted = [
            "2026-11-15T00:38:45Z", "2026-11-15T00:38:45.123Z", "2026-11-15T00:38:45.123456Z",
            "2026-11-15T00:38:45+09:00", "2026-11-15T00:38:45.123456-07:00", "2024-02-29T23:59:59Z",
            "2000-02-29T00:00:00Z", "1970-01-01T00:00:00Z", "2026-12-31T23:59:59+14:00",
        ]
        for value in accepted {
            XCTAssertTrue(OnePieceTimestampFastPath.isCertainlyValid(value), value)
            XCTAssertTrue(formatterAccepts(value), value)
        }
        let unrecognised = [
            "", "2026-11-15", "2026-11-15T00:38:45", "2026-11-15 00:38:45Z", "2026-13-15T00:38:45Z",
            "2026-02-29T00:00:00Z", "1900-02-29T00:00:00Z", "2026-04-31T00:00:00Z", "2026-11-15T24:00:00Z",
            "2026-11-15T00:60:00Z", "2026-11-15T00:00:60Z", "2026-11-15T00:38:45.Z", "2026-11-15T00:38:45.1Z",
            "2026-11-15T00:38:45.1234567890Z", "2026-11-15T00:38:45+0900", "2026-11-15T00:38:45+15:00",
            "2026-11-15T00:38:45Zjunk", "２０２６-11-15T00:38:45Z", "2026-11-15t00:38:45z", "1969-12-31T23:59:59Z",
        ]
        for value in unrecognised {
            XCTAssertFalse(OnePieceTimestampFastPath.isCertainlyValid(value), value)
        }
    }

    func testTimestampFastPathAgreesWithFormattersOnBundledRelease() throws {
        let release = try bundledSeedRelease()
        var checked = Set<String>()
        for value in release.observations.map(\.observedAt) + [release.generatedAt] where checked.insert(value).inserted {
            if OnePieceTimestampFastPath.isCertainlyValid(value) {
                XCTAssertTrue(formatterAccepts(value), value)
            }
        }
        XCTAssertGreaterThan(checked.count, 1_000)
    }

    /// The implementation `decode` replaced, kept verbatim as the oracle.
    private func referenceDecode(_ value: String) -> Data? {
        func encode(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        guard !value.isEmpty, value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return nil }
        let base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padded = base64 + String(repeating: "=", count: (4 - base64.utf8.count % 4) % 4)
        guard let data = Data(base64Encoded: padded), encode(data) == value else { return nil }
        return data
    }

    func testBase64URLDecodeMatchesReferenceImplementation() {
        var cases = ["", "A", "AA", "AB", "AAA", "AAB", "AAAA", "-_-_", "_w", "_x", "__8", "__9", "AQID", "AQI",
                     "AQ", "AQ==", "AQ=", "A+/B", "A B", "Zm9v\n", "Zm9vYg", "Zm9vYmE", "Zm9vYmFy", "é", "Zm9v=="]
        var generator = SystemRandomNumberGenerator()
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        for length in 0..<40 {
            let bytes = (0..<length).map { _ in UInt8.random(in: 0...255, using: &generator) }
            cases.append(Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: ""))
            cases.append(String((0..<length).map { _ in alphabet.randomElement(using: &generator)! }))
        }
        for value in cases {
            XCTAssertEqual(OnePieceCatalogSignature.decode(value), referenceDecode(value), "\(value)")
        }
    }

    func testBase64URLDecodeMatchesReferenceOnBundledPayload() throws {
        let envelope = try bundledSeedEnvelope()
        XCTAssertEqual(OnePieceCatalogSignature.decode(envelope.payload), referenceDecode(envelope.payload))
        XCTAssertNotNil(OnePieceCatalogSignature.decode(envelope.payload))
    }

    private func bundledSeedEnvelope() throws -> OnePieceCatalogReleaseEnvelope {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TradingCardScanner/OnePieceCatalogSeed/one-piece-catalog-release.json")
        return try JSONDecoder().decode(OnePieceCatalogReleaseEnvelope.self, from: Data(contentsOf: url))
    }

    private func bundledSeedRelease() throws -> OnePieceCatalogRelease {
        let payload = try XCTUnwrap(OnePieceCatalogSignature.decode(try bundledSeedEnvelope().payload))
        return try JSONDecoder().decode(OnePieceCatalogRelease.self, from: payload)
    }
}
