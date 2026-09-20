import CryptoKit
import Foundation

public enum PokemonCatalogPublicationEnvironment: String, Codable, Sendable {
    case production
    case staging

    public var path: String {
        switch self {
        case .production: return "v1"
        case .staging: return "staging/v1"
        }
    }
}

public struct PokemonCatalogSignedBuild: Sendable {
    public let build: PokemonCatalogBuildResult
    public let envelope: PokemonCatalogReleaseEnvelope

    public init(
        build: PokemonCatalogBuildResult,
        envelope: PokemonCatalogReleaseEnvelope
    ) {
        self.build = build
        self.envelope = envelope
    }
}

public enum PokemonCatalogPublicationError: Error, CustomStringConvertible, Sendable {
    case immutableRevisionConflict(Int)
    case revisionNotMonotonic(received: Int, current: Int)
    case invalidCurrentPointer
    case publicationInterrupted(String)
    case invalidSigningEnvironment
    case missingSigningSecret
    case invalidSigningSecret
    case missingSigningKeyID

    public var description: String {
        switch self {
        case .immutableRevisionConflict(let revision):
            return "Immutable catalog revision already exists with different bytes: \(revision)"
        case let .revisionNotMonotonic(received, current):
            return "Cannot publish revision \(received) over current revision \(current)"
        case .invalidCurrentPointer:
            return "Cannot publish over an unreadable current catalog pointer"
        case .publicationInterrupted(let reason): return "Publication interrupted: \(reason)"
        case .invalidSigningEnvironment:
            return "Catalog signing is available only to the matching protected GitHub Actions publication job"
        case .missingSigningSecret: return "Catalog signing secret is not available"
        case .invalidSigningSecret: return "Catalog signing secret is not a 32-byte private key"
        case .missingSigningKeyID: return "Catalog signing key ID is not available"
        }
    }
}

public struct PokemonCatalogSigningMaterial: Sendable {
    public let keyID: String
    public let privateKey: Curve25519.Signing.PrivateKey

    public init(keyID: String, privateKey: Curve25519.Signing.PrivateKey) {
        self.keyID = keyID
        self.privateKey = privateKey
    }
}

/// Signs a release after all publisher-side validation has completed.
public enum PokemonCatalogSigner {
    public static func sign(
        _ build: PokemonCatalogBuildResult,
        material: PokemonCatalogSigningMaterial
    ) throws -> PokemonCatalogSignedBuild {
        let envelope = try PokemonCatalogSignatureVerifier.sign(
            release: build.release,
            privateKey: material.privateKey,
            keyID: material.keyID
        )
        return PokemonCatalogSignedBuild(build: build, envelope: envelope)
    }
}

/// Reads a catalog signing key only in a matching GitHub Actions production
/// publication environment. Authority changes use the protected environment;
/// content-only changes use the separately named automatic environment. Local
/// builds and pull-request jobs intentionally cannot reach this path.
public enum PokemonCatalogSigningKeyLoader {
    public static func load(
        environment: PokemonCatalogPublicationEnvironment,
        variables: [String: String] = ProcessInfo.processInfo.environment,
        changeClass: PokemonCatalogChangeClass? = nil
    ) throws -> PokemonCatalogSigningMaterial {
        guard variables["GITHUB_ACTIONS"] == "true",
              variables["GITHUB_EVENT_NAME"] != "pull_request",
              variables["GITHUB_REF"] == "refs/heads/main",
              variables["POKEMON_CATALOG_PUBLISH"] == "true" else {
            throw PokemonCatalogPublicationError.invalidSigningEnvironment
        }
        let githubEnvironment = variables["GITHUB_ENVIRONMENT"] ?? ""
        switch environment {
        case .production:
            guard [
                "pokemon-catalog-production",
                "pokemon-catalog-production-auto"
            ].contains(githubEnvironment) else {
                throw PokemonCatalogPublicationError.invalidSigningEnvironment
            }
            guard githubEnvironment != "pokemon-catalog-production-auto"
                || changeClass == .some(.contentOnly) else {
                throw PokemonCatalogPublicationError.invalidSigningEnvironment
            }

        case .staging:
            guard githubEnvironment == "pokemon-catalog-staging" else {
                throw PokemonCatalogPublicationError.invalidSigningEnvironment
            }
        }
        guard let rawSecret = variables["POKEMON_CATALOG_SIGNING_KEY"],
              !rawSecret.isEmpty else {
            throw PokemonCatalogPublicationError.missingSigningSecret
        }
        guard let keyData = decodePrivateKey(rawSecret) else {
            throw PokemonCatalogPublicationError.invalidSigningSecret
        }
        guard let keyID = variables["POKEMON_CATALOG_KEY_ID"], !keyID.isEmpty else {
            throw PokemonCatalogPublicationError.missingSigningKeyID
        }
        do {
            return PokemonCatalogSigningMaterial(
                keyID: keyID,
                privateKey: try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
            )
        } catch {
            throw PokemonCatalogPublicationError.invalidSigningSecret
        }
    }

    private static func decodePrivateKey(_ value: String) -> Data? {
        if let data = PokemonCatalogBase64URL.decode(value), data.count == 32 {
            return data
        }
        if let data = Data(base64Encoded: value), data.count == 32 {
            return data
        }
        guard value.count == 64,
              value.allSatisfy({ $0.isHexDigit }) else { return nil }
        var result = Data()
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else { return nil }
            result.append(byte)
            index = next
        }
        return result.count == 32 ? result : nil
    }
}

