import Foundation
import CryptoKit
import OnePieceCatalogCore

/// Builds unsigned candidates or signs/verifies explicitly reviewed bytes.
/// This command never deploys, rewrites its input or allocates printing UUIDs.
@main
struct OnePieceCatalogPublisher {
    static func main() {
        do { try run(Array(CommandLine.arguments.dropFirst())) }
        catch {
            FileHandle.standardError.write(Data("one-piece-catalog-publisher: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) throws {
        if arguments.first == "sign" || arguments.first == "verify" { try publication(arguments); return }
        guard arguments.first == "build" else { throw CLIError.usage }
        var options: [String: String] = [:]
        var index = 1
        let allowed: Set<String> = ["--registry", "--observations", "--inventories", "--revision", "--generated-at", "--previous", "--bootstrap-registry", "--output"]
        while index < arguments.count {
            let key = arguments[index]
            guard allowed.contains(key), index + 1 < arguments.count, options[key] == nil else { throw CLIError.usage }
            options[key] = arguments[index + 1]; index += 2
        }
        func value(_ key: String) throws -> String {
            guard let value = options[key], !value.isEmpty else { throw CLIError.usage }
            return value
        }
        func read<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
            try JSONDecoder().decode(type, from: Data(contentsOf: URL(fileURLWithPath: path)))
        }
        let registryPath = try value("--registry")
        let observationsPath = try value("--observations")
        let inventoriesPath = try value("--inventories")
        let outputPath = try value("--output")
        let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL.resolvingSymlinksInPath()
        for input in [registryPath, observationsPath, inventoriesPath, options["--previous"]].compactMap({ $0 }) {
            if URL(fileURLWithPath: input).standardizedFileURL.resolvingSymlinksInPath() == outputURL { throw CLIError.overwritesInput }
        }
        guard let revision = Int(try value("--revision")) else { throw CLIError.usage }
        let previous = try options["--previous"].map { try read(OnePieceCatalogRelease.self, $0) }
        guard (previous != nil && options["--bootstrap-registry"] == nil) ||
                (previous == nil && options["--bootstrap-registry"] == "yes" && revision == 1) else { throw CLIError.baselineRequired }
        let release = try OnePieceCatalogBuilder.build(
            registry: read(OnePieceRegistryDocument.self, registryPath),
            observations: read([OnePieceSourceObservation].self, observationsPath),
            inventories: read([OnePieceSourceInventory].self, inventoriesPath),
            revision: revision, generatedAt: value("--generated-at"), previous: previous)
        // The input registry remains the durable authority. Output contains its
        // complete retained state, so review can diff old/new UUIDs and aliases.
        try release.canonicalData().write(to: outputURL, options: .atomic)
        let classification = OnePieceCatalogChangeClassifier.classify(previous: previous, current: release)
        print("Validated unsigned candidate: revision \(release.revision), \(release.registry.printings.count) retained printings, \(classification.changeClass.rawValue)")
    }

    enum CLIError: Error {
        case usage, overwritesInput, baselineRequired, invalidSigningKey, outputExists
    }

    private static func publication(_ arguments: [String]) throws {
        let signing = arguments[0] == "sign"
        let allowed: Set<String> = ["--input", "--trusted-keys", "--previous", "--bootstrap-registry",
                                    "--reviewed-payload-sha256", "--key-id", "--output", "--manifest"]
        var options: [String: String] = [:]
        var index = 1
        while index < arguments.count {
            let key = arguments[index]
            guard allowed.contains(key), index + 1 < arguments.count, options[key] == nil else { throw CLIError.usage }
            options[key] = arguments[index + 1]; index += 2
        }
        func required(_ key: String) throws -> String {
            guard let value = options[key], !value.isEmpty else { throw CLIError.usage }; return value
        }
        func url(_ path: String) -> URL { URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath() }
        func read(_ path: String, limit: Int = 48 * 1_024 * 1_024) throws -> Data {
            let handle = try FileHandle(forReadingFrom: url(path)); defer { try? handle.close() }
            let bytes = try handle.read(upToCount: limit + 1) ?? Data()
            guard bytes.count <= limit else { throw OnePieceCatalogSignatureError.oversizedPayload }; return bytes
        }
        let input = try required("--input"), keysPath = try required("--trusted-keys")
        let fingerprint = try required("--reviewed-payload-sha256")
        let manifestURL = url(try required("--manifest"))
        let outputURL = try signing ? url(required("--output")) : nil
        guard signing || (options["--output"] == nil && options["--key-id"] == nil) else { throw CLIError.usage }
        guard options["--bootstrap-registry"] == nil || options["--bootstrap-registry"] == "yes" else { throw CLIError.usage }
        let inputs = [input, keysPath, options["--previous"]].compactMap { $0 }.map(url)
        let outputs = [outputURL, manifestURL].compactMap { $0 }
        guard Set(outputs).count == outputs.count, outputs.allSatisfy({ !inputs.contains($0) }) else { throw CLIError.overwritesInput }
        let encodedKeys = try JSONDecoder().decode([String: String].self, from: read(keysPath, limit: 64 * 1_024))
        let keys = try encodedKeys.mapValues { value in
            guard let data = Data(base64Encoded: value), data.count == 32 else { throw CLIError.invalidSigningKey }
            return try Curve25519.Signing.PublicKey(rawRepresentation: data)
        }
        let previous = try options["--previous"].map { try JSONDecoder().decode(OnePieceCatalogReleaseEnvelope.self, from: read($0)) }
        let bootstrap = options["--bootstrap-registry"] == "yes"
        let manifest: OnePieceCatalogPublicationManifest
        var envelopeBytes: Data?
        if signing {
            guard let value = ProcessInfo.processInfo.environment["ONE_PIECE_CATALOG_SIGNING_KEY"],
                  let data = Data(base64Encoded: value), data.count == 32 else { throw CLIError.invalidSigningKey }
            let prepared = try OnePieceCatalogPublication.prepare(candidate: read(input), reviewedSHA256: fingerprint,
                keyID: required("--key-id"), privateKey: Curve25519.Signing.PrivateKey(rawRepresentation: data),
                trustedKeys: keys, previous: previous, bootstrap: bootstrap)
            if let outputURL, FileManager.default.fileExists(atPath: outputURL.path) {
                let existing = try JSONDecoder().decode(OnePieceCatalogReleaseEnvelope.self, from: read(outputURL.path))
                guard existing.keyID == prepared.envelope.keyID, existing.payload == prepared.envelope.payload else {
                    throw CLIError.outputExists
                }
                // Keep the already verified signature and its manifest rather
                // than regenerating an immutable artifact on a repeated run.
                manifest = try OnePieceCatalogPublication.verify(existing, reviewedSHA256: fingerprint,
                    trustedKeys: keys, previous: previous, bootstrap: bootstrap)
                envelopeBytes = try OnePieceCatalogPublication.envelopeData(existing)
            } else {
                manifest = prepared.manifest; envelopeBytes = try OnePieceCatalogPublication.envelopeData(prepared.envelope)
            }
        } else {
            manifest = try OnePieceCatalogPublication.verify(JSONDecoder().decode(OnePieceCatalogReleaseEnvelope.self, from: read(input)),
                reviewedSHA256: fingerprint, trustedKeys: keys, previous: previous, bootstrap: bootstrap)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifestBytes = try encoder.encode(manifest)
        var files: [(URL, Data)] = [(manifestURL, manifestBytes)]
        if let outputURL, let envelopeBytes { files.append((outputURL, envelopeBytes)) }
        // Check every destination before writing any artifact. Repeated runs
        // retain identical bytes; a differing existing artifact is never replaced.
        for (path, data) in files where FileManager.default.fileExists(atPath: path.path) {
            guard try read(path.path) == data else { throw CLIError.outputExists }
        }
        for (path, data) in files where !FileManager.default.fileExists(atPath: path.path) {
            // Foundation does not allow atomic and exclusive creation together.
            // These are private preparation artifacts: an interrupted file is
            // rejected on retry, and verification precedes any publication.
            try data.write(to: path, options: .withoutOverwriting)
        }
        print("Verified publication artifact: revision \(manifest.revision), \(manifest.classification.changeClass.rawValue), \(manifest.payloadSHA256)")
    }
}
