import CloudKit
import Foundation

enum CloudCollectionAnchorSchema {
    static let recordType = "CardScannerCollectionAnchor"
    static let recordName = "canonical-collection"
    static let storeIDField = "storeID"
    static let formatVersionField = "formatVersion"
    static let createdAtField = "createdAt"
    static let currentFormatVersion = 1
}

enum CloudAnchorDatabaseError: Error, Equatable, Sendable {
    case temporarilyUnavailable
    case malformed
    case conflict(CloudCollectionAnchor)
    case unavailable
}

protocol CloudAnchorDatabaseClient: Sendable {
    func fetchAnchor() async throws -> CloudCollectionAnchor?
    func createAnchor(_ anchor: CloudCollectionAnchor) async throws -> CloudCollectionAnchor
}

struct CloudKitPrivateAnchorDatabaseClient: CloudAnchorDatabaseClient, @unchecked Sendable {
    let database: CKDatabase

    init(container: CKContainer = CKContainer(identifier: CloudAccountProbe.containerIdentifier)) {
        database = container.privateCloudDatabase
    }

    func fetchAnchor() async throws -> CloudCollectionAnchor? {
        let recordID = CKRecord.ID(recordName: CloudCollectionAnchorSchema.recordName)
        do {
            let record = try await database.record(for: recordID)
            return try Self.decode(record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch let error as CKError {
            throw Self.map(error)
        } catch let error as CloudAnchorDatabaseError {
            throw error
        } catch {
            throw CloudAnchorDatabaseError.unavailable
        }
    }

    func createAnchor(_ anchor: CloudCollectionAnchor) async throws -> CloudCollectionAnchor {
        let recordID = CKRecord.ID(recordName: CloudCollectionAnchorSchema.recordName)
        let record = CKRecord(
            recordType: CloudCollectionAnchorSchema.recordType,
            recordID: recordID
        )
        record[CloudCollectionAnchorSchema.storeIDField] = anchor.storeID.uuidString as CKRecordValue
        record[CloudCollectionAnchorSchema.formatVersionField] = NSNumber(value: anchor.formatVersion)
        record[CloudCollectionAnchorSchema.createdAtField] = Date.now as CKRecordValue

        do {
            _ = try await database.save(record)
            guard let written = try await fetchAnchor() else {
                throw CloudAnchorDatabaseError.unavailable
            }
            return written
        } catch let error as CKError where error.code == .serverRecordChanged {
            do {
                if let existing = try await fetchAnchor() {
                    throw CloudAnchorDatabaseError.conflict(existing)
                }
            } catch let error as CloudAnchorDatabaseError {
                throw error
            }
            throw CloudAnchorDatabaseError.unavailable
        } catch let error as CloudAnchorDatabaseError {
            throw error
        } catch let error as CKError {
            throw Self.map(error)
        } catch {
            throw CloudAnchorDatabaseError.unavailable
        }
    }

    private static func decode(_ record: CKRecord) throws -> CloudCollectionAnchor {
        guard let rawStoreID = record[CloudCollectionAnchorSchema.storeIDField] as? String,
              let storeID = UUID(uuidString: rawStoreID),
              let rawVersion = record[CloudCollectionAnchorSchema.formatVersionField] as? NSNumber,
              rawVersion.intValue == CloudCollectionAnchorSchema.currentFormatVersion,
              record[CloudCollectionAnchorSchema.createdAtField] is Date else {
            throw CloudAnchorDatabaseError.malformed
        }
        return CloudCollectionAnchor(
            storeID: storeID,
            formatVersion: rawVersion.intValue
        )
    }

    private static func map(_ error: CKError) -> CloudAnchorDatabaseError {
        switch error.code {
        case .notAuthenticated, .accountTemporarilyUnavailable, .networkFailure,
             .networkUnavailable, .serviceUnavailable, .requestRateLimited,
             .zoneBusy, .limitExceeded:
            return .temporarilyUnavailable
        case .unknownItem:
            return .unavailable
        default:
            return .unavailable
        }
    }
}

enum CloudCollectionAnchorClaimResult: Equatable, Sendable {
    case claimed(CloudCollectionAnchor)
    case alreadyClaimed(CloudCollectionAnchor)
    case temporarilyUnavailable
    case malformed
}

struct CloudCollectionAnchorStore: Sendable {
    let client: any CloudAnchorDatabaseClient

    init(client: any CloudAnchorDatabaseClient) {
        self.client = client
    }

    func readState() async -> CloudCollectionAnchorState {
        do {
            if let anchor = try await client.fetchAnchor() {
                return .found(anchor)
            }
            return .missing
        } catch CloudAnchorDatabaseError.temporarilyUnavailable {
            return .temporarilyUnavailable
        } catch CloudAnchorDatabaseError.malformed {
            return .malformed
        } catch {
            return .unknown
        }
    }

    func claim(storeID: UUID) async -> CloudCollectionAnchorClaimResult {
        let desired = CloudCollectionAnchor(
            storeID: storeID,
            formatVersion: CloudCollectionAnchorSchema.currentFormatVersion
        )
        do {
            let written = try await client.createAnchor(desired)
            guard written == desired else { return .malformed }
            return .claimed(written)
        } catch let CloudAnchorDatabaseError.conflict(existing) {
            return .alreadyClaimed(existing)
        } catch CloudAnchorDatabaseError.temporarilyUnavailable {
            return .temporarilyUnavailable
        } catch CloudAnchorDatabaseError.malformed {
            return .malformed
        } catch {
            return .temporarilyUnavailable
        }
    }
}
