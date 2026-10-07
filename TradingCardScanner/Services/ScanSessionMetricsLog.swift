import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Local study instrumentation. Runtime UUIDs only route events; none are encoded.
/// This API deliberately cannot accept card identity, artwork, prices or free text.
actor ScanSessionMetricsLog {
    static let shared = ScanSessionMetricsLog()
    static let enabledDefaultsKey = "scanSessionMetricsEnabled"

    enum Interruption: String, Codable, Sendable {
        case variant, printRun, printing, duplicate, heldDuplicate
    }

    enum Outcome: String, Codable, Sendable {
        case success, failure, cancelled, invalidated, suppressed
        case sessionEnded = "session-ended"
        case choiceDismissed = "choice-dismissed"
        case printRunDismissed = "print-run-dismissed"
        case identityDismissed = "identity-dismissed"
        case sameCard = "same-card"
        case duplicateEvidenceStale = "duplicate-evidence-stale"
        case duplicatePromptAbandoned = "duplicate-prompt-abandoned"
        case duplicateProofMissing = "duplicate-proof-missing"
        case heldRepeatRejected = "held-repeat-rejected"
        case heldRepeatMismatch = "held-repeat-mismatch"
        case storageGenerationStale = "storage-generation-stale"
        case collectionGameWriteDisabled = "collection-game-write-disabled"
        case sessionStale = "session-stale"
        case certifiedDuplicate = "certified-duplicate"
        case priceCheck = "price-check"
        case priceCheckFailure = "price-check-failure"
        case autoDuplicate = "auto-duplicate"
        case other
    }

    enum Counter: String, Codable, CaseIterable, Sendable {
        case undo, finishCorrection, printingCorrection
        case needsAttentionFiled, needsAttentionResolved
        case lockSuggestionsShown, lockSuggestionsAccepted
        case autoAddedDuplicates, autoAddedDuplicateUndos
    }

    struct Encounter: Codable, Equatable, Sendable {
        let confirmedAt: Date
        let outcome: Outcome
        let durationMs: Int
        var interruptions: [Interruption]
    }

    struct Session: Codable, Equatable, Sendable {
        let startedAt: Date
        var endedAt: Date?
        var encounters: [Encounter] = []
        var counters: [String: Int] = Dictionary(
            uniqueKeysWithValues: Counter.allCases.map { ($0.rawValue, 0) }
        )
    }

    struct Payload: Codable, Equatable, Sendable {
        let schemaVersion: Int
        var sessions: [Session]
    }

    private struct PendingEncounter {
        let confirmedAt: Date
        let uptime: TimeInterval
        var interruptions: [Interruption] = []
    }

    let fileURL: URL
    private var payload = Payload(schemaVersion: 1, sessions: [])
    private var loaded = false
    private var storageError: Error?
    private var activeSessionID: UUID?
    private var pending: [UUID: PendingEncounter] = [:]
    private var completed: [UUID: Int] = [:]

    init(fileURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fileURL = fileURL ?? support.appendingPathComponent("Scanner", isDirectory: true)
            .appendingPathComponent("scan-session-metrics.json")
    }

    func beginSession(id: UUID, enabled: Bool, at date: Date = .now) {
        activeSessionID = nil
        pending.removeAll()
        completed.removeAll()
        guard enabled else { return }
        loadIfNeeded()
        guard storageError == nil else { return }
        activeSessionID = id
        payload.sessions.append(Session(startedAt: date))
        persist()
    }

    func beginEncounter(sessionID: UUID, encounterID: UUID, at date: Date = .now,
                        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard activeSessionID == sessionID, pending[encounterID] == nil,
              completed[encounterID] == nil else { return }
        pending[encounterID] = PendingEncounter(confirmedAt: date, uptime: uptime)
    }

    func interrupt(sessionID: UUID, encounterID: UUID, with interruption: Interruption) {
        guard activeSessionID == sessionID else { return }
        if pending[encounterID] != nil {
            pending[encounterID]?.interruptions.append(interruption)
        } else if let index = completed[encounterID] {
            // A held-copy offer may appear after the original receipt commits.
            payload.sessions[payload.sessions.count - 1].encounters[index].interruptions.append(interruption)
            persist()
        }
    }

    func endEncounter(sessionID: UUID, encounterID: UUID, outcome: Outcome,
                      uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard activeSessionID == sessionID,
              let encounter = pending.removeValue(forKey: encounterID) else { return }
        let index = payload.sessions.count - 1
        completed[encounterID] = payload.sessions[index].encounters.count
        payload.sessions[index].encounters.append(Encounter(
            confirmedAt: encounter.confirmedAt, outcome: outcome,
            durationMs: Int(max(0, uptime - encounter.uptime) * 1_000),
            interruptions: encounter.interruptions
        ))
        persist()
    }

    func increment(sessionID: UUID, counter: Counter, by count: Int = 1) {
        guard activeSessionID == sessionID, count > 0 else { return }
        payload.sessions[payload.sessions.count - 1].counters[counter.rawValue, default: 0] += count
        persist()
    }

    func endSession(id: UUID, at date: Date = .now) {
        guard activeSessionID == id else { return }
        // Defensive fallback for callers outside the scanner's end choke point.
        for encounterID in Array(pending.keys) {
            endEncounter(sessionID: id, encounterID: encounterID, outcome: .sessionEnded)
        }
        payload.sessions[payload.sessions.count - 1].endedAt = date
        activeSessionID = nil
        completed.removeAll()
        persist()
    }

    func exportData() throws -> Data {
        loadIfNeeded()
        if let storageError { throw storageError }
        return try Self.encoder().encode(payload)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let saved = try decoder.decode(Payload.self, from: Data(contentsOf: fileURL))
            guard saved.schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
            payload = saved
        } catch {
            let nsError = error as NSError
            guard nsError.domain == NSCocoaErrorDomain,
                  [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(nsError.code) else {
                // Never replace unreadable or newer-format study evidence.
                storageError = error
                return
            }
        }
    }

    private func persist() {
        guard storageError == nil else { return }
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.excludeFromBackup(directory)
            try Self.encoder().encode(payload).write(to: fileURL, options: .atomic)
            try Self.excludeFromBackup(fileURL)
        } catch {
            storageError = error
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

struct ScanSessionMetricsExport: Transferable, Sendable {
    let log: ScanSessionMetricsLog
    let pendingWrites: Task<Void, Never>?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { item in
            await item.pendingWrites?.value
            return try await item.log.exportData()
        }
        .suggestedFileName("CardScanner Session Log.json")
    }
}
