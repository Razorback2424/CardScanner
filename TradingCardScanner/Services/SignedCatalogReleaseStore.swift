import Foundation

enum SignedCatalogActivationResult: Equatable, Sendable {
    case activated(revision: Int, previousRevision: Int?)
    case alreadyCurrent
}

enum SignedCatalogStoreError: Error { case revisionCollision, revisionRollback }

/// Shared two-slot mechanics. Domains retain their signed wire contract,
/// decoder/trust policy, revision policy, paths and bundled fallback.
actor SignedCatalogReleaseStore<Envelope: Codable & Equatable & Sendable, Release: Sendable, Registry: Sendable> {
    struct StoredRelease: Sendable {
        let envelope: Envelope
        let release: Release
        let registry: Registry
    }
    enum RevisionPolicy: Sendable { case currentSlot, activeRelease }
    enum Slot: Sendable { case current, previous }

    private let root: URL
    private let currentName: String
    private let previousName: String
    private let revisionPolicy: RevisionPolicy
    private let strictRevisionContent: Bool
    private let rejectLowerRevision: Bool
    private let fallback: StoredRelease?
    private let revision: @Sendable (Release) -> Int
    private let encode: @Sendable (Envelope) throws -> Data
    private let validateTransition: @Sendable (StoredRelease?, StoredRelease) throws -> Void
    private let readData: @Sendable (URL) throws -> Data
    private let writeData: @Sendable (Data, URL) throws -> Void
    private var current: StoredRelease?
    private var currentBytes: Data?
    private var previous: StoredRelease?
    private var didLoad = false

    init(root: URL, currentName: String, previousName: String,
         revisionPolicy: RevisionPolicy, strictRevisionContent: Bool = false,
         rejectLowerRevision: Bool = false,
         fallback: StoredRelease? = nil,
         revision: @escaping @Sendable (Release) -> Int,
         encode: @escaping @Sendable (Envelope) throws -> Data,
         validateTransition: @escaping @Sendable (StoredRelease?, StoredRelease) throws -> Void = { _, _ in },
         readData: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) },
         writeData: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.root = root; self.currentName = currentName; self.previousName = previousName
        self.revisionPolicy = revisionPolicy; self.strictRevisionContent = strictRevisionContent
        self.rejectLowerRevision = rejectLowerRevision
        self.fallback = fallback; self.revision = revision; self.encode = encode
        self.validateTransition = validateTransition; self.readData = readData; self.writeData = writeData
    }

    var activeRelease: StoredRelease? { current ?? previous ?? fallback }
    var activeRevision: Int? { activeRelease.map { revision($0.release) } }
    var activeRegistry: Registry? { activeRelease?.registry }
    var currentSlotRelease: StoredRelease? { current }
    var previousSlotRelease: StoredRelease? { previous }

    func load(decodeAndVerify: @Sendable (Data) throws -> StoredRelease,
              rejectedSlot: @Sendable (String) -> Void = { _ in }) {
        guard !didLoad else { return }
        didLoad = true
        func read(_ slot: Slot) -> (StoredRelease, Data)? {
            let file = url(slot)
            do {
                let bytes = try readData(file)
                return (try decodeAndVerify(bytes), bytes)
            } catch {
                if FileManager.default.fileExists(atPath: file.path) { rejectedSlot(file.lastPathComponent) }
                return nil
            }
        }
        if let loaded = read(.current) {
            current = loaded.0; currentBytes = loaded.1
        } else {
            previous = read(.previous)?.0
        }
    }

    func activate(_ next: StoredRelease) throws -> SignedCatalogActivationResult {
        let comparison = revisionPolicy == .currentSlot ? current : activeRelease
        let previousRevision = comparison.map { revision($0.release) }
        let nextRevision = revision(next.release)
        if let previousRevision, nextRevision <= previousRevision {
            if rejectLowerRevision && nextRevision < previousRevision { throw SignedCatalogStoreError.revisionRollback }
            if strictRevisionContent, nextRevision == previousRevision, comparison?.envelope != next.envelope {
                throw SignedCatalogStoreError.revisionCollision
            }
            return .alreadyCurrent
        }
        // Runs inside this actor's non-suspending transaction. A concurrent
        // activation cannot validate corrections against a stale predecessor.
        try validateTransition(activeRelease, next)
        let nextBytes = try encode(next.envelope)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let current, let currentBytes {
            // Copy known verified bytes; disk corruption or external cache
            // deletion cannot turn the backup into an unverified current file.
            try writeConfirmingCommit(currentBytes, to: url(.previous))
            previous = current
        }
        try writeConfirmingCommit(nextBytes, to: url(.current))
        current = next; currentBytes = nextBytes
        return .activated(revision: nextRevision, previousRevision: previousRevision)
    }

    func diskUsageBytes() -> Int {
        [Slot.current, .previous].reduce(0) { result, slot in
            let attributes = try? FileManager.default.attributesOfItem(atPath: url(slot).path)
            return result + ((attributes?[.size] as? NSNumber)?.intValue ?? 0)
        }
    }
    func slotFileExists(_ slot: Slot) -> Bool { FileManager.default.fileExists(atPath: url(slot).path) }

    #if DEBUG
    func reset() {
        current = nil; currentBytes = nil; previous = nil; didLoad = false
        for slot in [Slot.current, .previous] { try? FileManager.default.removeItem(at: url(slot)) }
    }
    #endif

    private func url(_ slot: Slot) -> URL {
        root.appendingPathComponent(slot == .current ? currentName : previousName)
    }
    private func writeConfirmingCommit(_ bytes: Data, to url: URL) throws {
        do { try writeData(bytes, url) }
        catch {
            // A writer that committed then reported an error is reconciled
            // only through exact persisted bytes, never by assuming success.
            guard (try? readData(url)) == bytes else { throw error }
        }
    }
}
