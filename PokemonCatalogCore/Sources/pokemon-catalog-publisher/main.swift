import CryptoKit
import Foundation
import PokemonCatalogCore

@main
struct PokemonCatalogPublisherMain {
    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            print("pokemon-catalog-publisher: \(error)")
            Foundation.exit(1)
        }
    }

    private static func run(arguments: [String]) async throws {
        guard let command = arguments.first else {
            throw CLIError.usage
        }
        let options = try CLIOptions(Array(arguments.dropFirst()))
        switch command {
        case "validate":
            let environment = try parseEnvironment(options.value("--environment"))
            let result = try await build(
                options: options,
                siteRoot: nil,
                environment: environment
            )
            try writeReport(result.report, path: options.value("--report"))
            try writeCandidate(result, rootPath: options.value("--candidate-root"))
            printReport(result.report)
        case "verify-release":
            guard let path = options.value("--path") else {
                throw CLIError.message("verify-release requires --path PATH")
            }
            guard let environment = try parseEnvironment(options.value("--environment")) else {
                throw CLIError.message("verify-release requires --environment production|staging")
            }
            let release = try loadSignedRelease(
                from: URL(fileURLWithPath: path),
                options: options,
                environment: environment
            )
            if let expectedRaw = options.value("--expected-revision") {
                guard let expected = Int(expectedRaw), release.revision == expected else {
                    throw CLIError.message(
                        "verified release revision does not match --expected-revision"
                    )
                }
            }
            print(release.revision)
        case "publish":
            guard let rawEnvironment = options.value("--environment"),
                  let environment = PokemonCatalogPublicationEnvironment(rawValue: rawEnvironment),
                  let rawSiteRoot = options.value("--site-root") else {
                throw CLIError.message(
                    "publish requires --environment production|staging and --site-root PATH"
                )
            }
            let siteRoot = URL(fileURLWithPath: rawSiteRoot, isDirectory: true)
            let result: PokemonCatalogBuildResult
            if let candidateRoot = options.value("--candidate-root") {
                let activeRelease = try loadActiveRelease(
                    explicitPath: options.value("--active-release"),
                    siteRoot: siteRoot,
                    environment: environment,
                    options: options
                )
                result = try loadCandidate(
                    rootPath: candidateRoot,
                    activeRevision: activeRelease?.revision
                )
            } else {
                result = try await build(
                    options: options,
                    siteRoot: siteRoot,
                    environment: environment
                )
            }
            let material = try PokemonCatalogSigningKeyLoader.load(environment: environment)
            let signed = try PokemonCatalogSigner.sign(result, material: material)
            let publisher = PokemonCatalogFilesystemPublisher(
                root: siteRoot,
                environment: environment
            )
            let receipt = try publisher.publish(signed)
            try writeReport(result.report, path: options.value("--report"))
            printReport(result.report)
            print("published \(receipt.immutableObjectPath); pointer \(receipt.currentPointerPath)")
        case "help", "--help", "-h":
            print(usage)
        default:
            throw CLIError.message("unknown command \(command)\n\n\(usage)")
        }
    }

    private static func build(
        options: CLIOptions,
        siteRoot: URL?,
        environment: PokemonCatalogPublicationEnvironment?
    ) async throws -> PokemonCatalogBuildResult {
        let fixtureDirectory = URL(
            fileURLWithPath: options.value("--fixture-dir") ?? "publisher/fixtures",
            isDirectory: true
        )
        let humanInput = try read(
            PokemonCatalogHumanInputFile.self,
            from: URL(
                fileURLWithPath: options.value("--input")
                    ?? fixtureDirectory.appendingPathComponent("catalog-input.json").path
            )
        )
        let activeRelease = try loadActiveRelease(
            explicitPath: options.value("--active-release"),
            siteRoot: siteRoot,
            environment: environment,
            options: options
        )
        let authorizedSetIDs = Set(
            humanInput.sets.map(\.providerSetID)
                + (activeRelease?.sets.map(\.providerSetID) ?? [])
        )
        let fixture: PokemonCatalogProviderFixture
        if options.value("--live") == "true" {
            fixture = try await PokemonCatalogTCGdexProviderClient().fetchFixture(
                authorizedSetIDs: authorizedSetIDs
            )
        } else {
            fixture = try read(
                PokemonCatalogProviderFixture.self,
                from: fixtureDirectory.appendingPathComponent("recorded-provider.json")
            )
        }
        let revision: Int
        if let rawRevision = options.value("--revision") {
            guard let parsed = Int(rawRevision) else {
                throw CLIError.message("--revision must be an integer")
            }
            revision = parsed
        } else {
            revision = (activeRelease?.revision ?? 0) + 1
        }
        let generatedAt = try parseDate(options.value("--generated-at"))
        return try PokemonCatalogBuilder().build(
            PokemonCatalogBuildRequest(
                fixture: fixture,
                activeRelease: activeRelease,
                humanInputs: humanInput.sets,
                revision: revision,
                generatedAt: generatedAt
            )
        )
    }

    private static func loadActiveRelease(
        explicitPath: String?,
        siteRoot: URL?,
        environment: PokemonCatalogPublicationEnvironment?,
        options: CLIOptions
    ) throws -> PokemonCatalogRelease? {
        let url: URL?
        if let explicitPath {
            url = URL(fileURLWithPath: explicitPath)
        } else if let siteRoot, let environment {
            url = siteRoot
                .appendingPathComponent(environment.path)
                .appendingPathComponent("current.json")
        } else {
            url = nil
        }
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let environment else {
            throw CLIError.message(
                "--environment is required when reading an active catalog release"
            )
        }
        return try loadSignedRelease(from: url, options: options, environment: environment)
    }

    private static func parseDate(_ raw: String?) throws -> Date {
        guard let raw else { return Date() }
        guard let date = ISO8601DateFormatter().date(from: raw) else {
            throw CLIError.message("--generated-at must be an ISO-8601 date")
        }
        return date
    }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIError.message("missing input file: \(url.path)")
        }
        return try PokemonCatalogJSON.decode(type, from: Data(contentsOf: url))
    }

    private static func writeReport(
        _ report: PokemonCatalogReviewReport,
        path: String?
    ) throws {
        guard let path else { return }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try PokemonCatalogJSON.encode(report).write(to: url, options: .atomic)
    }

    private static func writeCandidate(
        _ result: PokemonCatalogBuildResult,
        rootPath: String?
    ) throws {
        guard let rootPath else { return }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try PokemonCatalogJSON.encode(result.release).write(
            to: root.appendingPathComponent("catalog-payload.json"),
            options: .atomic
        )
        try PokemonCatalogJSON.encode(result.snapshot).write(
            to: root.appendingPathComponent("pokemon-catalog-snapshot.json"),
            options: .atomic
        )
        try PokemonCatalogJSON.encode(result.report).write(
            to: root.appendingPathComponent("review-report.json"),
            options: .atomic
        )
    }

    private static func loadCandidate(
        rootPath: String,
        activeRevision: Int?
    ) throws -> PokemonCatalogBuildResult {
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let result = PokemonCatalogBuildResult(
            release: try read(
                PokemonCatalogRelease.self,
                from: root.appendingPathComponent("catalog-payload.json")
            ),
            snapshot: try read(
                PokemonCatalogSnapshot.self,
                from: root.appendingPathComponent("pokemon-catalog-snapshot.json")
            ),
            report: try read(
                PokemonCatalogReviewReport.self,
                from: root.appendingPathComponent("review-report.json")
            )
        )
        try PokemonCatalogCandidateValidator.validate(
            result,
            activeRevision: activeRevision
        )
        return result
    }

    private static func loadSignedRelease(
        from url: URL,
        options: CLIOptions,
        environment: PokemonCatalogPublicationEnvironment
    ) throws -> PokemonCatalogRelease {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIError.message("missing active catalog release: \(url.path)")
        }
        let data = try Data(contentsOf: url)
        let envelope: PokemonCatalogReleaseEnvelope
        do {
            envelope = try PokemonCatalogJSON.decode(
                PokemonCatalogReleaseEnvelope.self,
                from: data
            )
        } catch {
            throw CLIError.message(
                "active catalog release must be a signed envelope: \(url.path)"
            )
        }
        let release = try PokemonCatalogSignatureVerifier.verify(
            envelope: envelope,
            keys: try trustedKeys(options: options, environment: environment)
        )
        return release
    }

    private static func parseEnvironment(
        _ raw: String?
    ) throws -> PokemonCatalogPublicationEnvironment? {
        guard let raw else { return nil }
        guard let environment = PokemonCatalogPublicationEnvironment(rawValue: raw) else {
            throw CLIError.message("--environment must be production or staging")
        }
        return environment
    }

    private static func trustedKeys(
        options: CLIOptions,
        environment: PokemonCatalogPublicationEnvironment
    ) throws -> [PokemonCatalogSignatureVerifier.PinnedKey] {
        let raw: String
        if let configured = options.value("--trusted-keys"), !configured.isEmpty {
            raw = configured
        } else {
            let configPath = options.value("--trusted-keys-file")
                ?? "Config/PokemonCatalog\(environment == .production ? "Production" : "Staging").xcconfig"
            let configURL = URL(fileURLWithPath: configPath)
            let config = try String(contentsOf: configURL, encoding: .utf8)
            guard let line = config.split(whereSeparator: \.isNewline).first(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("POKEMON_CATALOG_PINNED_KEYS")
            }), let separator = line.firstIndex(of: "=") else {
                throw CLIError.message("missing POKEMON_CATALOG_PINNED_KEYS in \(configPath)")
            }
            raw = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let keys = raw.split(separator: ";").compactMap { entry -> PokemonCatalogSignatureVerifier.PinnedKey? in
            let text = String(entry)
            guard let separator = text.firstIndex(of: ":") ?? text.firstIndex(of: "=") else {
                return nil
            }
            let id = String(text[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let encoded = String(text[text.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty,
                  let data = PokemonCatalogBase64URL.decode(encoded),
                  data.count == 32,
                  let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: data) else {
                return nil
            }
            return PokemonCatalogSignatureVerifier.PinnedKey(id: id, publicKey: publicKey)
        }
        guard !keys.isEmpty else {
            throw CLIError.message("no valid pinned catalog keys are configured")
        }
        return keys
    }

    private static func printReport(_ report: PokemonCatalogReviewReport) {
        if let data = try? PokemonCatalogJSON.encode(report),
           let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

    private static let usage = """
    Usage:
      pokemon-catalog-publisher validate [options]
      pokemon-catalog-publisher publish [options]

    Options:
      --fixture-dir PATH    Recorded provider fixture directory (default: publisher/fixtures)
      --live true            Fetch a fresh bounded TCGdex fixture instead of the recorded fixture
      --input PATH          Human-gated catalog input JSON
      --active-release PATH Existing signed release envelope
      --trusted-keys-file FILE  xcconfig containing POKEMON_CATALOG_PINNED_KEYS
      --trusted-keys VALUE  semicolon-separated keyID:base64url-public-key list
      --revision NUMBER     New strictly higher release revision
      --generated-at DATE   ISO-8601 timestamp (use a fixed value for reproducible output)
      --report PATH         Write the public review report to PATH
      --candidate-root PATH Write or read the unsigned validated candidate
      --site-root PATH      Firebase Hosting root for publish
      --environment NAME    production or staging

      verify-release --path PATH --environment NAME [--expected-revision NUMBER]

    Production publish requires the protected GitHub Actions environment and
    the write-only POKEMON_CATALOG_SIGNING_KEY secret. Local and pull-request
    invocations can validate and report, but cannot sign or publish.
    """
}

private struct CLIOptions {
    private let values: [String: String]

    init(_ arguments: [String]) throws {
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            guard flag.hasPrefix("--"), index + 1 < arguments.count else {
                throw CLIError.message("expected a value after \(flag)")
            }
            values[flag] = arguments[index + 1]
            index += 2
        }
        self.values = values
    }

    func value(_ flag: String) -> String? { values[flag] }
}

private enum CLIError: Error, CustomStringConvertible {
    case usage
    case message(String)

    var description: String {
        switch self {
        case .usage: return "Use --help for usage."
        case .message(let message): return message
        }
    }
}
