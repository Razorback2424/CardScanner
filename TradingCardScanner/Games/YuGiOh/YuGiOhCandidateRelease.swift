import CryptoKit
import Foundation

/// Local delivery seam only. No endpoint, trust pins or launch activation are
/// installed. The existing publisher must sign the exact staged manifest bytes.
struct YuGiOhCandidateManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let revision: Int
    let generation: String
    let policyVersion: String
    let path: String
    let sha256: String
    let bytes: Int
    let status: String
    let capturedAt: String
}

struct YuGiOhCandidateEnvelope: Codable, Equatable, Sendable {
    let keyID: String
    /// Same unpadded base64url signature contract as the existing publishers.
    let payload: String
    let signature: String
    let catalog: Data
}

struct YuGiOhCatalogSnapshot: Sendable {
    let catalog: YuGiOhCatalog
    let priceAuthority: GameCatalogPriceAuthority
    init(catalog: YuGiOhCatalog) {
        self.catalog = catalog
        priceAuthority = YuGiOhPriceAdapter.priceAuthority(catalog)
    }
}

enum YuGiOhCandidateError: Error { case invalidManifest, invalidSignature, invalidTransition, oversized }

enum YuGiOhCandidateVerifier {
    static let maximumCatalogBytes = 48 * 1_024 * 1_024
    static let maximumEnvelopeBytes = 65 * 1_024 * 1_024
    static let policy = "yugioh-provider-membership-v1-2026-10-21"

    static func decodeURL(_ value: String) -> Data? {
        guard !value.isEmpty, value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return nil }
        let padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: padded), encodeURL(data) == value else { return nil }
        return data
    }
    static func encodeURL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func verify(_ envelope: YuGiOhCandidateEnvelope,
                       keys: [String: Curve25519.Signing.PublicKey], now: Date) throws -> (YuGiOhCandidateManifest, YuGiOhCatalogSnapshot) {
        guard envelope.catalog.count <= maximumCatalogBytes, envelope.payload.utf8.count <= 8192 else { throw YuGiOhCandidateError.oversized }
        guard envelope.keyID.range(of: "^yugioh-[a-z0-9][a-z0-9-]{0,63}$", options: .regularExpression) != nil,
              let key = keys[envelope.keyID], let payload = decodeURL(envelope.payload),
              envelope.signature.count == 86, let signature = decodeURL(envelope.signature), signature.count == 64,
              key.isValidSignature(signature, for: payload) else { throw YuGiOhCandidateError.invalidSignature }
        let manifest = try JSONDecoder().decode(YuGiOhCandidateManifest.self, from: payload)
        let catalog = try YuGiOhCatalog(data: envelope.catalog)
        let hash = SHA256.hash(data: envelope.catalog).map { String(format: "%02x", $0) }.joined()
        let iso = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard manifest.schemaVersion == 1, manifest.revision > 0, manifest.policyVersion == policy,
              manifest.status == "candidate_not_deployed", manifest.bytes == envelope.catalog.count,
              manifest.sha256 == hash, manifest.generation == catalog.generation,
              catalog.generation.range(of: "^yugioh-en-[a-z0-9-]{1,80}$", options: .regularExpression) != nil,
              manifest.path == "yugioh/v1/releases/\(catalog.generation)/catalog.json",
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
        return (manifest, .init(catalog: catalog))
    }

    static func validateTransition(from old: YuGiOhCatalog, to new: YuGiOhCatalog) throws {
        guard new.capturedAt >= old.capturedAt,
              new.generation == old.generation || new.capturedAt > old.capturedAt else { throw YuGiOhCandidateError.invalidTransition }
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

    init(root: URL, keys: [String: Curve25519.Signing.PublicKey], bundled: YuGiOhCatalog) throws {
        guard !keys.isEmpty, Set(keys.values.map(\.rawRepresentation)).count == keys.count else { throw YuGiOhCandidateError.invalidSignature }
        self.keys = keys
        self.bundled = .init(catalog: bundled)
        let transition: @Sendable (Core.StoredRelease?, Core.StoredRelease) throws -> Void = { previous, next in
            try YuGiOhCandidateVerifier.validateTransition(from: previous?.registry.catalog ?? bundled, to: next.registry.catalog)
        }
        core = Core(root: root, currentName: "yugioh-candidate-current.json", previousName: "yugioh-candidate-previous.json",
            revisionPolicy: .activeRelease, strictRevisionContent: true, rejectLowerRevision: true, validateRecovery: true,
            revision: { $0.revision }, encode: { try JSONEncoder().encode($0) },
            validateTransition: transition, validateRecoveryTransition: transition,
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
        await core.load { data in
            let envelope = try JSONDecoder().decode(YuGiOhCandidateEnvelope.self, from: data)
            let (manifest, snapshot) = try YuGiOhCandidateVerifier.verify(envelope, keys: keys, now: now)
            try YuGiOhCandidateVerifier.validateTransition(from: bundled, to: snapshot.catalog)
            return .init(envelope: envelope, release: manifest, registry: snapshot)
        }
    }
    func snapshot(now: Date = .now) async -> YuGiOhCatalogSnapshot {
        await load(now: now)
        return await core.activeRegistry ?? bundled
    }
    func stage(_ envelope: YuGiOhCandidateEnvelope, now: Date = .now) async throws -> SignedCatalogActivationResult {
        await load(now: now)
        let (manifest, snapshot) = try YuGiOhCandidateVerifier.verify(envelope, keys: keys, now: now)
        return try await core.activate(.init(envelope: envelope, release: manifest, registry: snapshot))
    }
}
