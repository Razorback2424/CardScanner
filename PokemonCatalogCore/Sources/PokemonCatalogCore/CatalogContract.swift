import CryptoKit
import Foundation

/// The wire contract shared by the iOS client and the publisher.
///
/// This module deliberately has no UIKit or app-target dependency. The app can
/// therefore verify a release in its normal runtime while the macOS publisher
/// and CI use the same bytes and validation rules.
public enum PokemonCatalogCoreContract {
    public static let releaseSchemaVersion = 1
    public static let snapshotSchemaVersion = 1
    public static let rulesVersion = 1
}

public struct PokemonCatalogReleaseEnvelope: Codable, Equatable, Sendable {
    public let keyID: String
    public let payload: String
    public let signature: String

    public init(keyID: String, payload: String, signature: String) {
        self.keyID = keyID
        self.payload = payload
        self.signature = signature
    }
}

public struct PokemonCatalogRelease: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = PokemonCatalogCoreContract.releaseSchemaVersion

    public let schemaVersion: Int
    public let revision: Int
    public let generatedAt: Date
    public let sets: [PokemonCatalogSetDescriptor]

    public init(
        schemaVersion: Int = PokemonCatalogRelease.currentSchemaVersion,
        revision: Int,
        generatedAt: Date,
        sets: [PokemonCatalogSetDescriptor]
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.generatedAt = generatedAt
        self.sets = sets
    }
}

/// A provider-backed membership list for a product whose physical printed
/// identities are not represented by the provider's local IDs. The provider
/// card ID remains the stable lookup key; the printed identity is the signed
/// recognition evidence used by the scanner.
public struct PokemonCatalogMembershipRecognition: Codable, Equatable, Hashable, Sendable {
    public struct Member: Codable, Equatable, Hashable, Sendable {
        public let providerCardID: String
        public let canonicalName: String
        public let printedLocalID: String
        public let printedDenominator: Int

        public init(
            providerCardID: String,
            canonicalName: String,
            printedLocalID: String,
            printedDenominator: Int
        ) {
            self.providerCardID = providerCardID
            self.canonicalName = canonicalName
            self.printedLocalID = printedLocalID
            self.printedDenominator = printedDenominator
        }
    }

    public let members: [Member]

    public init(members: [Member]) {
        self.members = members
    }
}

public struct PokemonCatalogSetDescriptor: Codable, Equatable, Hashable, Sendable {
    public enum RecognitionKind: String, Codable, Sendable {
        case expansion
        case promo
        case notScannable
    }

    public let providerSetID: String
    public let displayName: String?
    public let releaseDate: String?
    public let releaseOrder: Int?
    public let recognitionKind: RecognitionKind

    public let printedCode: String?
    public let officialCount: Int?

    public let printedPrefix: String?
    public let catalogLocalIDPrefix: String?
    public let localIDPadWidth: Int?

    public let scanEnabled: Bool
    public let logoURL: String?
    public let symbolURL: String?
    /// Optional parent set identity used only by the publisher to explain an
    /// inherited artwork URL. The client receives the resolved URL and does
    /// not construct provider paths from this value.
    public let parentProviderSetID: String?
    /// Optional reviewed source identifier for a bundled logo/symbol pair.
    /// This keeps the app's local-artwork availability mapping in signed
    /// catalog data for newly discovered sets while remaining optional for
    /// legacy releases.
    public let bundledArtworkSourceID: String?
    public let rulesVersion: Int
    public let membershipRecognition: PokemonCatalogMembershipRecognition?

    public init(
        providerSetID: String,
        displayName: String?,
        releaseDate: String?,
        releaseOrder: Int?,
        recognitionKind: RecognitionKind,
        printedCode: String?,
        officialCount: Int?,
        printedPrefix: String?,
        catalogLocalIDPrefix: String?,
        localIDPadWidth: Int?,
        scanEnabled: Bool,
        logoURL: String?,
        symbolURL: String?,
        parentProviderSetID: String? = nil,
        bundledArtworkSourceID: String? = nil,
        rulesVersion: Int = PokemonCatalogCoreContract.rulesVersion,
        membershipRecognition: PokemonCatalogMembershipRecognition? = nil
    ) {
        self.providerSetID = providerSetID
        self.displayName = displayName
        self.releaseDate = releaseDate
        self.releaseOrder = releaseOrder
        self.recognitionKind = recognitionKind
        self.printedCode = printedCode
        self.officialCount = officialCount
        self.printedPrefix = printedPrefix
        self.catalogLocalIDPrefix = catalogLocalIDPrefix
        self.localIDPadWidth = localIDPadWidth
        self.scanEnabled = scanEnabled
        self.logoURL = logoURL
        self.symbolURL = symbolURL
        self.parentProviderSetID = parentProviderSetID
        self.bundledArtworkSourceID = bundledArtworkSourceID
        self.rulesVersion = rulesVersion
        self.membershipRecognition = membershipRecognition
    }