public struct PokemonCatalogPublicationReceipt: Codable, Equatable, Sendable {
    public let environment: PokemonCatalogPublicationEnvironment
    public let revision: Int
    public let immutableObjectPath: String
    public let currentPointerPath: String

    public init(
        environment: PokemonCatalogPublicationEnvironment,
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

/// Filesystem publisher used by the CLI and exercised in CI before Firebase
/// deployment. It writes the revision object completely, then changes the
/// current pointer exactly once and only after the immutable object is durable.
public final class PokemonCatalogFilesystemPublisher: @unchecked Sendable {
    public typealias BeforePointerUpdate = @Sendable () throws -> Void

    private let root: URL
    private let environment: PokemonCatalogPublicationEnvironment
    private let beforePointerUpdate: BeforePointerUpdate?

    public init(
        root: URL,
        environment: PokemonCatalogPublicationEnvironment,
        beforePointerUpdate: BeforePointerUpdate? = nil
    ) {
        self.root = root
        self.environment = environment
        self.beforePointerUpdate = beforePointerUpdate
    }

    public func publish(_ signedBuild: PokemonCatalogSignedBuild) throws -> PokemonCatalogPublicationReceipt {
        let namespace = root.appendingPathComponent(environment.path, isDirectory: true)
        let revisions = namespace.appendingPathComponent("releases", isDirectory: true)
        let revision = signedBuild.build.release.revision
        let revisionDirectory = revisions.appendingPathComponent(String(revision), isDirectory: true)
        let envelopeData = try PokemonCatalogJSON.encode(signedBuild.envelope)

        if FileManager.default.fileExists(atPath: revisionDirectory.path) {
            let existingURL = revisionDirectory.appendingPathComponent("catalog-release.json")
            guard let existing = try? Data(contentsOf: existingURL), existing == envelopeData else {
                throw PokemonCatalogPublicationError.immutableRevisionConflict(revision)
            }
        } else {
            let temporaryDirectory = revisions.appendingPathComponent(
                ".staging-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true
            )
            do {
                try writeRevision(
                    signedBuild,
                    envelopeData: envelopeData,
                    to: temporaryDirectory
                )
                try FileManager.default.createDirectory(
                    at: revisions,
                    withIntermediateDirectories: true
                )
                try FileManager.default.moveItem(at: temporaryDirectory, to: revisionDirectory)
            } catch {
                try? FileManager.default.removeItem(at: temporaryDirectory)
                throw error
            }
        }

        let currentURL = namespace.appendingPathComponent("current.json")
        if FileManager.default.fileExists(atPath: currentURL.path) {
            guard let currentData = try? Data(contentsOf: currentURL),
                  let currentEnvelope = try? PokemonCatalogJSON.decode(
                      PokemonCatalogReleaseEnvelope.self,
                      from: currentData
                  ),
                  let currentPayload = PokemonCatalogBase64URL.decode(currentEnvelope.payload),
                  let currentRelease = try? PokemonCatalogJSON.decode(
                      PokemonCatalogRelease.self,
                      from: currentPayload
                  ) else {
                throw PokemonCatalogPublicationError.invalidCurrentPointer
            }
            if currentRelease.revision >= revision {
                if currentRelease.revision == revision, currentData == envelopeData {
                    return receipt(revision: revision)
                }
                throw PokemonCatalogPublicationError.revisionNotMonotonic(
                    received: revision,
                    current: currentRelease.revision
                )
            }
        }

        try beforePointerUpdate?()
        try FileManager.default.createDirectory(
            at: namespace,
            withIntermediateDirectories: true
        )
        try envelopeData.write(to: currentURL, options: .atomic)
        return receipt(revision: revision)
    }

    public func currentEnvelope() throws -> PokemonCatalogReleaseEnvelope? {
        let url = root.appendingPathComponent(environment.path, isDirectory: true)
            .appendingPathComponent("current.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try PokemonCatalogJSON.decode(PokemonCatalogReleaseEnvelope.self, from: data)
    }

    private func writeRevision(
        _ signedBuild: PokemonCatalogSignedBuild,
        envelopeData: Data,
        to directory: URL
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try envelopeData.write(
            to: directory.appendingPathComponent("catalog-release.json"),
            options: .atomic
        )
        let payloadData = try PokemonCatalogJSON.encode(signedBuild.build.release)
        try payloadData.write(
            to: directory.appendingPathComponent("catalog-payload.json"),
            options: .atomic
        )
        let snapshotData = try PokemonCatalogJSON.encode(signedBuild.build.snapshot)
        try snapshotData.write(
            to: directory.appendingPathComponent("pokemon-catalog-snapshot.json"),
            options: .atomic
        )
        let reportData = try PokemonCatalogJSON.encode(signedBuild.build.report)
        try reportData.write(
            to: directory.appendingPathComponent("review-report.json"),
            options: .atomic
        )
        let completion = Data("complete\n".utf8)
        try completion.write(
            to: directory.appendingPathComponent(".complete"),
            options: .atomic
        )
    }

    private func receipt(revision: Int) -> PokemonCatalogPublicationReceipt {
        PokemonCatalogPublicationReceipt(
            environment: environment,
            revision: revision,
            immutableObjectPath: "\(environment.path)/releases/\(revision)/catalog-release.json",
            currentPointerPath: "\(environment.path)/current.json"
        )
    }
}
