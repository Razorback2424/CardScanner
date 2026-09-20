import CryptoKit
import Foundation
import MagicCatalogCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
struct MagicCatalogPublisherMain {
    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("magic-catalog-publisher: \(error)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func run(arguments: [String]) async throws {
        guard let command = arguments.first else { throw CLIError.usage }
        let options = try CLIOptions(Array(arguments.dropFirst()))
        switch command {
        case "validate":
            let result = try await build(options: options)
            try writeReport(result.report, path: options.value("--report"))
            try writeCandidate(result, rootPath: options.value("--candidate-root"))
            printReport(result.report)
        case "verify-release":
            guard let path = options.value("--path") else {
                throw CLIError.message("verify-release requires --path PATH")
            }
            let release = try loadSignedRelease(
                from: URL(fileURLWithPath: path),
                options: options
            )
            if let raw = options.value("--expected-revision"),
               Int(raw) != release.revision {
                throw CLIError.message("verified release revision does not match --expected-revision")
            }
            print(release.revision)
        case "publish":
            guard let environmentRaw = options.value("--environment"),
                  let environment = MagicCatalogPublicationEnvironment(rawValue: environmentRaw),
                  let siteRootRaw = options.value("--site-root"),
                  let candidateRootRaw = options.value("--candidate-root") else {
                throw CLIError.message(
                    "publish requires --environment production|staging --site-root PATH --candidate-root PATH"
                )
            }
            let activeRelease = try loadActiveRelease(options: options)
            let result = try loadCandidate(
                rootPath: candidateRootRaw,
                activeRevision: activeRelease?.revision
            )
            let material = try MagicCatalogSigningKeyLoader.load(environment: environment)
            let signed = try MagicCatalogSigner.sign(
                result,
                privateKey: material.privateKey,
                keyID: material.keyID
            )
            let publisher = MagicCatalogFilesystemPublisher(
                root: URL(fileURLWithPath: siteRootRaw, isDirectory: true),
                environment: environment
            )
            let receipt = try publisher.publish(signed, activeRelease: activeRelease)
            try writeReport(result.report, path: options.value("--report"))
            printReport(result.report)
            print("published \(receipt.immutableObjectPath); pointer \(receipt.currentPointerPath)")
        case "help", "--help", "-h":
            print(usage)
        default:
            throw CLIError.message("unknown command \(command)\n\n\(usage)")
        }
    }

    private static func build(options: CLIOptions) async throws -> MagicCatalogBuildResult {
        let activeRelease = try loadActiveRelease(options: options)
        let generatedAt = options.value("--generated-at") ?? MagicCatalogDate.formatTimestamp(Date())
        guard MagicCatalogDate.parseTimestamp(generatedAt) != nil else {
            throw CLIError.message("--generated-at must be an ISO-8601 timestamp")
        }
        let fixture: MagicCatalogProviderFixture
        if options.value("--live") == "true" {
            fixture = try await MagicCatalogScryfallProviderClient().fetchDirectory()
        } else {
            let path = options.value("--input") ?? "magic-publisher/fixtures/recorded-provider.json"
            fixture = try read(MagicCatalogProviderFixture.self, from: URL(fileURLWithPath: path))
        }
        let revision: Int
        if let raw = options.value("--revision"), let value = Int(raw) {
            revision = value
        } else {
            revision = (activeRelease?.revision ?? 0) + 1
        }
        return try MagicCatalogBuilder().build(
            MagicCatalogBuildRequest(
                fixture: fixture,
                activeRelease: activeRelease,
                revision: revision,
                generatedAt: generatedAt
            )
        )
    }

    private static func loadActiveRelease(options: CLIOptions) throws -> MagicCatalogRelease? {
        guard let raw = options.value("--active-release") else { return nil }
        let url = URL(fileURLWithPath: raw)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try loadSignedRelease(from: url, options: options)
    }

    private static func loadSignedRelease(
        from url: URL,
        options: CLIOptions
    ) throws -> MagicCatalogRelease {
        let envelope = try read(MagicCatalogReleaseEnvelope.self, from: url)
        let keysPath = options.value("--trusted-keys-file")
        let keys = try loadPinnedKeys(path: keysPath)
        guard !keys.isEmpty else {
            throw CLIError.message("a trusted key file is required to verify a Magic release")
        }
        return try MagicCatalogSignatureVerifier.verify(envelope: envelope, keys: keys)
    }

