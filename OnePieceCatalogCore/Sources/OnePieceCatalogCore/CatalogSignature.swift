#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
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
    /// Largest canonical payload a release may carry. Revision 7 is about 36 MiB.
    public static let maximumPayloadBytes = 40 * 1_024 * 1_024
    /// Largest signed envelope read from disk or the network. Base64 adds a
    /// third to the payload, so this leaves room above the payload cap.
    public static let maximumEnvelopeBytes = 64 * 1_024 * 1_024

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
                              maximumPayloadBytes: Int = OnePieceCatalogSignature.maximumPayloadBytes) throws -> OnePieceVerifiedCatalogRelease {
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
    /// Unpadded base64url → bytes, rejecting any non-canonical encoding.
    ///
    /// Equivalent to "only `[A-Za-z0-9_-]`, decodes, and `encode(data) == value`",
    /// done over bytes: the payload is tens of megabytes, and the regex,
    /// string replacements and re-encoded comparison cost seconds on device.
    static func decode(_ value: String) -> Data? {
        var value = value
        let standard: Data? = value.withUTF8 { input in
            guard !input.isEmpty else { return nil }
            let padding = (4 - input.count % 4) % 4
            var output = Data(count: input.count + padding)
            let valid = output.withUnsafeMutableBytes { raw -> Bool in
                let out = raw.bindMemory(to: UInt8.self)
                for index in 0..<input.count {
                    let byte = input[index]
                    switch byte {
                    case 65...90, 97...122, 48...57: out[index] = byte // A-Z a-z 0-9
                    case 45: out[index] = 43                            // - → +
                    case 95: out[index] = 47                            // _ → /
                    default: return false
                    }
                }
                for index in input.count..<out.count { out[index] = 61 } // =
                return true
            }
            return valid ? output : nil
        }
        guard let standard, let data = Data(base64Encoded: standard) else { return nil }
        // Canonical form: re-encoding must give back exactly the input, which
        // rejects non-zero unused bits in the final character.
        return data.base64EncodedData() == standard ? data : nil
    }
}
