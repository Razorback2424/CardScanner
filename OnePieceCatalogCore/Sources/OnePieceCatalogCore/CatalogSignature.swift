import CryptoKit
import Foundation

public struct OnePieceCatalogReleaseEnvelope: Codable, Equatable, Sendable {
    public let keyID: String
    public let payload: String
    public let signature: String
    public init(keyID: String, payload: String, signature: String) {
        self.keyID = keyID; self.payload = payload; self.signature = signature
    }
}

/// Constructed only after signature, contract, index and time validation. App
/// catalog registries require this value rather than accepting unsigned JSON.
public struct OnePieceVerifiedCatalogRelease: Sendable {
    public let release: OnePieceCatalogRelease
    public let payloadFingerprint: String
    public let verifiedAt: Date
    fileprivate init(release: OnePieceCatalogRelease, payload: Data, verifiedAt: Date) {
        self.release = release; self.payloadFingerprint = OnePieceSourceObservation.sha256(payload)
        self.verifiedAt = verifiedAt
    }
}

public enum OnePieceCatalogSignatureError: Error, Equatable {
    case invalidKeyID, unknownKey, invalidEncoding, invalidSignature, oversizedPayload
    case nonMonotonicRevision, futureRelease
}

public enum OnePieceCatalogSignature {
    public static func sign(_ release: OnePieceCatalogRelease, keyID: String,
                            privateKey: Curve25519.Signing.PrivateKey) throws -> OnePieceCatalogReleaseEnvelope {
        guard keyID.hasPrefix("one-piece-"), keyID.count > "one-piece-".count else {
            throw OnePieceCatalogSignatureError.invalidKeyID
        }
        try OnePieceCatalogCandidateValidator.validate(release)
        let payload = try release.canonicalData()
        return .init(keyID: keyID, payload: encode(payload), signature: encode(try privateKey.signature(for: payload)))
    }

    public static func verify(_ envelope: OnePieceCatalogReleaseEnvelope,
                              trustedKeys: [String: Curve25519.Signing.PublicKey],
                              minimumRevision: Int? = nil, now: Date = .now,
                              maximumPayloadBytes: Int = 32 * 1_024 * 1_024) throws -> OnePieceVerifiedCatalogRelease {
        guard envelope.keyID.hasPrefix("one-piece-") else { throw OnePieceCatalogSignatureError.invalidKeyID }
        guard let key = trustedKeys[envelope.keyID] else { throw OnePieceCatalogSignatureError.unknownKey }
        // Bound before base64 allocation. This limits bytes, never candidates.
        guard maximumPayloadBytes > 0,
              envelope.payload.utf8.count / 4 * 3 <= maximumPayloadBytes,
              envelope.signature.utf8.count <= 90 else { throw OnePieceCatalogSignatureError.oversizedPayload }
        guard let payload = decode(envelope.payload), let signature = decode(envelope.signature), signature.count == 64 else {
            throw OnePieceCatalogSignatureError.invalidEncoding
        }
        guard payload.count <= maximumPayloadBytes else { throw OnePieceCatalogSignatureError.oversizedPayload }
        guard key.isValidSignature(signature, for: payload) else { throw OnePieceCatalogSignatureError.invalidSignature }
        let release = try JSONDecoder().decode(OnePieceCatalogRelease.self, from: payload)
        try OnePieceCatalogCandidateValidator.validate(release)
        if let minimumRevision, release.revision <= minimumRevision { throw OnePieceCatalogSignatureError.nonMonotonicRevision }
        guard let generatedAt = ISO8601DateFormatter().date(from: release.generatedAt),
              generatedAt <= now.addingTimeInterval(300) else { throw OnePieceCatalogSignatureError.futureRelease }
        return .init(release: release, payload: payload, verifiedAt: now)
    }

    private static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private static func decode(_ value: String) -> Data? {
        guard !value.isEmpty, value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return nil }
        let base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padded = base64 + String(repeating: "=", count: (4 - base64.utf8.count % 4) % 4)
        guard let data = Data(base64Encoded: padded), encode(data) == value else { return nil }
        return data
    }
}
