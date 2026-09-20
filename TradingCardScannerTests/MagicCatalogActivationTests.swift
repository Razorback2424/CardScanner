import CryptoKit
import XCTest
@testable import TradingCardScanner

final class MagicCatalogActivationTests: XCTestCase {
    private let key = Curve25519.Signing.PrivateKey()
    private let keyID = "activation-test"

    private func descriptor(
        code: String = "ABC",
        name: String = "Test Set",
        printedSize: Int? = 100,
        scanEnabled: Bool = true,
        browseEnabled: Bool = true,
        parentSetCode: String? = nil,
        routingKind: MagicCatalogRoutingKind? = nil
    ) -> MagicCatalogSetDescriptor {
        MagicCatalogSetDescriptor(
            scryfallSetID: "00000000-0000-4000-8000-000000000001",
            code: code,
            displayName: name,
            releaseDate: "2020-01-01",
            setType: routingKind == nil ? "expansion" : "token",
            printedSize: printedSize,
            cardCount: 100,
            iconSVGURL: nil,
            parentSetCode: parentSetCode,
            routingKind: routingKind,
            scanEnabled: scanEnabled,
            browseEnabled: browseEnabled
        )
    }

    private func envelope(
        revision: Int,
        name: String = "Test Set",
        scanEnabled: Bool = true
    ) throws -> MagicCatalogReleaseEnvelope {
        let release = MagicCatalogRelease(
            revision: revision,
            generatedAt: "2026-01-01T00:00:00.000Z",
            sets: [descriptor(name: name, scanEnabled: scanEnabled)]
        )
        return try MagicCatalogSignatureVerifier.sign(
            release: release,
            privateKey: key,
            keyID: keyID
        )
    }

    func testActivationIsIdempotentMonotonicAndProjectionAware() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("magic-catalog-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let pinnedKey = MagicCatalogSignatureVerifier.PinnedKey(
            id: keyID,
            publicKey: key.publicKey
        )
        let coordinator = MagicCatalogCoordinator(
            store: MagicCatalogReleaseStore(root: root),
            keys: [pinnedKey],
            rolloutMode: .remoteAuthority
        )

        let first = try envelope(revision: 1)
        guard case .activated(let firstEvent) = await coordinator.activateEnvelope(first) else {
            return XCTFail("first signed release should activate")
        }
        XCTAssertTrue(firstEvent.scannerProjectionChanged)
        XCTAssertTrue(firstEvent.browseProjectionChanged)
        let firstRevision = await coordinator.revision
        XCTAssertEqual(firstRevision, 1)

        if case .notModified = await coordinator.activateEnvelope(first) {
            // Expected same-revision idempotence.
        } else {
            XCTFail("replaying the same signed revision should be idempotent")
        }

        let conflictingSameRevision = try envelope(revision: 1, name: "Different")
        if case .rejected = await coordinator.activateEnvelope(conflictingSameRevision) {
            // A revision cannot be reused for different bytes.
        } else {
            XCTFail("a conflicting same-revision envelope should be rejected")
        }

        let metadataOnly = try envelope(revision: 2, name: "Metadata Update")
        guard case .activated(let metadataEvent) = await coordinator.activateEnvelope(metadataOnly) else {
            return XCTFail("higher signed revision should activate")
        }
        XCTAssertFalse(metadataEvent.scannerProjectionChanged)
        XCTAssertTrue(metadataEvent.browseProjectionChanged)
        let metadataRevision = await coordinator.revision
        XCTAssertEqual(metadataRevision, 2)

        let scannerChange = try envelope(revision: 3, name: "Metadata Update", scanEnabled: false)
        guard case .activated(let scannerEvent) = await coordinator.activateEnvelope(scannerChange) else {
            return XCTFail("higher signed revision should activate")
        }
        XCTAssertTrue(scannerEvent.scannerProjectionChanged)

        let recovered = MagicCatalogCoordinator(
            store: MagicCatalogReleaseStore(root: root),
            keys: [pinnedKey],
            rolloutMode: .remoteAuthority
        )
        await recovered.loadPersistedOrBundled()
        let recoveredRevision = await recovered.revision
        let recoveredRegistry = await recovered.registry
        XCTAssertEqual(recoveredRevision, 3)
        XCTAssertEqual(recoveredRegistry.descriptor(forCode: "ABC")?.displayName, "Metadata Update")
    }
}
