import CryptoKit
import Foundation
import OnePieceCatalogCore

actor OnePieceCatalogReleaseStore {
    enum Slot: String, CaseIterable {
        case current = "one-piece-catalog-release-current.json"
        case previous = "one-piece-catalog-release-previous.json"
    }
    typealias Core = SignedCatalogReleaseStore<OnePieceCatalogReleaseEnvelope, OnePieceVerifiedCatalogRelease, OnePieceCatalogRegistry>
    typealias StoredRelease = Core.StoredRelease
    typealias ActivationResult = SignedCatalogActivationResult
    private let core: Core
    private let keys: [String: Curve25519.Signing.PublicKey]
    nonisolated let bundledRegistry: OnePieceCatalogRegistry?

    init(root: URL? = nil, keys: [String: Curve25519.Signing.PublicKey],
         bundledEnvelope: OnePieceCatalogReleaseEnvelope? = nil, now: Date = .now,
         writeData: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) throws {
        self.keys = keys
        let fallback = try bundledEnvelope.map { try Self.stored(envelope: $0, keys: keys, now: now) }
        bundledRegistry = fallback?.registry
        let root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("BrowseCatalogCache/OnePieceCatalogReleases", isDirectory: true)
        core = Core(root: root, currentName: Slot.current.rawValue, previousName: Slot.previous.rawValue,
            revisionPolicy: .activeRelease, strictRevisionContent: true, rejectLowerRevision: true, fallback: fallback,
            revision: { $0.release.revision }, encode: { envelope in
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                return try encoder.encode(envelope)
            }, validateTransition: { previous, next in
                if let previous {
                    try OnePieceCatalogCandidateValidator.validate(next.release.release, previous: previous.release.release)
                }
            }, readData: { url in
                let maximum = 48 * 1_024 * 1_024
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: maximum + 1) ?? Data()
                guard data.count <= maximum else { throw OnePieceCatalogSignatureError.oversizedPayload }
                return data
            }, writeData: writeData)
    }

    var activeRelease: StoredRelease? { get async { await core.activeRelease } }
    var activeRevision: Int? { get async { await core.activeRevision } }
    var activeRegistry: OnePieceCatalogRegistry? { get async { await core.activeRegistry } }

    func load(now: Date = .now) async {
        let keys = keys
        await core.load(decodeAndVerify: { data in
            let envelope = try JSONDecoder().decode(OnePieceCatalogReleaseEnvelope.self, from: data)
            return try Self.stored(envelope: envelope, keys: keys, now: now)
        })
    }

    func activate(_ envelope: OnePieceCatalogReleaseEnvelope, now: Date = .now) async throws -> ActivationResult {
        await load(now: now)
        let next = try Self.stored(envelope: envelope, keys: keys, now: now)
        return try await core.activate(next)
    }

    func diskUsageBytes() async -> Int { await core.diskUsageBytes() }

    func validateEnvelope(_ envelope: OnePieceCatalogReleaseEnvelope, now: Date = .now) async throws -> Int {
        await load(now: now)
        let next = try Self.stored(envelope: envelope, keys: keys, now: now)
        if let previous = await core.activeRelease {
            guard next.release.release.revision >= previous.release.release.revision else {
                throw SignedCatalogStoreError.revisionRollback
            }
            if next.release.release.revision == previous.release.release.revision {
                guard next.envelope == previous.envelope else { throw SignedCatalogStoreError.revisionCollision }
            } else {
                try OnePieceCatalogCandidateValidator.validate(next.release.release, previous: previous.release.release)
            }
        }
        return next.release.release.revision
    }

    private static func stored(envelope: OnePieceCatalogReleaseEnvelope,
                               keys: [String: Curve25519.Signing.PublicKey], now: Date) throws -> StoredRelease {
        let verified = try OnePieceCatalogSignature.verify(envelope, trustedKeys: keys, now: now)
        return .init(envelope: envelope, release: verified, registry: .init(verifiedRelease: verified))
    }
}
