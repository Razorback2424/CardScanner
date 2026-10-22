import CryptoKit
import Foundation

struct YuGiOhCatalogSnapshot: Sendable {
    let catalog: YuGiOhCatalog
    let priceAuthority: GameCatalogPriceAuthority
    init(catalog: YuGiOhCatalog) {
        self.catalog = catalog
        priceAuthority = YuGiOhPriceAdapter.priceAuthority(catalog)
    }
}

enum YuGiOhCandidateVerifier {
    static let maximumCatalogBytes = YuGiOhReleaseWire.maximumCatalogBytes
    static let maximumEnvelopeBytes = YuGiOhReleaseWire.maximumEnvelopeBytes
    static let policy = YuGiOhReleaseWire.policy

    static func decodeURL(_ value: String) -> Data? {
        YuGiOhReleaseWire.decodeURL(value)
    }
    static func encodeURL(_ data: Data) -> String {
        YuGiOhReleaseWire.encodeURL(data)
    }

    static func verify(_ envelope: YuGiOhCandidateEnvelope,
                       keys: [String: Curve25519.Signing.PublicKey], now: Date,
                       state: YuGiOhPublicationState = .candidate) throws -> (YuGiOhCandidateManifest, YuGiOhCatalogSnapshot) {
        let manifest = try YuGiOhReleaseWire.verify(envelope, keys: keys, state: state, now: now)
        var catalog = try YuGiOhCatalog(data: envelope.catalog)
        let iso = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard manifest.generation == catalog.generation,
              (iso.date(from: manifest.capturedAt) ?? fractional.date(from: manifest.capturedAt)) == catalog.capturedAt,
              now.timeIntervalSince1970.isFinite, catalog.capturedAt <= now.addingTimeInterval(300) else { throw YuGiOhCandidateError.invalidManifest }
        // The hash also binds policy and membership provenance, which the real
        // loader validates before catalog and price authority are built together.
        let raw = try JSONSerialization.jsonObject(with: envelope.catalog) as? [String: Any]
        guard raw?["policyVersion"] as? String == policy else { throw YuGiOhCandidateError.invalidManifest }
        for printing in catalog.printingByID.values {
            for member in printing.membership {
                guard let timestamp = member.s, let date = iso.date(from: timestamp) ?? fractional.date(from: timestamp),
                      date <= catalog.capturedAt else { throw YuGiOhCandidateError.invalidManifest }
            }
        }
        if state == .approved { catalog.publicationRevision = manifest.revision }
        return (manifest, .init(catalog: catalog))
    }

    static func validateTransition(from old: YuGiOhCatalog, to new: YuGiOhCatalog,
                                   reviewedSameSnapshot: Bool = false) throws {
        guard new.capturedAt >= old.capturedAt,
              new.generation == old.generation || new.capturedAt > old.capturedAt || reviewedSameSnapshot else { throw YuGiOhCandidateError.invalidTransition }
        if new.generation == old.generation {
            guard new.capturedAt == old.capturedAt, new.printingByID == old.printingByID,
                  new.autoEligibleCodes == old.autoEligibleCodes, new.incompleteCodes == old.incompleteCodes else { throw YuGiOhCandidateError.invalidTransition }
        }
        for (id, previous) in old.printingByID {
            guard let next = new.printingByID[id], previous.productID == next.productID,
                  previous.card.id == next.card.id, previous.code == next.code,
                  previous.set.groupID == next.set.groupID, previous.rarity == next.rarity,
                  previous.artLabel == next.artLabel, previous.productName == next.productName else { throw YuGiOhCandidateError.invalidTransition }
        }
    }
}

/// Reuses the existing verified two-slot persistence/rollback mechanism. The
/// explicit root is required so local staging cannot touch owner collection or
/// recovery data. Bundled data is the fallback, never described as live pricing.
actor YuGiOhCandidateReleaseStore {
    typealias Core = SignedCatalogReleaseStore<YuGiOhCandidateEnvelope, YuGiOhCandidateManifest, YuGiOhCatalogSnapshot>
    private let core: Core
    private let keys: [String: Curve25519.Signing.PublicKey]
    private let bundled: YuGiOhCatalogSnapshot
    private let state: YuGiOhPublicationState

    init(root: URL, keys: [String: Curve25519.Signing.PublicKey], bundled: YuGiOhCatalog,
         state: YuGiOhPublicationState = .candidate, bundledSHA256: String? = nil) throws {
        guard !keys.isEmpty, Set(keys.values.map(\.rawRepresentation)).count == keys.count else { throw YuGiOhCandidateError.invalidSignature }
        self.keys = keys
        self.state = state
        self.bundled = .init(catalog: bundled)
        let transition: @Sendable (Core.StoredRelease?, Core.StoredRelease) throws -> Void = { previous, next in
            if state == .approved {
                guard next.release.parentSHA256 == (previous?.release.sha256 ?? bundledSHA256) else { throw YuGiOhCandidateError.invalidTransition }
            }
            try YuGiOhCandidateVerifier.validateTransition(from: previous?.registry.catalog ?? bundled, to: next.registry.catalog,
                reviewedSameSnapshot: state == .approved)
        }
        if state == .approved, bundledSHA256?.range(of: "^[a-f0-9]{64}$", options: .regularExpression) == nil { throw YuGiOhCandidateError.invalidManifest }
        let prefix = state == .approved ? "yugioh-approved" : "yugioh-candidate"
        core = Core(root: root, currentName: "\(prefix)-current.json", previousName: "\(prefix)-previous.json",
            revisionPolicy: .activeRelease, strictRevisionContent: true, rejectLowerRevision: true, validateRecovery: true,
            revision: { $0.revision }, encode: { try JSONEncoder().encode($0) },
            validateTransition: transition,
            validateRecoveryTransition: { previous, next in
                // A two-slot cache cannot retain the full approval ancestry.
                // Each slot is independently signed; available adjacent slots
                // must agree on their parent hash and immutable identities.
                if previous != nil { try transition(previous, next) }
            },
            readData: { url in
                let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
                let data = try file.read(upToCount: YuGiOhCandidateVerifier.maximumEnvelopeBytes + 1) ?? Data()
                guard data.count <= YuGiOhCandidateVerifier.maximumEnvelopeBytes else { throw YuGiOhCandidateError.oversized }
                return data
            })
    }

    func load(now: Date = .now) async {
        let keys = keys
        let bundled = bundled.catalog
        let state = state
        await core.load { data in
            let envelope = try JSONDecoder().decode(YuGiOhCandidateEnvelope.self, from: data)
            let (manifest, snapshot) = try YuGiOhCandidateVerifier.verify(envelope, keys: keys, now: now, state: state)
            try YuGiOhCandidateVerifier.validateTransition(from: bundled, to: snapshot.catalog, reviewedSameSnapshot: state == .approved)
            return .init(envelope: envelope, release: manifest, registry: snapshot)
        }
    }
    func snapshot(now: Date = .now) async -> YuGiOhCatalogSnapshot {
        await load(now: now)
        return await core.activeRegistry ?? bundled
    }
    func stage(_ envelope: YuGiOhCandidateEnvelope, now: Date = .now) async throws -> SignedCatalogActivationResult {
        await load(now: now)
        let (manifest, snapshot) = try YuGiOhCandidateVerifier.verify(envelope, keys: keys, now: now, state: state)
        try Task.checkCancellation()
        return try await core.activate(.init(envelope: envelope, release: manifest, registry: snapshot))
    }

    func activeRelease() async -> Core.StoredRelease? { await core.activeRelease }
}
