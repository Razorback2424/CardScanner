import CryptoKit
import Foundation
import PokemonCatalogCore

/// App-facing compatibility wrapper around the platform-neutral verifier.
/// Registry validation remains an app concern, while signature bytes, schema,
/// timestamp, and release decoding are owned by PokemonCatalogCore.
enum PokemonCatalogSignatureVerifier {
    enum VerificationError: Error, CustomStringConvertible {
        case unknownKeyID(String)
        case invalidPayloadEncoding
        case invalidSignatureEncoding
        case signatureVerificationFailed
        case payloadDecodeFailed(Error)
        case unsupportedSchemaVersion(Int)
        case revisionNotMonotonic(received: Int, current: Int)
        case futureTimestamp(Date)

        var description: String {
            switch self {
            case .unknownKeyID(let id): return "Unknown key ID: \(id)"
            case .invalidPayloadEncoding: return "Payload is not valid base64url"
            case .invalidSignatureEncoding: return "Signature is not valid base64url"
            case .signatureVerificationFailed: return "Signature verification failed"
            case .payloadDecodeFailed(let e): return "Payload decode failed: \(e)"
            case .unsupportedSchemaVersion(let v): return "Unsupported schema version: \(v)"
            case .revisionNotMonotonic(let r, let c): return "Revision \(r) is not greater than current \(c)"
            case .futureTimestamp(let d): return "Generated timestamp \(d) is in the future"
            }
        }
    }

    typealias PinnedKey = PokemonCatalogCore.PokemonCatalogSignatureVerifier.PinnedKey

    /// Public keys are build configuration, not credentials. The value is a
    /// semicolon-separated list of `keyID:base64url-public-key` entries. An
    /// empty or unresolved build setting deliberately leaves the client unable
    /// to activate a remote release; the bundled catalog remains usable.
    static var pinnedKeys: [PinnedKey] {
        configuredPinnedKeys(
            from: Bundle.main.object(forInfoDictionaryKey: "POKEMON_CATALOG_PINNED_KEYS") as? String
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
                  let data = Base64URL.decode(encoded),
                  data.count == 32,
                  let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: data) else {
                return nil
            }
            return PinnedKey(id: id, publicKey: publicKey)
        }
    }

    static func pinnedKey(
        forID id: String,
        in keys: [PinnedKey] = pinnedKeys
    ) -> Curve25519.Signing.PublicKey? {
        keys.first { $0.id == id }?.publicKey
    }

    static func verify(
        envelope: PokemonCatalogReleaseEnvelope,
        currentRevision: Int?,
        now: Date = Date(),
        maxFutureSkew: TimeInterval = 3600,
        keys: [PinnedKey] = pinnedKeys
    ) throws -> PokemonCatalogRelease {
        do {
            return try PokemonCatalogCore.PokemonCatalogSignatureVerifier.verify(
                envelope: envelope,
                currentRevision: currentRevision,
                now: now,
                maxFutureSkew: maxFutureSkew,
                keys: keys
            )
        } catch let error as PokemonCatalogSignatureError {
            throw map(error)
        } catch {
            throw VerificationError.payloadDecodeFailed(error)
        }
    }

    #if DEBUG
    static func sign(
        release: PokemonCatalogRelease,
        privateKey: Curve25519.Signing.PrivateKey,
        keyID: String
    ) throws -> PokemonCatalogReleaseEnvelope {
        try PokemonCatalogCore.PokemonCatalogSignatureVerifier.sign(
            release: release,
            privateKey: privateKey,
            keyID: keyID
        )
    }
    #endif

    private static func map(_ error: PokemonCatalogSignatureError) -> VerificationError {
        switch error {
        case .unknownKeyID(let id): return .unknownKeyID(id)
        case .invalidPayloadEncoding: return .invalidPayloadEncoding
        case .invalidSignatureEncoding: return .invalidSignatureEncoding
        case .signatureVerificationFailed: return .signatureVerificationFailed
        case .payloadDecodeFailed(let message):
            return .payloadDecodeFailed(
                NSError(
                    domain: "PokemonCatalogCore",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            )
        case .unsupportedSchemaVersion(let version): return .unsupportedSchemaVersion(version)
        case .revisionNotMonotonic(let received, let current):
            return .revisionNotMonotonic(received: received, current: current)
        case .futureTimestamp(let date): return .futureTimestamp(date)
        }
    }
}