    public func catalogLocalID(number: Int) -> String? {
        guard recognitionKind == .promo,
              let prefix = catalogLocalIDPrefix,
              let padWidth = localIDPadWidth else { return nil }
        return prefix + String(format: "%0\(padWidth)d", number)
    }
}

public enum PokemonCatalogBase64URL {
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

public enum PokemonCatalogJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder().encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder().decode(type, from: data)
    }
}

public enum PokemonCatalogSignatureError: Error, CustomStringConvertible, Sendable {
    case unknownKeyID(String)
    case invalidPayloadEncoding
    case invalidSignatureEncoding
    case signatureVerificationFailed
    case payloadDecodeFailed(String)
    case unsupportedSchemaVersion(Int)
    case revisionNotMonotonic(received: Int, current: Int)
    case futureTimestamp(Date)

    public var description: String {
        switch self {
        case .unknownKeyID(let id): return "Unknown key ID: \(id)"
        case .invalidPayloadEncoding: return "Payload is not valid base64url"
        case .invalidSignatureEncoding: return "Signature is not valid base64url"
        case .signatureVerificationFailed: return "Signature verification failed"
        case .payloadDecodeFailed(let message): return "Payload decode failed: \(message)"
        case .unsupportedSchemaVersion(let version):
            return "Unsupported schema version: \(version)"
        case .revisionNotMonotonic(let received, let current):
            return "Revision \(received) is not greater than current \(current)"
        case .futureTimestamp(let date): return "Generated timestamp \(date) is in the future"
        }
    }
}

public enum PokemonCatalogSignatureVerifier {
    public struct PinnedKey: Sendable {
        public let id: String
        public let publicKey: Curve25519.Signing.PublicKey

        public init(id: String, publicKey: Curve25519.Signing.PublicKey) {
            self.id = id
            self.publicKey = publicKey
        }
    }

    public static func verify(
        envelope: PokemonCatalogReleaseEnvelope,
        currentRevision: Int? = nil,
        now: Date = Date(),
        maxFutureSkew: TimeInterval = 3600,
        keys: [PinnedKey]
    ) throws -> PokemonCatalogRelease {
        guard let publicKey = keys.first(where: { $0.id == envelope.keyID })?.publicKey else {
            throw PokemonCatalogSignatureError.unknownKeyID(envelope.keyID)
        }
        guard let payloadData = PokemonCatalogBase64URL.decode(envelope.payload) else {
            throw PokemonCatalogSignatureError.invalidPayloadEncoding
        }
        guard let signatureData = PokemonCatalogBase64URL.decode(envelope.signature) else {
            throw PokemonCatalogSignatureError.invalidSignatureEncoding
        }
        guard publicKey.isValidSignature(signatureData, for: payloadData) else {
            throw PokemonCatalogSignatureError.signatureVerificationFailed
        }

        let release: PokemonCatalogRelease
        do {
            release = try PokemonCatalogJSON.decode(PokemonCatalogRelease.self, from: payloadData)
        } catch {
            throw PokemonCatalogSignatureError.payloadDecodeFailed(String(describing: error))
        }

        guard release.schemaVersion == PokemonCatalogRelease.currentSchemaVersion else {
            throw PokemonCatalogSignatureError.unsupportedSchemaVersion(release.schemaVersion)
        }
        if let currentRevision {
            guard release.revision > currentRevision else {
                throw PokemonCatalogSignatureError.revisionNotMonotonic(
                    received: release.revision,
                    current: currentRevision
                )
            }
        }
        guard release.generatedAt <= now.addingTimeInterval(maxFutureSkew) else {
            throw PokemonCatalogSignatureError.futureTimestamp(release.generatedAt)
        }

        try PokemonCatalogReleaseValidator.validate(release)
        return release
    }

    public static func sign(
        release: PokemonCatalogRelease,
        privateKey: Curve25519.Signing.PrivateKey,
        keyID: String
    ) throws -> PokemonCatalogReleaseEnvelope {
        let payloadData = try PokemonCatalogJSON.encode(release)
        let signature = try privateKey.signature(for: payloadData)
        return PokemonCatalogReleaseEnvelope(
            keyID: keyID,
            payload: PokemonCatalogBase64URL.encode(payloadData),
            signature: PokemonCatalogBase64URL.encode(signature)
        )
    }
}

