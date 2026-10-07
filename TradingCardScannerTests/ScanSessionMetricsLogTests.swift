import XCTest
@testable import TradingCardScanner

final class ScanSessionMetricsLogTests: XCTestCase {
    func testRoundTripContainsOnlyStudyFieldsAndExcludesBackup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("metrics.json")
        let log = ScanSessionMetricsLog(fileURL: url)
        let sessionID = UUID()
        let encounterID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        await log.beginSession(id: sessionID, enabled: true, at: date)
        await log.beginEncounter(sessionID: sessionID, encounterID: encounterID, at: date, uptime: 100)
        await log.interrupt(sessionID: sessionID, encounterID: encounterID, with: .variant)
        await log.interrupt(sessionID: sessionID, encounterID: encounterID, with: .printRun)
        await log.endEncounter(sessionID: sessionID, encounterID: encounterID, outcome: .choiceDismissed, uptime: 102)
        // Repeated terminal callbacks must not double count a physical encounter.
        await log.endEncounter(sessionID: sessionID, encounterID: encounterID, outcome: .success, uptime: 104)
        await log.increment(sessionID: sessionID, counter: .undo)
        await log.increment(sessionID: sessionID, counter: .needsAttentionFiled, by: 2)
        await log.endSession(id: sessionID, at: date.addingTimeInterval(3))

        let bytes = try await log.exportData()
        let restoredBytes = try await ScanSessionMetricsLog(fileURL: url).exportData()
        XCTAssertEqual(bytes, restoredBytes)
        let payload = try Self.decode(bytes)
        let session = try XCTUnwrap(payload.sessions.first)
        XCTAssertEqual(session.startedAt, date)
        XCTAssertEqual(session.endedAt, date.addingTimeInterval(3))
        XCTAssertEqual(session.encounters.count, 1)
        XCTAssertEqual(session.encounters.first?.durationMs, 2_000)
        XCTAssertEqual(session.encounters.first?.outcome, .choiceDismissed)
        XCTAssertEqual(session.encounters.first?.interruptions, [.variant, .printRun])
        XCTAssertEqual(session.counters["undo"], 1)
        XCTAssertEqual(session.counters["needsAttentionFiled"], 2)
        XCTAssertEqual(session.counters["printingCorrection"], 0)
        XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)

        let text = String(decoding: bytes, as: UTF8.self)
        for forbidden in [sessionID.uuidString, encounterID.uuidString, "Pikachu", "cardName", "providerID", "price", "image"] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["schemaVersion", "sessions"])
        let sessions = try XCTUnwrap(json["sessions"] as? [[String: Any]])
        XCTAssertEqual(Set(sessions[0].keys), ["startedAt", "endedAt", "encounters", "counters"])
        let encounters = try XCTUnwrap(sessions[0]["encounters"] as? [[String: Any]])
        XCTAssertEqual(Set(encounters[0].keys), ["confirmedAt", "outcome", "durationMs", "interruptions"])
    }

    func testDisabledLogCreatesNoFileAndPreservesExistingEvidence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("metrics.json")
        let log = ScanSessionMetricsLog(fileURL: url)
        let sessionID = UUID()
        let encounterID = UUID()
        await log.beginSession(id: sessionID, enabled: false)
        await log.beginEncounter(sessionID: sessionID, encounterID: encounterID)
        await log.interrupt(sessionID: sessionID, encounterID: encounterID, with: .duplicate)
        await log.endEncounter(sessionID: sessionID, encounterID: encounterID, outcome: .success)
        await log.increment(sessionID: sessionID, counter: .undo)
        await log.endSession(id: sessionID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let emptyExport = try await log.exportData()
        XCTAssertTrue(try Self.decode(emptyExport).sessions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        await log.beginSession(id: sessionID, enabled: true)
        await log.endSession(id: sessionID)
        let original = try Data(contentsOf: url)
        let disabled = ScanSessionMetricsLog(fileURL: url)
        await disabled.beginSession(id: UUID(), enabled: false)
        await disabled.increment(sessionID: sessionID, counter: .undo)
        XCTAssertEqual(try Data(contentsOf: url), original)
        let disabledExport = try await disabled.exportData()
        XCTAssertEqual(disabledExport, original)
    }

    func testStaleSessionsCannotMutateNewSessionAndHeldOfferIsRecorded() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = ScanSessionMetricsLog(fileURL: directory.appendingPathComponent("metrics.json"))
        let old = UUID(), current = UUID(), encounterID = UUID()
        await log.beginSession(id: old, enabled: true)
        await log.endSession(id: old)
        await log.beginSession(id: current, enabled: true)
        await log.beginEncounter(sessionID: current, encounterID: encounterID, uptime: 10)
        await log.endEncounter(sessionID: current, encounterID: encounterID, outcome: .success, uptime: 9)
        await log.interrupt(sessionID: current, encounterID: encounterID, with: .heldDuplicate)
        await log.increment(sessionID: old, counter: .undo)
        await log.endSession(id: old)
        let bytes = try await log.exportData()
        let session = try XCTUnwrap(Self.decode(bytes).sessions.last)
        XCTAssertNil(session.endedAt)
        XCTAssertEqual(session.counters["undo"], 0)
        XCTAssertEqual(session.encounters.first?.durationMs, 0)
        XCTAssertEqual(session.encounters.first?.interruptions, [.heldDuplicate])
    }

    func testUnreadableEvidenceIsNotOverwrittenAndExportFails() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("metrics.json")
        let original = Data("unreadable evidence".utf8)
        try original.write(to: url)
        let log = ScanSessionMetricsLog(fileURL: url)
        await log.beginSession(id: UUID(), enabled: true)
        do {
            _ = try await log.exportData()
            XCTFail("Export must report unreadable evidence")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    static func decode(_ data: Data) throws -> ScanSessionMetricsLog.Payload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ScanSessionMetricsLog.Payload.self, from: data)
    }
}
