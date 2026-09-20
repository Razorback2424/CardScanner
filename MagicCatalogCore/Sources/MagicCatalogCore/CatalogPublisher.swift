import CryptoKit
import Foundation

public enum MagicCatalogPublicationEnvironment: String, Sendable {
    case production
    case staging

    public var path: String { "magic/v1" }
}

public struct MagicCatalogSignedBuild: Sendable {
    public let build: MagicCatalogBuildResult
    public let envelope: MagicCatalogReleaseEnvelope

    public init(build: MagicCatalogBuildResult, envelope: MagicCatalogReleaseEnvelope) {
        self.build = build
        self.envelope = envelope
    }
}

public enum MagicCatalogSigningKeyLoader {
    public enum Error: Swift.Error, CustomStringConvertible, Sendable {
        case notProtectedEnvironment
        case missingEnvironment(String)
        case invalidPrivateKey

        public var description: String {
            switch self {
            case .notProtectedEnvironment:
                return "Magic catalog signing is allowed only in the protected publication environment"
            case .missingEnvironment(let name): return "Missing required environment variable \(name)"
            case .invalidPrivateKey: return "MAGIC_CATALOG_SIGNING_KEY is not a 32-byte base64url key"
            }
        }
    }

    public static func load(environment: MagicCatalogPublicationEnvironment) throws
        -> (privateKey: Curve25519.Signing.PrivateKey, keyID: String) {
        guard environment == .production,
              ProcessInfo.processInfo.environment["GITHUB_ENVIRONMENT"] == "magic-catalog-production" else {
            throw Error.notProtectedEnvironment
        }
        let variables = ProcessInfo.processInfo.environment
        guard let rawKey = variables["MAGIC_CATALOG_SIGNING_KEY"], !rawKey.isEmpty else {
            throw Error.missingEnvironment("MAGIC_CATALOG_SIGNING_KEY")
        }
        guard let keyID = variables["MAGIC_CATALOG_KEY_ID"], !keyID.isEmpty else {
            throw Error.missingEnvironment("MAGIC_CATALOG_KEY_ID")
        }
        guard let data = MagicCatalogBase64URL.decode(rawKey), data.count == 32,
              let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else {
            throw Error.invalidPrivateKey
        }
        return (privateKey, keyID)
    }
}

public enum MagicCatalogSigner {
    public static func sign(
        _ build: MagicCatalogBuildResult,
        privateKey: Curve25519.Signing.PrivateKey,
        keyID: String
    ) throws -> MagicCatalogSignedBuild {
        let envelope = try MagicCatalogSignatureVerifier.sign(
            release: build.release,
            privateKey: privateKey,
            keyID: keyID
        )
        return MagicCatalogSignedBuild(build: build, envelope: envelope)
    }
}

public struct MagicCatalogPublicationReceipt: Sendable {
    public let environment: MagicCatalogPublicationEnvironment
    public let revision: Int
    public let immutableObjectPath: String
    public let currentPointerPath: String

    public init(
        environment: MagicCatalogPublicationEnvironment,
        revision: Int,
        immutableObjectPath: String,
        currentPointerPath: String
    ) {
        self.environment = environment
        self.revision = revision
        self.immutableObjectPath = immutableObjectPath
        self.currentPointerPath = currentPointerPath
    }
}

public enum MagicCatalogPublisherError: Error, CustomStringConvertible, Sendable, Equatable {
    case immutableRevisionConflict(Int)
    case activeRevisionNotMonotonic(received: Int, current: Int)

    public var description: String {
        switch self {
        case .immutableRevisionConflict(let revision):
            return "Magic catalog immutable revision \(revision) already contains different bytes"
        case let .activeRevisionNotMonotonic(received, current):
            return "Magic catalog revision \(received) is not greater than active revision \(current)"
        }
    }
}

public struct MagicCatalogFilesystemPublisher: Sendable {
    public let root: URL
    public let environment: MagicCatalogPublicationEnvironment

    public init(root: URL, environment: MagicCatalogPublicationEnvironment) {
        self.root = root
        self.environment = environment
    }

    public func publish(
        _ signedBuild: MagicCatalogSignedBuild,
        activeRelease: MagicCatalogRelease? = nil
    ) throws -> MagicCatalogPublicationReceipt {
        let revision = signedBuild.build.release.revision
        if let activeRelease, revision <= activeRelease.revision {
            throw MagicCatalogPublisherError.activeRevisionNotMonotonic(
                received: revision,
                current: activeRelease.revision
            )
        }

        let namespace = root.appendingPathComponent(environment.path, isDirectory: true)
        let releaseDirectory = namespace
            .appendingPathComponent("releases", isDirectory: true)
            .appendingPathComponent(String(revision), isDirectory: true)
        try FileManager.default.createDirectory(
            at: releaseDirectory,
            withIntermediateDirectories: true
        )

        let envelopeData = try MagicCatalogJSON.encode(signedBuild.envelope)
        let payloadData = try MagicCatalogJSON.encode(signedBuild.build.release)
        let reportData = try MagicCatalogJSON.encode(signedBuild.build.report)
        let objects: [(String, Data)] = [
            ("catalog-release.json", envelopeData),
            ("catalog-payload.json", payloadData),
            ("review-report.json", reportData)
        ]
        for (name, data) in objects {
            let path = releaseDirectory.appendingPathComponent(name)
            if let existing = try? Data(contentsOf: path), existing != data {
                throw MagicCatalogPublisherError.immutableRevisionConflict(revision)
            }
            if !FileManager.default.fileExists(atPath: path.path) {
                try data.write(to: path, options: .atomic)
            }
        }
        try Data("complete\n".utf8).write(
            to: releaseDirectory.appendingPathComponent(".complete"),
            options: .atomic
        )

        let currentURL = namespace.appendingPathComponent("current.json")
        try FileManager.default.createDirectory(at: namespace, withIntermediateDirectories: true)
        try envelopeData.write(to: currentURL, options: .atomic)
        return MagicCatalogPublicationReceipt(
            environment: environment,
            revision: revision,
            immutableObjectPath: "\(environment.path)/releases/\(revision)/catalog-release.json",
            currentPointerPath: "\(environment.path)/current.json"
        )
    }

    public func currentEnvelope() throws -> MagicCatalogReleaseEnvelope? {
        let url = root.appendingPathComponent(environment.path, isDirectory: true)
            .appendingPathComponent("current.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try MagicCatalogJSON.decode(MagicCatalogReleaseEnvelope.self, from: data)
    }
}
