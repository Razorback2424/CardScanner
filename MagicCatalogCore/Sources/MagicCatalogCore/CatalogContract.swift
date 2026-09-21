import CryptoKit
import Foundation

public enum MagicCatalogCoreContract {
    public static let releaseSchemaVersion = 1
    public static let rulesVersion = 1
    public static let catalogKind = "magic"
    public static let approvedIconHosts: Set<String> = [
        "svgs.scryfall.io"
    ]
}

public enum MagicCatalogRoutingKind: String, Codable, Equatable, Hashable, Sendable {
    case token
    case artCard
}

/// The complete descriptor used by all three Magic authority consumers.
///
/// Dates intentionally remain wire-format strings. Scryfall publishes a
/// calendar day, and converting that value to an absolute instant in the
/// publisher would make an otherwise stable catalog depend on a time zone.
public struct MagicCatalogSetDescriptor: Codable, Equatable, Hashable, Sendable {
    public let scryfallSetID: String
    public let code: String
    public let displayName: String
    public let releaseDate: String?
    public let setType: String
    public let printedSize: Int?
    public let cardCount: Int?
    public let iconSVGURL: URL?
    public let parentSetCode: String?
    public let routingKind: MagicCatalogRoutingKind?
    public let scanEnabled: Bool
    public let browseEnabled: Bool

    public init(
        scryfallSetID: String,
        code: String,
        displayName: String,
        releaseDate: String?,
        setType: String,
        printedSize: Int?,
        cardCount: Int?,
        iconSVGURL: URL?,
        parentSetCode: String?,
        routingKind: MagicCatalogRoutingKind?,
        scanEnabled: Bool,
        browseEnabled: Bool
    ) {
        self.scryfallSetID = scryfallSetID
        self.code = code
        self.displayName = displayName
        self.releaseDate = releaseDate
        self.setType = setType
        self.printedSize = printedSize
        self.cardCount = cardCount
        self.iconSVGURL = iconSVGURL
        self.parentSetCode = parentSetCode
        self.routingKind = routingKind
        self.scanEnabled = scanEnabled
        self.browseEnabled = browseEnabled
    }
}

public struct MagicCatalogRelease: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = MagicCatalogCoreContract.releaseSchemaVersion
    public static let currentCatalogKind = MagicCatalogCoreContract.catalogKind

    public let schemaVersion: Int
    public let catalogKind: String
    public let revision: Int
    public let generatedAt: String
    public let sets: [MagicCatalogSetDescriptor]

    public init(
        schemaVersion: Int = MagicCatalogRelease.currentSchemaVersion,
        catalogKind: String = MagicCatalogRelease.currentCatalogKind,
        revision: Int,
        generatedAt: String,
        sets: [MagicCatalogSetDescriptor]
    ) {
        self.schemaVersion = schemaVersion
        self.catalogKind = catalogKind
        self.revision = revision
        self.generatedAt = generatedAt
        self.sets = sets
    }
}

public struct MagicCatalogReleaseEnvelope: Codable, Equatable, Sendable {
    public let keyID: String
    public let payload: String
    public let signature: String

    public init(keyID: String, payload: String, signature: String) {
        self.keyID = keyID
        self.payload = payload
        self.signature = signature
    }
}

public enum MagicCatalogDate {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public static func parseDay(_ raw: String?) -> Date? {
        guard let raw, raw.count == 10 else { return nil }
        guard let date = dayFormatter.date(from: raw), formatDay(date) == raw else {
            return nil
        }
        return date
    }

    public static func parseTimestamp(_ raw: String) -> Date? {
        if let date = isoFormatter.date(from: raw) { return date }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: raw)
    }

    public static func formatDay(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    public static func formatTimestamp(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }
}

public enum MagicCatalogBase64URL {
    public static func decode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }

    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public enum MagicCatalogJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        JSONDecoder()
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder().encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder().decode(type, from: data)
    }
}

