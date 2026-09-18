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
            let result = try await build(options: options, siteRoot: nil, environment: nil)
            try writeReport(result.report, path: options.value("--report"))
            printReport(result.report)
        case "publish":
            guard let rawEnvironment = options.value("--environment"),
                  let environment = PokemonCatalogPublicationEnvironment(rawValue: rawEnvironment),
                  let rawSiteRoot = options.value("--site-root") else {
                throw CLIError.message(
                    "publish requires --environment production|staging and --site-root PATH"
                )
            }
            let siteRoot = URL(fileURLWithPath: rawSiteRoot, isDirectory: true)
            let result = try await build(
                options: options,
                siteRoot: siteRoot,
                environment: environment
            )
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
        let fixture: PokemonCatalogProviderFixture
        if options.value("--live") == "true" {
            fixture = try await PokemonCatalogTCGdexProviderClient().fetchFixture()
        } else {
            fixture = try read(
                PokemonCatalogProviderFixture.self,
                from: fixtureDirectory.appendingPathComponent("recorded-provider.json")
            )
        }
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
            environment: environment
        )
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
        environment: PokemonCatalogPublicationEnvironment?
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
        let data = try Data(contentsOf: url)
        if let envelope = try? PokemonCatalogJSON.decode(
            PokemonCatalogReleaseEnvelope.self,
            from: data
        ), let payload = PokemonCatalogBase64URL.decode(envelope.payload) {
            return try PokemonCatalogJSON.decode(PokemonCatalogRelease.self, from: payload)
        }
        return try PokemonCatalogJSON.decode(PokemonCatalogRelease.self, from: data)
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
      --active-release PATH Existing release envelope or payload
      --revision NUMBER     New strictly higher release revision
      --generated-at DATE   ISO-8601 timestamp (use a fixed value for reproducible output)
      --report PATH         Write the public review report to PATH
      --site-root PATH      Firebase Hosting root for publish
      --environment NAME    production or staging

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
