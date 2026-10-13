import CryptoKit
import Foundation

actor LorcanaCatalogReleaseStore {
    enum Slot: String {
        case current = "lorcana-catalog-release-current.json"
        case previous = "lorcana-catalog-release-previous.json"
    }
    typealias Core = SignedCatalogReleaseStore<LorcanaCatalogReleaseEnvelope, LorcanaVerifiedCatalogRelease, LorcanaCatalogRegistry>
    typealias StoredRelease = Core.StoredRelease
    private let core: Core
    private let keys: [String: Curve25519.Signing.PublicKey]

    init(root: URL? = nil, keys: [String: Curve25519.Signing.PublicKey],
         forbiddenPublicKeys: Set<Data> = [], bundledEnvelope: LorcanaCatalogReleaseEnvelope? = nil, now: Date = .now,
         writeData: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) throws {
        try LorcanaCatalogSignature.validateTrust(keys, forbiddenPublicKeys: forbiddenPublicKeys)
        self.keys = keys
        let fallback = try bundledEnvelope.map { try Self.stored($0, keys: keys, now: now) }
        let root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BrowseCatalogCache/LorcanaCatalogReleases", isDirectory: true)
        core = Core(root: root, currentName: Slot.current.rawValue, previousName: Slot.previous.rawValue,
            revisionPolicy: .activeRelease, strictRevisionContent: true, rejectLowerRevision: true, validateRecovery: true,
            fallback: fallback, revision: { $0.release.revision }, encode: { envelope in
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                return try encoder.encode(envelope)
            }, sameRevisionContent: { previous, next in
                Self.sameContent(previous.envelope, next.envelope)
            }, validateTransition: { previous, next in
                if let previous { try next.registry.physicalCatalog!.validateTransition(from: previous.registry) }
            }, readData: { url in
                let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                let bytes = try handle.read(upToCount: LorcanaCatalogSignature.maximumEnvelopeBytes + 1) ?? Data()
                guard bytes.count <= LorcanaCatalogSignature.maximumEnvelopeBytes else {
                    throw LorcanaCatalogSignatureError.oversizedPayload
                }
                return bytes
            }, writeData: writeData)
    }

    var activeRelease: StoredRelease? { get async { await core.activeRelease } }
    var activeRevision: Int? { get async { await core.activeRevision } }

    func load(now: Date = .now) async {
        let keys = keys
        await core.load(decodeAndVerify: { bytes in
            try Self.stored(JSONDecoder().decode(LorcanaCatalogReleaseEnvelope.self, from: bytes), keys: keys, now: now)
        })
    }
    func activate(_ envelope: LorcanaCatalogReleaseEnvelope, now: Date = .now) async throws -> SignedCatalogActivationResult {
        await load(now: now)
        return try await core.activate(Self.stored(envelope, keys: keys, now: now))
    }
    func validateEnvelope(_ envelope: LorcanaCatalogReleaseEnvelope, now: Date = .now) async throws -> Int {
        await load(now: now)
        let next = try Self.stored(envelope, keys: keys, now: now)
        if let previous = await core.activeRelease {
            guard next.release.release.revision >= previous.release.release.revision else { throw SignedCatalogStoreError.revisionRollback }
            if next.release.release.revision == previous.release.release.revision {
                guard Self.sameContent(next.envelope, previous.envelope) else { throw SignedCatalogStoreError.revisionCollision }
            } else { try next.registry.physicalCatalog!.validateTransition(from: previous.registry) }
        }
        return next.release.release.revision
    }
    private static func stored(_ envelope: LorcanaCatalogReleaseEnvelope,
                               keys: [String: Curve25519.Signing.PublicKey], now: Date) throws -> StoredRelease {
        let verified = try LorcanaCatalogSignature.verify(envelope, trustedKeys: keys, now: now)
        return .init(envelope: envelope, release: verified, registry: verified.registry)
    }
    /// Both envelopes are verified before comparison. A re-signature under the
    /// same pin cannot turn identical canonical content into a revision collision.
    private static func sameContent(_ lhs: LorcanaCatalogReleaseEnvelope, _ rhs: LorcanaCatalogReleaseEnvelope) -> Bool {
        lhs.keyID == rhs.keyID && lhs.payload == rhs.payload
    }
}