public enum MagicCatalogSignatureError: Error, CustomStringConvertible, Sendable, Equatable {
    case unknownKeyID(String)
    case invalidPayloadEncoding
    case invalidSignatureEncoding
    case signatureVerificationFailed
    case payloadDecodeFailed(String)
    case unsupportedSchemaVersion(Int)
    case wrongCatalogKind(String)
    case revisionNotMonotonic(received: Int, current: Int)
    case futureTimestamp(String)

    public var description: String {
        switch self {
        case .unknownKeyID(let id): return "Unknown Magic catalog key ID: \(id)"
        case .invalidPayloadEncoding: return "Magic catalog payload is not valid base64url"
        case .invalidSignatureEncoding: return "Magic catalog signature is not valid base64url"
        case .signatureVerificationFailed: return "Magic catalog signature verification failed"
        case .payloadDecodeFailed(let message): return "Magic catalog payload decode failed: \(message)"
        case .unsupportedSchemaVersion(let version):
            return "Unsupported Magic catalog schema version: \(version)"
        case .wrongCatalogKind(let kind):
            return "Expected Magic catalog kind, received: \(kind)"
        case .revisionNotMonotonic(let received, let current):
            return "Magic catalog revision \(received) is not greater than current \(current)"
        case .futureTimestamp(let timestamp):
            return "Magic catalog timestamp is in the future: \(timestamp)"
        }
    }
}

public enum MagicCatalogSignatureVerifier {
    public struct PinnedKey: Sendable {
        public let id: String
        public let publicKey: Curve25519.Signing.PublicKey

        public init(id: String, publicKey: Curve25519.Signing.PublicKey) {
            self.id = id
            self.publicKey = publicKey
        }
    }

    public static func verify(
        envelope: MagicCatalogReleaseEnvelope,
        currentRevision: Int? = nil,
        now: Date = Date(),
        maxFutureSkew: TimeInterval = 3600,
        keys: [PinnedKey]
    ) throws -> MagicCatalogRelease {
        guard let publicKey = keys.first(where: { $0.id == envelope.keyID })?.publicKey else {
            throw MagicCatalogSignatureError.unknownKeyID(envelope.keyID)
        }
        guard let payloadData = MagicCatalogBase64URL.decode(envelope.payload) else {
            throw MagicCatalogSignatureError.invalidPayloadEncoding
        }
        guard let signatureData = MagicCatalogBase64URL.decode(envelope.signature) else {
            throw MagicCatalogSignatureError.invalidSignatureEncoding
        }
        guard publicKey.isValidSignature(signatureData, for: payloadData) else {
            throw MagicCatalogSignatureError.signatureVerificationFailed
        }

        let release: MagicCatalogRelease
        do {
            release = try MagicCatalogJSON.decode(MagicCatalogRelease.self, from: payloadData)
        } catch {
            throw MagicCatalogSignatureError.payloadDecodeFailed(String(describing: error))
        }

        guard release.schemaVersion == MagicCatalogRelease.currentSchemaVersion else {
            throw MagicCatalogSignatureError.unsupportedSchemaVersion(release.schemaVersion)
        }
        guard release.catalogKind == MagicCatalogRelease.currentCatalogKind else {
            throw MagicCatalogSignatureError.wrongCatalogKind(release.catalogKind)
        }
        if let currentRevision {
            guard release.revision > currentRevision else {
                throw MagicCatalogSignatureError.revisionNotMonotonic(
                    received: release.revision,
                    current: currentRevision
                )
            }
        }
        guard let timestamp = MagicCatalogDate.parseTimestamp(release.generatedAt),
              timestamp <= now.addingTimeInterval(maxFutureSkew) else {
            throw MagicCatalogSignatureError.futureTimestamp(release.generatedAt)
        }

        try MagicCatalogReleaseValidator.validate(release)
        return release
    }