public enum PokemonCatalogReleaseValidator {
    public struct ValidationConfiguration: Sendable {
        public let supportedRulesVersion: Int

        public init(
            supportedRulesVersion: Int = PokemonCatalogCoreContract.rulesVersion
        ) {
            self.supportedRulesVersion = supportedRulesVersion
        }
    }

    public enum ValidationError: Error, CustomStringConvertible, Sendable {
        case invalidRevision
        case emptyProviderSetID
        case duplicateProviderSetID(String)
        case duplicatePrintedCode(String)
        case duplicatePrintedPrefix(String)
        case crossNamespaceCollision(String)
        case unsupportedRulesVersion(Int)
        case invalidDescriptor(String)
        case OCRConfusableCodeCollision(first: String, second: String, denominator: Int)

        public var description: String {
            switch self {
            case .invalidRevision: return "Release revision must be positive"
            case .emptyProviderSetID: return "A set descriptor has an empty provider ID"
            case .duplicateProviderSetID(let id): return "Duplicate provider set ID: \(id)"
            case .duplicatePrintedCode(let code): return "Duplicate printed code: \(code)"
            case .duplicatePrintedPrefix(let prefix): return "Duplicate promo prefix: \(prefix)"
            case .crossNamespaceCollision(let value):
                return "Expansion/promo namespace collision: \(value)"
            case .unsupportedRulesVersion(let version):
                return "Unsupported catalog rules version: \(version)"
            case .invalidDescriptor(let reason): return "Invalid catalog descriptor: \(reason)"
            case let .OCRConfusableCodeCollision(first, second, denominator):
                return "OCR-confusable scan codes \(first) and \(second) share denominator \(denominator)"
            }
        }
    }

    public static func validate(
        _ release: PokemonCatalogRelease,
        configuration: ValidationConfiguration = .init()
    ) throws {
        guard release.revision > 0 else { throw ValidationError.invalidRevision }
        var providers = Set<String>()
        var expansionCodes = Set<String>()
        var promoPrefixes = Set<String>()

        for descriptor in release.sets {
            let providerID = descriptor.providerSetID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !providerID.isEmpty else { throw ValidationError.emptyProviderSetID }
            let providerKey = providerID.lowercased()
            guard providers.insert(providerKey).inserted else {
                throw ValidationError.duplicateProviderSetID(providerID)
            }
            guard descriptor.rulesVersion <= configuration.supportedRulesVersion else {
                throw ValidationError.unsupportedRulesVersion(descriptor.rulesVersion)
            }
            guard descriptor.releaseOrder == nil || descriptor.releaseOrder! >= 0 else {
                throw ValidationError.invalidDescriptor("release order must be non-negative")
            }
            try validateMembershipRecognition(descriptor.membershipRecognition)

            switch descriptor.recognitionKind {
            case .expansion:
                guard let code = descriptor.printedCode,
                      isValidExpansionCode(code) else {
                    throw ValidationError.invalidDescriptor(
                        "expansions require a three-character printed code"
                    )
                }
                guard let count = descriptor.officialCount, (1...10_000).contains(count) else {
                    throw ValidationError.invalidDescriptor(
                        "expansions require an official count between 1 and 10,000"
                    )
                }
                let normalized = code.uppercased()
                guard expansionCodes.insert(normalized).inserted else {
                    throw ValidationError.duplicatePrintedCode(code)
                }
            case .promo:
                guard let prefix = descriptor.printedPrefix,
                      isValidPromoPrefix(prefix),
                      let width = descriptor.localIDPadWidth,
                      (1...6).contains(width),
                      descriptor.catalogLocalIDPrefix != nil else {
                    throw ValidationError.invalidDescriptor(
                        "promos require a prefix, catalog prefix, and pad width"
                    )
                }
                guard descriptor.officialCount == nil else {
                    throw ValidationError.invalidDescriptor(
                        "promo descriptors must not claim an expansion denominator"
                    )
                }
                let normalized = prefix.uppercased()
                guard promoPrefixes.insert(normalized).inserted else {
                    throw ValidationError.duplicatePrintedPrefix(prefix)
                }
            case .notScannable:
                guard !descriptor.scanEnabled else {
                    throw ValidationError.invalidDescriptor(
                        "not-scannable descriptors must have scanEnabled=false"
                    )
                }
            }
        }

        for code in expansionCodes where promoPrefixes.contains(code) {
            throw ValidationError.crossNamespaceCollision(code)
        }

        let scanableExpansions = release.sets.compactMap { descriptor -> (String, Int)? in
            guard descriptor.recognitionKind == .expansion,
                  descriptor.scanEnabled,
                  let code = descriptor.printedCode,
                  let count = descriptor.officialCount else { return nil }
            return (code.uppercased(), count)
        }
        for index in scanableExpansions.indices {
            for otherIndex in scanableExpansions.indices where otherIndex > index {
                let first = scanableExpansions[index]
                let second = scanableExpansions[otherIndex]
                guard first.1 == second.1,
                      areOCRConfusable(first.0, second.0) else { continue }
                throw ValidationError.OCRConfusableCodeCollision(
                    first: first.0,
                    second: second.0,
                    denominator: first.1
                )
            }
        }
    }