    private static func loadPinnedKeys(path: String?) throws
        -> [MagicCatalogSignatureVerifier.PinnedKey] {
        guard let path else { return [] }
        let raw = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        let assignment = raw
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { $0.contains("MAGIC_CATALOG_PINNED_KEYS") }
        let value = assignment?
            .split(separator: "=", maxSplits: 1)
            .dropFirst()
            .first
            .map(String.init)
            ?? raw
        let cleaned = value
            .replacingOccurrences(of: "//", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.split(separator: ";").compactMap { entry in
            let text = String(entry)
            guard let separator = text.firstIndex(of: ":") ?? text.firstIndex(of: "=") else {
                return nil
            }
            let id = String(text[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let encoded = String(text[text.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = MagicCatalogBase64URL.decode(encoded), data.count == 32,
                  let key = try? Curve25519.Signing.PublicKey(rawRepresentation: data) else {
                return nil
            }
            return MagicCatalogSignatureVerifier.PinnedKey(id: id, publicKey: key)
        }
    }

    private static func writeReport(_ report: MagicCatalogReviewReport, path: String?) throws {
        guard let path else { return }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try MagicCatalogJSON.encode(report).write(to: url, options: .atomic)
    }

    private static func writeCandidate(
        _ result: MagicCatalogBuildResult,
        rootPath: String?
    ) throws {
        guard let rootPath else { return }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try MagicCatalogJSON.encode(result.release).write(
            to: root.appendingPathComponent("catalog-payload.json"),
            options: .atomic
        )
        try MagicCatalogJSON.encode(result.report).write(
            to: root.appendingPathComponent("review-report.json"),
            options: .atomic
        )
    }

    private static func loadCandidate(
        rootPath: String,
        activeRevision: Int?
    ) throws -> MagicCatalogBuildResult {
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let result = MagicCatalogBuildResult(
            release: try read(
                MagicCatalogRelease.self,
                from: root.appendingPathComponent("catalog-payload.json")
            ),
            report: try read(
                MagicCatalogReviewReport.self,
                from: root.appendingPathComponent("review-report.json")
            )
        )
        try MagicCatalogCandidateValidator.validate(result, activeRevision: activeRevision)
        return result
    }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIError.message("missing input file: \(url.path)")
        }
        return try MagicCatalogJSON.decode(type, from: Data(contentsOf: url))
    }

    private static func printReport(_ report: MagicCatalogReviewReport) {
        print("Magic catalog revision \(report.revision)")
        print("descriptors: \(report.descriptorCount)")
        let added = report.addedCodes.isEmpty ? "none" : report.addedCodes.joined(separator: ", ")
        let changed = report.changedCodes.isEmpty ? "none" : report.changedCodes.joined(separator: ", ")
        let removed = report.removedCodes.isEmpty ? "none" : report.removedCodes.joined(separator: ", ")
        print("added: \(added)")
        print("changed: \(changed)")
        print("removed: \(removed)")
        print("meaningful changes: \(report.hasMeaningfulChanges)")
    }

    private static let usage = """
    magic-catalog-publisher validate [--input PATH | --live true] [--active-release PATH]
        [--trusted-keys-file PATH] [--revision N] [--generated-at ISO8601]
        [--candidate-root PATH] [--report PATH]
    magic-catalog-publisher verify-release --path PATH --trusted-keys-file PATH
        [--expected-revision N]
    magic-catalog-publisher publish --candidate-root PATH --site-root PATH
        --environment production|staging [--active-release PATH]
    """
}

private struct CLIOptions {
    private var values: [String: String] = [:]

    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--"), index + 1 < arguments.count else {
                throw CLIError.message("option \(key) requires a value")
            }
            values[key] = arguments[index + 1]
            index += 2
        }
    }

    func value(_ key: String) -> String? { values[key] }
}

private enum CLIError: Error, CustomStringConvertible {
    case usage
    case message(String)

    var description: String {
        switch self {
        case .usage: return "missing command; run with --help"
        case .message(let message): return message
        }
    }
}