    public static func sign(
        release: MagicCatalogRelease,
        privateKey: Curve25519.Signing.PrivateKey,
        keyID: String
    ) throws -> MagicCatalogReleaseEnvelope {
        let payloadData = try MagicCatalogJSON.encode(release)
        let signature = try privateKey.signature(for: payloadData)
        return MagicCatalogReleaseEnvelope(
            keyID: keyID,
            payload: MagicCatalogBase64URL.encode(payloadData),
            signature: MagicCatalogBase64URL.encode(signature)
        )
    }
}

public enum MagicCatalogReleaseValidator {
    public enum ValidationError: Error, CustomStringConvertible, Sendable, Equatable {
        case invalidRevision
        case invalidGeneratedAt
        case emptyScryfallSetID
        case emptyCode
        case invalidCode(String)
        case emptyDisplayName(String)
        case emptySetType(String)
        case duplicateScryfallSetID(String)
        case duplicateCode(String)
        case identityMismatch(uuid: String, firstCode: String, secondCode: String)
        case codeIdentityMismatch(code: String, firstUUID: String, secondUUID: String)
        case invalidPrintedSize(String)
        case invalidCardCount(String)
        case invalidReleaseDate(String)
        case invalidIconSVGURL(code: String, url: String)
        case routingChildMissingParent(String)
        case routingChildMissingParentCode(String)
        case routingChildMayNotScan(String)
        case routingChildMayNotBrowse(String)
        case nonRoutingDescriptorHasParent(String)

        public var description: String {
            switch self {
            case .invalidRevision: return "Magic catalog revision must be positive"
            case .invalidGeneratedAt: return "Magic catalog generatedAt must be ISO-8601"
            case .emptyScryfallSetID: return "Magic descriptor has an empty Scryfall UUID"
            case .emptyCode: return "Magic descriptor has an empty set code"
            case .invalidCode(let code): return "Invalid Magic set code: \(code)"
            case .emptyDisplayName(let code): return "Magic descriptor \(code) has an empty display name"
            case .emptySetType(let code): return "Magic descriptor \(code) has an empty set type"
            case .duplicateScryfallSetID(let id): return "Duplicate Scryfall UUID: \(id)"
            case .duplicateCode(let code): return "Duplicate normalized Magic set code: \(code)"
            case let .identityMismatch(uuid, firstCode, secondCode):
                return "Scryfall UUID \(uuid) maps to both \(firstCode) and \(secondCode)"
            case let .codeIdentityMismatch(code, firstUUID, secondUUID):
                return "Magic code \(code) maps to both \(firstUUID) and \(secondUUID)"
            case .invalidPrintedSize(let code): return "Invalid printed size for Magic set \(code)"
            case .invalidCardCount(let code): return "Invalid card count for Magic set \(code)"
            case .invalidReleaseDate(let code): return "Invalid release date for Magic set \(code)"
            case let .invalidIconSVGURL(code, url):
                return "Invalid iconSVGURL for Magic set \(code): \(url)"
            case .routingChildMissingParent(let code):
                return "Routing child \(code) references a nonexistent parent set"
            case .routingChildMissingParentCode(let code):
                return "Routing child \(code) is missing parentSetCode"
            case .routingChildMayNotScan(let code):
                return "Routing child \(code) may not be scanner-enabled"
            case .routingChildMayNotBrowse(let code):
                return "Routing child \(code) may not be Browse-visible"
            case .nonRoutingDescriptorHasParent(let code):
                return "Non-routing descriptor \(code) unexpectedly has parentSetCode"
            }
        }
    }

