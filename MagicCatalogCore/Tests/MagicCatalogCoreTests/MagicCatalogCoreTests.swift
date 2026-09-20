import CryptoKit
import Foundation
import XCTest
@testable import MagicCatalogCore

final class MagicCatalogCoreTests: XCTestCase {
    private func fixture() throws -> MagicCatalogProviderFixture {
        let url = Bundle.module.url(
            forResource: "recorded-provider",
            withExtension: "json"
        )!
        return try MagicCatalogJSON.decode(
            MagicCatalogProviderFixture.self,
            from: Data(contentsOf: url)
        )
    }

    private func build(
        fixture: MagicCatalogProviderFixture? = nil,
        active: MagicCatalogRelease? = nil,
        generatedAt: String = "2026-01-01T00:00:00.000Z",
        revision: Int = 1
    ) throws -> MagicCatalogBuildResult {
        try MagicCatalogBuilder().build(
            MagicCatalogBuildRequest(
                fixture: fixture ?? self.fixture(),
                activeRelease: active,
                revision: revision,
                generatedAt: generatedAt
            )
        )
    }

    func testThreePoliciesProduceIndependentProjections() throws {
        let result = try build()
        let byCode = Dictionary(result.release.sets.map { ($0.code, $0) }) { first, _ in first }

        XCTAssertEqual(byCode["ABC"]?.scanEnabled, true)
        XCTAssertEqual(byCode["ABC"]?.browseEnabled, true)
        XCTAssertEqual(byCode["OLD"]?.scanEnabled, false)
        XCTAssertEqual(byCode["OLD"]?.browseEnabled, true)
        XCTAssertEqual(byCode["TABC"]?.routingKind, .token)
        XCTAssertEqual(byCode["AABC"]?.routingKind, .artCard)
        XCTAssertEqual(byCode["TABC"]?.browseEnabled, false)
        XCTAssertEqual(byCode["TABC"]?.scanEnabled, false)
        XCTAssertNil(byCode["DGT"])
        XCTAssertEqual(result.report.scannerProjectionChangedCodes, ["ABC"])
        XCTAssertEqual(result.report.browseProjectionChangedCodes, ["ABC", "OLD"])
        XCTAssertEqual(result.report.routingProjectionChangedCodes, ["AABC", "TABC"])
    }