    public static func isValidExpansionCode(_ value: String) -> Bool {
        let characters = Array(value.uppercased())
        return characters.count == 3
            && characters.allSatisfy { $0.isLetter || $0.isNumber }
    }

    private static func isValidPromoPrefix(_ value: String) -> Bool {
        let characters = Array(value.uppercased())
        return (2...6).contains(characters.count)
            && characters.allSatisfy { $0.isLetter || $0.isNumber }
    }

    private static func validateMembershipRecognition(
        _ recognition: PokemonCatalogMembershipRecognition?
    ) throws {
        guard let recognition else { return }
        guard !recognition.members.isEmpty else {
            throw ValidationError.invalidDescriptor(
                "membership recognition requires at least one member"
            )
        }

        var providerCardIDs = Set<String>()
        var physicalIdentities = Set<String>()
        for member in recognition.members {
            let providerCardID = member.providerCardID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !providerCardID.isEmpty else {
                throw ValidationError.invalidDescriptor(
                    "membership rows require a provider card ID"
                )
            }
            guard providerCardIDs.insert(providerCardID.lowercased()).inserted else {
                throw ValidationError.invalidDescriptor(
                    "membership rows must have unique provider card IDs"
                )
            }

            let canonicalName = canonicalMembershipName(member.canonicalName)
            guard !canonicalName.isEmpty else {
                throw ValidationError.invalidDescriptor(
                    "membership rows require a canonical name"
                )
            }
            guard isPrintedLocalID(member.printedLocalID) else {
                throw ValidationError.invalidDescriptor(
                    "membership rows require a printed local ID containing digits"
                )
            }
            guard (1...10_000).contains(member.printedDenominator) else {
                throw ValidationError.invalidDescriptor(
                    "membership rows require a printed denominator between 1 and 10,000"
                )
            }

            let physicalIdentity = "\(canonicalName)|\(canonicalLocalID(member.printedLocalID))/\(member.printedDenominator)"
            guard physicalIdentities.insert(physicalIdentity).inserted else {
                throw ValidationError.invalidDescriptor(
                    "membership rows must have unique canonical name and printed identity pairs"
                )
            }
        }
    }

    private static func isPrintedLocalID(_ value: String) -> Bool {
        let characters = Array(value.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !characters.isEmpty else { return false }
        var index = 0
        while index < characters.count, characters[index].isLetter {
            index += 1
        }
        let digitStart = index
        while index < characters.count, characters[index].isNumber {
            index += 1
        }
        guard index > digitStart else { return false }
        return characters[index...].allSatisfy(\.isLetter)
    }

    private static func canonicalMembershipName(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).replacingOccurrences(of: "&", with: " and ")
        return folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : " "
        }
        .joined()
        .split(whereSeparator: { $0 == " " })
        .joined(separator: " ")
    }

    private static func canonicalLocalID(_ value: String) -> String {
        let compact = value.uppercased().filter { !$0.isWhitespace }
        let prefix = compact.prefix { $0.isLetter }
        let suffix = compact.dropFirst(prefix.count)
        guard let number = Int(suffix) else { return compact }
        return "\(prefix)\(number)"
    }

    private static func areOCRConfusable(_ first: String, _ second: String) -> Bool {
        let firstCharacters = Array(first)
        let secondCharacters = Array(second)
        guard firstCharacters.count == secondCharacters.count else { return false }
        var differingPairs: [(Character, Character)] = []
        for (lhs, rhs) in zip(firstCharacters, secondCharacters) where lhs != rhs {
            differingPairs.append((lhs, rhs))
        }
        guard differingPairs.count == 1 else { return false }
        let pair = differingPairs[0]
        let confusable: Set<Set<Character>> = [
            ["0", "O"], ["1", "I"], ["1", "L"], ["2", "Z"],
            ["5", "S"], ["6", "G"], ["8", "B"]
        ]
        return confusable.contains { $0.contains(pair.0) && $0.contains(pair.1) }
    }
}
