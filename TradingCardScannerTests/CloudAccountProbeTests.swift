import CloudKit
import XCTest
@testable import TradingCardScanner

final class CloudAccountProbeTests: XCTestCase {
    private actor FakeClient: CloudAccountClient {
        let statusResult: Result<CKAccountStatus, Error>
        let recordResult: Result<String, Error>

        init(
            status: Result<CKAccountStatus, Error>,
            record: Result<String, Error> = .success("record-a")
        ) {
            statusResult = status
            recordResult = record
        }

        func accountStatus() async throws -> CKAccountStatus {
            try statusResult.get()
        }

        func userRecordName() async throws -> String {
            try recordResult.get()
        }
    }

    private struct ProbeError: Error {}

    private func probe(
        status: Result<CKAccountStatus, Error>,
        record: Result<String, Error> = .success("record-a")
    ) -> CloudAccountProbe {
        CloudAccountProbe(
            client: FakeClient(status: status, record: record),
            fingerprintSalt: Data("test-salt".utf8)
        )
    }

    func testEverySystemAccountStatusMapsDistinctly() async {
        let available = await probe(status: .success(.available)).availability()
        let noAccount = await probe(status: .success(.noAccount)).availability()
        let restricted = await probe(status: .success(.restricted)).availability()
        let temporarilyUnavailable = await probe(status: .success(.temporarilyUnavailable)).availability()
        let couldNotDetermine = await probe(status: .success(.couldNotDetermine)).availability()
        XCTAssertEqual(available, .available(fingerprint: CloudAccountProbe.fingerprint(recordName: "record-a", salt: Data("test-salt".utf8))))
        XCTAssertEqual(noAccount, .noAccount)
        XCTAssertEqual(restricted, .restricted)
        XCTAssertEqual(temporarilyUnavailable, .temporarilyUnavailable)
        XCTAssertEqual(couldNotDetermine, .couldNotDetermine)
    }

    func testAccountStatusFailureDoesNotBecomeNoAccountOrNewAccount() async {
        let result = await probe(status: .failure(ProbeError())).availability()
        XCTAssertEqual(result, .couldNotDetermine)
    }

    func testUserRecordFailureDoesNotBecomeAnAvailableFingerprint() async {
        let result = await probe(
            status: .success(.available),
            record: .failure(ProbeError())
        ).availability()
        XCTAssertEqual(result, .couldNotDetermine)
    }

    func testIdenticalRecordAndSaltProduceStableFingerprint() {
        let salt = Data("same-salt".utf8)
        XCTAssertEqual(
            CloudAccountProbe.fingerprint(recordName: "record-a", salt: salt),
            CloudAccountProbe.fingerprint(recordName: "record-a", salt: salt)
        )
        XCTAssertNotEqual(
            CloudAccountProbe.fingerprint(recordName: "record-a", salt: salt),
            CloudAccountProbe.fingerprint(recordName: "record-b", salt: salt)
        )
        XCTAssertNotEqual(
            CloudAccountProbe.fingerprint(recordName: "record-a", salt: salt),
            CloudAccountProbe.fingerprint(recordName: "record-a", salt: Data("other-salt".utf8))
        )
    }

    func testReturnedValueDoesNotContainRawRecordName() async {
        let rawRecordName = "raw-record-name-that-must-not-leak"
        let result = await probe(
            status: .success(.available),
            record: .success(rawRecordName)
        ).availability()
        XCTAssertFalse(String(describing: result).contains(rawRecordName))
    }
}