    public static func normalizedCode(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func validate(_ release: MagicCatalogRelease) throws {
        guard release.revision > 0 else { throw ValidationError.invalidRevision }
        guard MagicCatalogDate.parseTimestamp(release.generatedAt) != nil else {
            throw ValidationError.invalidGeneratedAt
        }

        var ids: [String: String] = [:]
        var codes: [String: String] = [:]
        var descriptorsByCode: [String: MagicCatalogSetDescriptor] = [:]

        for descriptor in release.sets {
            let code = normalizedCode(descriptor.code)
            let uuid = descriptor.scryfallSetID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !uuid.isEmpty else { throw ValidationError.emptyScryfallSetID }
            guard !code.isEmpty else { throw ValidationError.emptyCode }
            guard (1...8).contains(code.count),
                  code.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
                throw ValidationError.invalidCode(descriptor.code)
            }
            guard !descriptor.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.emptyDisplayName(descriptor.code)
            }
            guard !descriptor.setType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.emptySetType(descriptor.code)
            }
            if let printedSize = descriptor.printedSize, !(1...100_000).contains(printedSize) {
                throw ValidationError.invalidPrintedSize(descriptor.code)
            }
            if let cardCount = descriptor.cardCount, !(0...100_000).contains(cardCount) {
                throw ValidationError.invalidCardCount(descriptor.code)
            }
            if let releaseDate = descriptor.releaseDate,
               MagicCatalogDate.parseDay(releaseDate) == nil {
                throw ValidationError.invalidReleaseDate(descriptor.code)
            }
            if let iconURL = descriptor.iconSVGURL {
                // A query is allowed, and only a query. Scryfall stamps every
                // set icon with a `?<timestamp>` cache-buster — all 910 URLs in
                // the bundled seed carry one — so rejecting queries rejects the
                // provider's real data, including releases already signed and
                // published. The host allowlist is what makes the URL safe;
                // once the origin is pinned, its query string cannot redirect
                // the fetch anywhere else.
                let host = iconURL.host?.lowercased()
                let isValid = iconURL.scheme == "https"
                    && host.map(MagicCatalogCoreContract.approvedIconHosts.contains) == true
                    && iconURL.user == nil
                    && iconURL.password == nil
                    && iconURL.port == nil
                    && iconURL.fragment == nil
                    && !iconURL.path.isEmpty
                guard isValid else {
                    throw ValidationError.invalidIconSVGURL(
                        code: descriptor.code,
                        url: iconURL.absoluteString
                    )
                }
            }

            if let existing = ids[uuid], existing != descriptor.code {
                throw ValidationError.identityMismatch(
                    uuid: uuid,
                    firstCode: existing,
                    secondCode: descriptor.code
                )
            }
            if let existing = codes[code], existing != uuid {
                throw ValidationError.codeIdentityMismatch(
                    code: code,
                    firstUUID: existing,
                    secondUUID: uuid
                )
            }
            guard ids[uuid] == nil else { throw ValidationError.duplicateScryfallSetID(uuid) }
            guard codes[code] == nil else { throw ValidationError.duplicateCode(descriptor.code) }
            ids[uuid] = descriptor.code
            codes[code] = uuid
            descriptorsByCode[code] = descriptor

            if let routingKind = descriptor.routingKind {
                _ = routingKind
                guard let parent = descriptor.parentSetCode,
                      !normalizedCode(parent).isEmpty else {
                    throw ValidationError.routingChildMissingParentCode(descriptor.code)
                }
                guard !descriptor.scanEnabled else {
                    throw ValidationError.routingChildMayNotScan(descriptor.code)
                }
                guard !descriptor.browseEnabled else {
                    throw ValidationError.routingChildMayNotBrowse(descriptor.code)
                }
            } else if descriptor.parentSetCode != nil {
                throw ValidationError.nonRoutingDescriptorHasParent(descriptor.code)
            }

            if descriptor.scanEnabled {
                guard (3...4).contains(code.count) else {
                    throw ValidationError.invalidCode(descriptor.code)
                }
            }
        }

        for descriptor in release.sets where descriptor.routingKind != nil {
            let parent = normalizedCode(descriptor.parentSetCode ?? "")
            guard descriptorsByCode[parent] != nil else {
                throw ValidationError.routingChildMissingParent(descriptor.code)
            }
        }
    }
}
