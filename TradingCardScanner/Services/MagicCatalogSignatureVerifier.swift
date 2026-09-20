import CryptoKit
import Foundation
import MagicCatalogCore

enum MagicCatalogSignatureVerifier {
    enum VerificationError: Error, CustomStringConvertible, Equatable {
        case unknownKeyID(String)
        case invalidPayloadEncoding
        case invalidSignatureEncoding
        case signatureVerificationFailed
        case payloadDecodeFailed(String)
        case unsupportedSchemaVersion(Int)
        case wrongCatalogKind(String)
        case revisionNotMonotonic(received: Int, current: Int)
        case futureTimestamp(String)

        var description: String {
            switch self {
            case .unknownKeyID(let id): return "Unknown Magic catalog key ID: \(id)"
            case .invalidPayloadEncoding: return "Magic catalog payload is not valid base64url"
            case .invalidSignatureEncoding: return "Magic catalog signature is not valid base64url"
            case .signatureVerificationFailed: return "Magic catalog signature verification failed"
            case .payloadDecodeFailed(let message): return "Magic catalog payload decode failed: \(message)"
            case .unsupportedSchemaVersion(let version): return "Unsupported Magic catalog schema version: \(version)"
            case .wrongCatalogKind(let kind): return "Expected Magic catalog kind, received \(kind)"
            case .revisionNotMonotonic(let received, let current):
                return "Magic catalog revision \(received) is not greater than current \(current)"
            case .futureTimestamp(let timestamp): return "Magic catalog timestamp is in the future: \(timestamp)"
            }
        }
    }

    typealias PinnedKey = MagicCatalogCore.MagicCatalogSignatureVerifier.PinnedKey

    static var pinnedKeys: [PinnedKey] {
        configuredPinnedKeys(
            from: Bundle.main.object(forInfoDictionaryKey: "MAGIC_CATALOG_PINNED_KEYS") as? String
        )
    }

    static func configuredPinnedKeys(from rawValue: String?) -> [PinnedKey] {
        guard let rawValue,
              !rawValue.isEmpty,
              !rawValue.contains("$(") else { return [] }
        return rawValue.split(separator: ";").compactMap { entry in
            let text = String(entry)
            guard let separator = text.firstIndex(of: ":") ?? text.firstIndex(of: "=") else {
                return nil
            }
            let id = String(text[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let encoded = String(text[text.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty,
                  let data = MagicCatalogBase64URL.decode(encoded),
                  data.count == 32,
                  let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: data) else {
                return nil
            }
            return PinnedKey(id: id, publicKey: publicKey)
        }
    }

    static func verify(
        envelope: MagicCatalogReleaseEnvelope,
        currentRevision: Int? = nil,
        now: Date = Date(),
        maxFutureSkew: TimeInterval = 3600,
        keys: [PinnedKey] = pinnedKeys
    ) throws -> MagicCatalogRelease {
        do {
            return try MagicCatalogCore.MagicCatalogSignatureVerifier.verify(
                envelope: envelope,
                currentRevision: currentRevision,
                now: now,
                maxFutureSkew: maxFutureSkew,
                keys: keys
            )
        } catch let error as MagicCatalogSignatureError {
            throw map(error)
        } catch {
            throw VerificationError.payloadDecodeFailed(String(describing: error))
        }
    }

    #if DEBUG
    static func sign(
        release: MagicCatalogRelease,
        privateKey: Curve25519.Signing.PrivateKey,
        keyID: String
    ) throws -> MagicCatalogReleaseEnvelope {
        try MagicCatalogCore.MagicCatalogSignatureVerifier.sign(
            release: release,
            privateKey: privateKey,
            keyID: keyID
        )
    }
    #endif

    private static func map(_ error: MagicCatalogSignatureError) -> VerificationError {
        switch error {
        case .unknownKeyID(let id): return .unknownKeyID(id)
        case .invalidPayloadEncoding: return .invalidPayloadEncoding
        case .invalidSignatureEncoding: return .invalidSignatureEncoding
        case .signatureVerificationFailed: return .signatureVerificationFailed
        case .payloadDecodeFailed(let message): return .payloadDecodeFailed(message)
        case .unsupportedSchemaVersion(let version): return .unsupportedSchemaVersion(version)
        case .wrongCatalogKind(let kind): return .wrongCatalogKind(kind)
        case .revisionNotMonotonic(let received, let current):
            return .revisionNotMonotonic(received: received, current: current)
        case .futureTimestamp(let timestamp): return .futureTimestamp(timestamp)
        }
    }
}
