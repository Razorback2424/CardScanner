import CryptoKit
import Foundation

public enum OnePieceCatalogPublicationError: Error, Equatable {
    case reviewFingerprintMismatch, nonCanonicalCandidate, baselineRequired, keyMismatch
}

public struct OnePieceCatalogPublicationManifest: Codable, Equatable, Sendable {
    public let revision: Int
    public let previousRevision: Int?
    public let keyID: String
    public let payloadSHA256: String
    public let envelopeSHA256: String
    public let classification: OnePieceCatalogChangeClassification
}

/// A reviewed payload and independently pinned public key are required even
/// when a private signing key is available. This API never allocates identities.
public enum OnePieceCatalogPublication {
    public static func prepare(candidate: Data, reviewedSHA256: String, keyID: String,
                               privateKey: Curve25519.Signing.PrivateKey,
                               trustedKeys: [String: Curve25519.Signing.PublicKey],
                               previous: OnePieceCatalogReleaseEnvelope? = nil,
                               bootstrap: Bool = false, now: Date = .now)
        throws -> (envelope: OnePieceCatalogReleaseEnvelope, manifest: OnePieceCatalogPublicationManifest) {
        guard OnePieceSourceObservation.sha256(candidate) == reviewedSHA256 else {
            throw OnePieceCatalogPublicationError.reviewFingerprintMismatch
        }
        guard candidate.count <= 32 * 1_024 * 1_024 else { throw OnePieceCatalogSignatureError.oversizedPayload }
        let release = try JSONDecoder().decode(OnePieceCatalogRelease.self, from: candidate)
        guard try release.canonicalData() == candidate else { throw OnePieceCatalogPublicationError.nonCanonicalCandidate }
        guard trustedKeys[keyID]?.rawRepresentation == privateKey.publicKey.rawRepresentation else {
            throw OnePieceCatalogPublicationError.keyMismatch
        }
        let envelope = try OnePieceCatalogSignature.sign(release, keyID: keyID, privateKey: privateKey)
        let manifest = try verify(envelope, reviewedSHA256: reviewedSHA256, trustedKeys: trustedKeys,
                                  previous: previous, bootstrap: bootstrap, now: now)
        return (envelope, manifest)
    }

    public static func verify(_ envelope: OnePieceCatalogReleaseEnvelope, reviewedSHA256: String,
                              trustedKeys: [String: Curve25519.Signing.PublicKey],
                              previous: OnePieceCatalogReleaseEnvelope? = nil,
                              bootstrap: Bool = false, now: Date = .now) throws -> OnePieceCatalogPublicationManifest {
        let baseline = try previous.map { try OnePieceCatalogSignature.verify($0, trustedKeys: trustedKeys, now: now).release }
        let verified = try OnePieceCatalogSignature.verify(envelope, trustedKeys: trustedKeys,
            minimumRevision: baseline?.revision, now: now)
        guard (baseline != nil && !bootstrap) || (baseline == nil && bootstrap && verified.release.revision == 1) else {
            throw OnePieceCatalogPublicationError.baselineRequired
        }
        guard verified.payloadFingerprint == reviewedSHA256 else { throw OnePieceCatalogPublicationError.reviewFingerprintMismatch }
        try OnePieceCatalogCandidateValidator.validate(verified.release, previous: baseline)
        return .init(revision: verified.release.revision, previousRevision: baseline?.revision,
            keyID: envelope.keyID, payloadSHA256: verified.payloadFingerprint,
            envelopeSHA256: OnePieceSourceObservation.sha256(try envelopeData(envelope)),
            classification: OnePieceCatalogChangeClassifier.classify(previous: baseline, current: verified.release))
    }

    public static func envelopeData(_ envelope: OnePieceCatalogReleaseEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(envelope)
    }
}
