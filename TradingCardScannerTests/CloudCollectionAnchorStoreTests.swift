import XCTest
@testable import TradingCardScanner

final class CloudCollectionAnchorStoreTests: XCTestCase {
    private actor FakeDatabase: CloudAnchorDatabaseClient {
        enum Mode {
            case missing
            case existing(CloudCollectionAnchor)
            case unavailable
            case malformed
            case race
        }

        private var mode: Mode
        private var stored: CloudCollectionAnchor?

        init(mode: Mode) {
            self.mode = mode
            if case let .existing(anchor) = mode { stored = anchor }
        }

        func fetchAnchor() async throws -> CloudCollectionAnchor? {
            switch mode {
            case .unavailable:
                throw CloudAnchorDatabaseError.temporarilyUnavailable
            case .malformed:
                throw CloudAnchorDatabaseError.malformed
            case .missing, .race:
                return stored
            case .existing:
                return stored
            }
        }

        func createAnchor(_ anchor: CloudCollectionAnchor) async throws -> CloudCollectionAnchor {
            if let stored {
                throw CloudAnchorDatabaseError.conflict(stored)
            }
            switch mode {
            case .unavailable:
                throw CloudAnchorDatabaseError.temporarilyUnavailable
            case .malformed:
                throw CloudAnchorDatabaseError.malformed
            case .missing, .race:
                stored = anchor
                return anchor
            case .existing:
                throw CloudAnchorDatabaseError.conflict(stored ?? anchor)
            }
        }
    }

    private let localID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let remoteID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    func testMissingAnchorIsDistinctFromTemporaryFailure() async {
        let missing = CloudCollectionAnchorStore(client: FakeDatabase(mode: .missing))
        let missingState = await missing.readState()
        XCTAssertEqual(missingState, .missing)

        let unavailable = CloudCollectionAnchorStore(client: FakeDatabase(mode: .unavailable))
        let unavailableState = await unavailable.readState()
        XCTAssertEqual(unavailableState, .temporarilyUnavailable)
    }

    func testMatchingAndDifferentAnchorsRemainTyped() async {
        let matching = CloudCollectionAnchorStore(
            client: FakeDatabase(
                mode: .existing(CloudCollectionAnchor(storeID: localID, formatVersion: 1))
            )
        )
        let matchingState = await matching.readState()
        XCTAssertEqual(
            matchingState,
            .found(CloudCollectionAnchor(storeID: localID, formatVersion: 1))
        )

        let different = CloudCollectionAnchorStore(
            client: FakeDatabase(
                mode: .existing(CloudCollectionAnchor(storeID: remoteID, formatVersion: 1))
            )
        )
        let differentState = await different.readState()
        XCTAssertEqual(
            differentState,
            .found(CloudCollectionAnchor(storeID: remoteID, formatVersion: 1))
        )
    }

    func testFirstClaimSucceedsAndReadAfterWriteIsRequiredByClientContract() async {
        let store = CloudCollectionAnchorStore(client: FakeDatabase(mode: .missing))
        let firstClaim = await store.claim(storeID: localID)
        XCTAssertEqual(
            firstClaim,
            .claimed(CloudCollectionAnchor(storeID: localID, formatVersion: 1))
        )
        let stateAfterClaim = await store.readState()
        XCTAssertEqual(
            stateAfterClaim,
            .found(CloudCollectionAnchor(storeID: localID, formatVersion: 1))
        )
    }

    func testSecondClaimCannotOverwriteTheFirstIdentity() async {
        let database = FakeDatabase(mode: .missing)
        let store = CloudCollectionAnchorStore(client: database)
        let first = await store.claim(storeID: localID)
        let second = await store.claim(storeID: remoteID)

        XCTAssertEqual(
            first,
            .claimed(CloudCollectionAnchor(storeID: localID, formatVersion: 1))
        )
        XCTAssertEqual(
            second,
            .alreadyClaimed(CloudCollectionAnchor(storeID: localID, formatVersion: 1))
        )
        let stateAfterFirstClaim = await store.readState()
        XCTAssertEqual(
            stateAfterFirstClaim,
            .found(CloudCollectionAnchor(storeID: localID, formatVersion: 1))
        )
    }

    func testMalformedAnchorBlocksAttachment() async {
        let store = CloudCollectionAnchorStore(client: FakeDatabase(mode: .malformed))
        let state = await store.readState()
        let claim = await store.claim(storeID: localID)
        XCTAssertEqual(state, .malformed)
        XCTAssertEqual(claim, .malformed)
    }

    func testNoInventoryContentIsPartOfAnchorSchema() {
        XCTAssertEqual(CloudCollectionAnchorSchema.recordType, "CardScannerCollectionAnchor")
        XCTAssertEqual(CloudCollectionAnchorSchema.recordName, "canonical-collection")
        XCTAssertEqual(CloudCollectionAnchorSchema.storeIDField, "storeID")
        XCTAssertEqual(CloudCollectionAnchorSchema.formatVersionField, "formatVersion")
        XCTAssertEqual(CloudCollectionAnchorSchema.createdAtField, "createdAt")
        let fields = [
            CloudCollectionAnchorSchema.storeIDField,
            CloudCollectionAnchorSchema.formatVersionField,
            CloudCollectionAnchorSchema.createdAtField
        ]
        XCTAssertFalse(fields.contains { $0.localizedCaseInsensitiveContains("card") })
        XCTAssertFalse(fields.contains { $0.localizedCaseInsensitiveContains("inventory") })
        XCTAssertFalse(fields.contains { $0.localizedCaseInsensitiveContains("price") })
    }
}
