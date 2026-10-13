import CryptoKit
import Foundation

struct LorcanaCatalogReleaseEnvelope: Codable, Equatable, Sendable {
    let keyID: String
    let payload: String
    let signature: String
}

struct LorcanaCatalogRelease: Codable, Sendable {
    let schemaVersion: Int
    let gameID: String
    let revision: Int
    let generatedAt: Date
    let catalog: LorcanaPhysicalCatalogManifest

    func canonicalData() throws -> Data {
        try canonicalData(registry: LorcanaCatalogRegistry(manifest: catalog))
    }

    fileprivate func canonicalData(registry: LorcanaCatalogRegistry) throws -> Data {
        guard schemaVersion == 1, gameID == CardGame.lorcana.rawValue, revision > 0,
              generatedAt.timeIntervalSince1970.isFinite, generatedAt.timeIntervalSince1970 > 0,
              catalog.reviewedAt <= generatedAt else { throw LorcanaCatalogSignatureError.invalidRelease }
        let normalized = Self(schemaVersion: schemaVersion, gameID: gameID, revision: revision,
            generatedAt: generatedAt, catalog: registry.normalizedPhysicalManifest!)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(normalized)
    }
}

/// Only the verifier can construct signed authority; unsigned research registries
/// remain useful for footer tests without being accepted by the release store.
struct LorcanaVerifiedCatalogRelease: Sendable {
    let release: LorcanaCatalogRelease
    let registry: LorcanaCatalogRegistry
    let payloadFingerprint: String
    fileprivate init(release: LorcanaCatalogRelease, registry: LorcanaCatalogRegistry, payload: Data) {
        self.release = release; self.registry = registry
        payloadFingerprint = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }
}

enum LorcanaCatalogSignatureError: Error, Equatable {
    case invalidKeyID, unknownKey, invalidTrust, invalidEncoding, invalidSignature
    case oversizedPayload, invalidRelease, nonCanonicalPayload, futureRelease
}

enum LorcanaCatalogSignature {
    static let maximumPayloadBytes = 8 * 1_024 * 1_024
    static let maximumEnvelopeBytes = 12 * 1_024 * 1_024

    static func validateTrust(_ keys: [String: Curve25519.Signing.PublicKey],
                              forbiddenPublicKeys: Set<Data> = []) throws {
        var material: Set<Data> = []
        guard !keys.isEmpty else { throw LorcanaCatalogSignatureError.invalidTrust }
        for (id, key) in keys {
            guard validKeyID(id), !forbiddenPublicKeys.contains(key.rawRepresentation),
                  material.insert(key.rawRepresentation).inserted else { throw LorcanaCatalogSignatureError.invalidTrust }
        }
    }

    static func sign(_ release: LorcanaCatalogRelease, keyID: String,
                     privateKey: Curve25519.Signing.PrivateKey) throws -> LorcanaCatalogReleaseEnvelope {
        guard validKeyID(keyID) else { throw LorcanaCatalogSignatureError.invalidKeyID }
        let bytes = try release.canonicalData()
        guard bytes.count <= maximumPayloadBytes else { throw LorcanaCatalogSignatureError.oversizedPayload }
        return .init(keyID: keyID, payload: encode(bytes), signature: encode(try privateKey.signature(for: bytes)))
    }

    static func verify(_ envelope: LorcanaCatalogReleaseEnvelope,
                       trustedKeys: [String: Curve25519.Signing.PublicKey], now: Date = .now) throws -> LorcanaVerifiedCatalogRelease {
        guard validKeyID(envelope.keyID) else { throw LorcanaCatalogSignatureError.invalidKeyID }
        try validateTrust(trustedKeys)
        guard let key = trustedKeys[envelope.keyID] else { throw LorcanaCatalogSignatureError.unknownKey }
        guard envelope.payload.utf8.count <= (maximumPayloadBytes * 4 + 2) / 3,
              envelope.signature.utf8.count == 86 else { throw LorcanaCatalogSignatureError.oversizedPayload }
        guard let payload = decode(envelope.payload), payload.count <= maximumPayloadBytes,
              let signature = decode(envelope.signature), signature.count == 64 else {
            throw LorcanaCatalogSignatureError.invalidEncoding
        }
        guard key.isValidSignature(signature, for: payload) else { throw LorcanaCatalogSignatureError.invalidSignature }
        let release = try JSONDecoder().decode(LorcanaCatalogRelease.self, from: payload)
        let registry = try LorcanaCatalogRegistry(manifest: release.catalog)
        guard try release.canonicalData(registry: registry) == payload else { throw LorcanaCatalogSignatureError.nonCanonicalPayload }
        guard now.timeIntervalSince1970.isFinite, release.generatedAt <= now.addingTimeInterval(300) else {
            throw LorcanaCatalogSignatureError.futureRelease
        }
        return .init(release: release, registry: registry, payload: payload)
    }

    private static func validKeyID(_ id: String) -> Bool {
        LorcanaPrintedIdentity.matches(id, "lorcana-[a-z0-9][a-z0-9-]{0,63}")
    }
    private static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private static func decode(_ value: String) -> Data? {
        guard !value.isEmpty, LorcanaPrintedIdentity.matches(value, "[A-Za-z0-9_-]+") else { return nil }
        let base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let bytes = Data(base64Encoded: base64 + String(repeating: "=", count: (4 - base64.utf8.count % 4) % 4)),
              encode(bytes) == value else { return nil }
        return bytes
    }
}
