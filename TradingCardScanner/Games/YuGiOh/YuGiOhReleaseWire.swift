import CryptoKit
import Foundation

/// Shared verbatim by the app and the offline publisher. Signing a candidate
/// never grants approval: consumers choose the required publication state.
enum YuGiOhPublicationState: String, Codable, Sendable {
    case candidate = "candidate_not_deployed"
    case approved = "approved"
}

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
    var parentSHA256: String? = nil
    var reviewID: String? = nil
    /// Signed locator for the immutable parent envelope; the hash remains the authority.
    var parentRevision: Int? = nil
    /// The reviewed full snapshot may be installed from this exact bundled seed.
    var checkpointSHA256: String? = nil
    /// Catalog hashes of reviewed predecessors, keyed by approval revision.
    var ancestors: [Int: String]? = nil

    var ancestryIncludingSelf: [Int: String] {
        var lineage = ancestors ?? [:]
        lineage[revision] = sha256
        return lineage
    }

    var checkpointBaseSHA256: String? {
        checkpointSHA256 ?? ((parentRevision ?? 0) == 0 ? parentSHA256 : nil)
    }

    func canInstallCheckpoint(after active: Self?, bundleSHA256: String) -> Bool {
        if let active { return ancestors?[active.revision] == active.sha256 }
        return checkpointSHA256 == bundleSHA256 || ancestors?.values.contains(bundleSHA256) == true
    }
}

struct YuGiOhCandidateEnvelope: Codable, Equatable, Sendable {
    let keyID: String
    let payload: String
    let signature: String
    /// JSONEncoder's ordinary base64 Data representation, not base64url.
    let catalog: Data
}

enum YuGiOhCandidateError: Error { case invalidManifest, invalidSignature, invalidTransition, oversized }

enum YuGiOhReleaseWire {
    static let maximumCatalogBytes = 48 * 1_024 * 1_024
    static let maximumEnvelopeBytes = 65 * 1_024 * 1_024
    // A revision is at most six digits. Even a hash for every supported
    // approval revision fits this encoded payload and the envelope stays bounded.
    private static let maximumApprovedPayloadBytes = 12 * 1_024 * 1_024
    static let policy = "yugioh-provider-membership-v1-2026-10-21"

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
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
    static func date(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return ISO8601DateFormatter().date(from: text) ?? fractional.date(from: text)
    }
    static func verify(_ envelope: YuGiOhCandidateEnvelope, keys: [String: Curve25519.Signing.PublicKey],
                       state: YuGiOhPublicationState, now: Date) throws -> YuGiOhCandidateManifest {
        let approved = state == .approved
        guard envelope.catalog.count <= maximumCatalogBytes,
              envelope.payload.utf8.count <= (approved ? maximumApprovedPayloadBytes : 8192) else {
            throw YuGiOhCandidateError.oversized
        }
        guard envelope.keyID.range(of: "^yugioh-[a-z0-9][a-z0-9-]{0,63}$", options: .regularExpression) != nil,
              let key = keys[envelope.keyID], let payload = decodeURL(envelope.payload),
              envelope.signature.count == 86, let signature = decodeURL(envelope.signature), signature.count == 64,
              key.isValidSignature(signature, for: payload) else { throw YuGiOhCandidateError.invalidSignature }
        let manifest = try JSONDecoder().decode(YuGiOhCandidateManifest.self, from: payload)
        guard manifest.schemaVersion == (approved ? 2 : 1), (1...100_000).contains(manifest.revision),
              manifest.policyVersion == policy, manifest.status == state.rawValue,
              manifest.bytes == envelope.catalog.count, manifest.sha256 == hash(envelope.catalog),
              manifest.generation.range(of: "^yugioh-en-[a-z0-9-]{1,80}$", options: .regularExpression) != nil,
              manifest.path == (approved ? "yugioh/v1/releases/\(manifest.revision)/catalog.json"
                : "yugioh/v1/releases/\(manifest.generation)/catalog.json"),
              let captured = date(manifest.capturedAt), now.timeIntervalSince1970.isFinite,
              captured <= now.addingTimeInterval(300) else { throw YuGiOhCandidateError.invalidManifest }
        if approved {
            guard manifest.parentSHA256?.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                  manifest.reviewID?.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", options: .regularExpression) != nil else {
                throw YuGiOhCandidateError.invalidManifest
            }
            if let parent = manifest.parentRevision {
                guard (0..<manifest.revision).contains(parent) else { throw YuGiOhCandidateError.invalidManifest }
            }
            if let checkpoint = manifest.checkpointSHA256 {
                guard checkpoint.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                      manifest.parentRevision != nil || checkpoint == manifest.parentSHA256 else {
                    throw YuGiOhCandidateError.invalidManifest
                }
            }
            if let ancestors = manifest.ancestors {
                guard let parent = manifest.parentRevision, parent > 0, ancestors[parent] == manifest.parentSHA256,
                      ancestors.allSatisfy({ revision, hash in
                          (1...parent).contains(revision) && hash.utf8.count == 64
                              && hash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
                      }) else { throw YuGiOhCandidateError.invalidManifest }
            }
        } else if manifest.parentSHA256 != nil || manifest.reviewID != nil || manifest.parentRevision != nil
                    || manifest.checkpointSHA256 != nil || manifest.ancestors != nil {
            throw YuGiOhCandidateError.invalidManifest
        }
        return manifest
    }
}