    func testProviderIdentityRejectsDuplicateCodeAndUUID() throws {
        let source = try fixture()
        let duplicateCode = MagicCatalogProviderSet(
            id: "00000000-0000-4000-8000-000000000099",
            code: "abc",
            name: "Collision",
            releasedAt: "2020-01-01",
            setType: "expansion"
        )
        XCTAssertThrowsError(try build(fixture: .init(sets: source.sets + [duplicateCode]))) { error in
            guard case .providerCodeMapsToMultipleUUIDs = error as? MagicCatalogBuilderError else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        let duplicateUUID = MagicCatalogProviderSet(
            id: source.sets[0].id,
            code: "ZZZ",
            name: "Collision",
            releasedAt: "2020-01-01",
            setType: "expansion"
        )
        XCTAssertThrowsError(try build(fixture: .init(sets: source.sets + [duplicateUUID]))) { error in
            guard case .providerUUIDMapsToMultipleCodes = error as? MagicCatalogBuilderError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testReleasedPrintedSizeDriftFailsClosedButFutureDriftIsAllowed() throws {
        let first = try build().release
        let source = try fixture()
        let changedRows = source.sets.map { row in
            row.code == "ABC"
                ? MagicCatalogProviderSet(
                    id: row.id,
                    code: row.code,
                    name: row.name,
                    releasedAt: row.releasedAt,
                    setType: row.setType,
                    cardCount: row.cardCount,
                    printedSize: 101,
                    iconSVGURL: row.iconSVGURL,
                    parentSetCode: row.parentSetCode,
                    digital: row.digital
                )
                : row
        }
        XCTAssertThrowsError(try build(fixture: .init(sets: changedRows), active: first, revision: 2)) { error in
            guard case .printedSizeDrift(let code, let activeSize, let candidateSize) = error as? MagicCatalogBuilderError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(code, "ABC")
            XCTAssertEqual(activeSize, 100)
            XCTAssertEqual(candidateSize, 101)
        }

        let futureSource = MagicCatalogProviderFixture(sets: source.sets.map { row in
            row.code == "ABC"
                ? MagicCatalogProviderSet(
                    id: row.id,
                    code: row.code,
                    name: row.name,
                    releasedAt: "2030-01-01",
                    setType: row.setType,
                    cardCount: row.cardCount,
                    printedSize: 101,
                    iconSVGURL: row.iconSVGURL,
                    parentSetCode: row.parentSetCode,
                    digital: row.digital
                )
                : row
        })
        let futureActiveSource = MagicCatalogProviderFixture(sets: source.sets.map { row in
            row.code == "ABC"
                ? MagicCatalogProviderSet(
                    id: row.id,
                    code: row.code,
                    name: row.name,
                    releasedAt: "2030-01-01",
                    setType: row.setType,
                    cardCount: row.cardCount,
                    printedSize: row.printedSize,
                    iconSVGURL: row.iconSVGURL,
                    parentSetCode: row.parentSetCode,
                    digital: row.digital
                )
                : row
        })
        let futureActive = try build(fixture: futureActiveSource, generatedAt: "2026-01-01T00:00:00.000Z").release
        let futureResult = try build(
            fixture: futureSource,
            active: futureActive,
            generatedAt: "2026-01-02T00:00:00.000Z",
            revision: 2
        )
        XCTAssertTrue(
            futureResult.report.warnings.contains {
                $0.contains("Future Magic set ABC printedSize changed")
            }
        )
    }

    func testRoutingInvariantsAndParentIdentityAreValidated() throws {
        let source = try fixture()
        let badChild = MagicCatalogProviderFixture(sets: source.sets.map { row in
            row.code == "TABC"
                ? MagicCatalogProviderSet(
                    id: row.id,
                    code: row.code,
                    name: row.name,
                    releasedAt: row.releasedAt,
                    setType: row.setType,
                    cardCount: row.cardCount,
                    printedSize: row.printedSize,
                    iconSVGURL: row.iconSVGURL,
                    parentSetCode: "MISSING",
                    digital: row.digital
                )
                : row
        })
        XCTAssertThrowsError(try build(fixture: badChild)) { error in
            XCTAssertEqual(
                error as? MagicCatalogReleaseValidator.ValidationError,
                .routingChildMissingParent("TABC")
            )
        }
    }

    func testSignatureRequiresMagicCatalogKind() throws {
        let key = Curve25519.Signing.PrivateKey()
        let release = try build().release
        let envelope = try MagicCatalogSignatureVerifier.sign(
            release: release,
            privateKey: key,
            keyID: "test"
        )
        XCTAssertNoThrow(try MagicCatalogSignatureVerifier.verify(
            envelope: envelope,
            keys: [.init(id: "test", publicKey: key.publicKey)]
        ))

        let wrongKind = MagicCatalogRelease(
            schemaVersion: 1,
            catalogKind: "pokemon",
            revision: release.revision,
            generatedAt: release.generatedAt,
            sets: release.sets
        )
        let wrongEnvelope = try MagicCatalogSignatureVerifier.sign(
            release: wrongKind,
            privateKey: key,
            keyID: "test"
        )
        XCTAssertThrowsError(try MagicCatalogSignatureVerifier.verify(
            envelope: wrongEnvelope,
            keys: [.init(id: "test", publicKey: key.publicKey)]
        )) { error in
            XCTAssertEqual(error as? MagicCatalogSignatureError, .wrongCatalogKind("pokemon"))
        }
    }

    func testMetadataChangeDoesNotChangeScannerProjection() throws {
        let first = try build().release
        let source = try fixture()
        let renamed = MagicCatalogProviderFixture(sets: source.sets.map { row in
            guard row.code == "ABC" else { return row }
            return MagicCatalogProviderSet(
                id: row.id,
                code: row.code,
                name: "Recorded Expansion Renamed",
                releasedAt: row.releasedAt,
                setType: row.setType,
                cardCount: row.cardCount,
                printedSize: row.printedSize,
                iconSVGURL: row.iconSVGURL,
                parentSetCode: row.parentSetCode,
                digital: row.digital
            )
        })

        let next = try build(fixture: renamed, active: first, revision: 2)
        XCTAssertEqual(next.report.scannerProjectionChangedCodes, [])
        XCTAssertEqual(next.report.browseProjectionChangedCodes, ["ABC"])
        XCTAssertEqual(next.report.routingProjectionChangedCodes, [])
    }

    func testScannerAndRoutingProjectionChangesAreReportedOrRejected() throws {
        let first = try build().release
        let source = try fixture()
        let releasedHistorical = MagicCatalogProviderFixture(sets: source.sets.map { row in
            guard row.code == "OLD" else { return row }
            return MagicCatalogProviderSet(
                id: row.id,
                code: row.code,
                name: row.name,
                releasedAt: "2015-01-01",
                setType: row.setType,
                cardCount: row.cardCount,
                printedSize: row.printedSize,
                iconSVGURL: row.iconSVGURL,
                parentSetCode: row.parentSetCode,
                digital: row.digital
            )
        })
        let next = try build(fixture: releasedHistorical, active: first, revision: 2)
        XCTAssertEqual(next.report.scannerProjectionChangedCodes, ["OLD"])

        let movedChild = MagicCatalogProviderFixture(sets: source.sets.map { row in
            guard row.code == "TABC" else { return row }
            return MagicCatalogProviderSet(
                id: row.id,
                code: row.code,
                name: row.name,
                releasedAt: row.releasedAt,
                setType: row.setType,
                cardCount: row.cardCount,
                printedSize: row.printedSize,
                iconSVGURL: row.iconSVGURL,
                parentSetCode: "OLD",
                digital: row.digital
            )
        })
        XCTAssertThrowsError(try build(fixture: movedChild, active: first, revision: 2)) { error in
            XCTAssertEqual(
                error as? MagicCatalogBuilderError,
                .routingAuthorityDrift(code: "TABC")
            )
        }
    }

    func testPublisherIsIdempotentAndRejectsDowngrade() throws {
        let first = try build().release
        let key = Curve25519.Signing.PrivateKey()
        let publisherRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("magic-catalog-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: publisherRoot) }

        let firstBuild = try build()
        let firstSigned = try MagicCatalogSigner.sign(
            firstBuild,
            privateKey: key,
            keyID: "test"
        )
        let publisher = MagicCatalogFilesystemPublisher(
            root: publisherRoot,
            environment: .production
        )
        _ = try publisher.publish(firstSigned)
        _ = try publisher.publish(firstSigned)

        let secondBuild = try build(active: first, revision: 2)
        let secondSigned = try MagicCatalogSigner.sign(
            secondBuild,
            privateKey: key,
            keyID: "test"
        )
        let secondReceipt = try publisher.publish(
            secondSigned,
            activeRelease: first
        )
        XCTAssertEqual(secondReceipt.revision, 2)
        XCTAssertThrowsError(try publisher.publish(firstSigned, activeRelease: secondBuild.release)) { error in
            XCTAssertEqual(
                error as? MagicCatalogPublisherError,
                .activeRevisionNotMonotonic(received: 1, current: 2)
            )
        }
    }

    func testSignatureCorruptionFailsClosed() throws {
        let key = Curve25519.Signing.PrivateKey()
        let envelope = try MagicCatalogSignatureVerifier.sign(
            release: try build().release,
            privateKey: key,
            keyID: "test"
        )
        let corrupted = MagicCatalogReleaseEnvelope(
            keyID: envelope.keyID,
            payload: envelope.payload,
            signature: envelope.signature + "A"
        )
        XCTAssertThrowsError(try MagicCatalogSignatureVerifier.verify(
            envelope: corrupted,
            keys: [.init(id: "test", publicKey: key.publicKey)]
        )) { error in
            XCTAssertEqual(error as? MagicCatalogSignatureError, .signatureVerificationFailed)
        }
    }
}
