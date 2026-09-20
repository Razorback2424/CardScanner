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
            try writeCandidate(result, rootPath: options.value("--candidate-root"))
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
            let result: PokemonCatalogBuildResult
            if let candidateRoot = options.value("--candidate-root") {
                result = try loadCandidate(rootPath: candidateRoot)
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
            environment: environment
        )
        let generatedAt = try parseDate(options.value("--generated-at"))
        let fixture: PokemonCatalogProviderFixture
        if options.value("--live") == "true" {
            let client = PokemonCatalogTCGdexProviderClient()
            let directory = try await client.fetchDirectory()
            let activeIDs = Set(
                (activeRelease?.sets.map(\.providerSetID) ?? [])
                    .map { $0.lowercased() }
            )
            let overrideIDs = Set(humanInput.sets.map { $0.providerSetID.lowercased() })
            let policy = try read(
                PokemonCatalogDiscoveryPolicy.self,
                from: URL(
                fileURLWithPath: options.value("--discovery-policy")
                        ?? "publisher/discovery-policy.json"
                )
            )
            guard policy.schemaVersion == 1 else {
                throw CLIError.message(
                    "discovery policy schema \(policy.schemaVersion) is unsupported"
                )
            }
            guard let boundary = catalogDate(policy.automaticDiscoveryStartDate) else {
                throw CLIError.message(
                    "discovery policy has an invalid automaticDiscoveryStartDate"
                )
            }
            let unknownRows = directory.filter { row in
                let key = row.id.lowercased()
                return !row.isUnsupportedProduct
                    && !activeIDs.contains(key)
                    && !overrideIDs.contains(key)
                    && !policy.ignoredHistoricalIDs.contains(key)
            }
            let metadata = try await client.fetchSetMetadata(for: unknownRows)
            var directoryDates: [String: String] = [:]
            for row in unknownRows {
                if let releaseDate = row.releaseDate {
                    directoryDates[row.id.lowercased()] = releaseDate
                }
            }
            var dueIDs = Set<String>()
            var historicalIDs: [String] = []
            var pendingIDs: [String] = []
            var invalidMetadataIDs: [String] = []
            for providerSet in metadata {
                let key = providerSet.id.lowercased()
                guard let rawDate = providerSet.releaseDate ?? directoryDates[key] else {
                    invalidMetadataIDs.append(key)
                    continue
                }
                guard let releaseDate = catalogDate(rawDate) else {
                    invalidMetadataIDs.append(key)
                    continue
                }
                if releaseDate < boundary {
                    historicalIDs.append(key)
                } else if releaseDate > generatedAt {
                    pendingIDs.append(key)
                } else {
                    dueIDs.insert(key)
                }
            }
            if !historicalIDs.isEmpty {
                print(
                    "discovery historical backfill ignored: "
                        + historicalIDs.sorted().joined(separator: ", ")
                )
            }
            if !invalidMetadataIDs.isEmpty {
                // Include anomalous rows in the full candidate so the builder
                // fails closed on missing/invalid release date, abbreviation,
                // or denominator instead of silently treating them as pending.
                print(
                    "discovery metadata requires intervention: "
                        + invalidMetadataIDs.sorted().joined(separator: ", ")
                )
                dueIDs.formUnion(invalidMetadataIDs)
            }
            let authorizedSetIDs = activeIDs
                .union(overrideIDs)
                .union(dueIDs)
            fixture = try await client.fetchFixture(
                directory: directory,
                authorizedSetIDs: authorizedSetIDs
            )
            if !pendingIDs.isEmpty {
                print(
                    "discovery pending provider set IDs: "
                        + pendingIDs.sorted().joined(separator: ", ")
                )
            }
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
        guard let date = catalogDate(raw) else {
            throw CLIError.message("--generated-at must be an ISO-8601 date")
        }
        return date
    }

    private static func catalogDate(_ raw: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: raw) {
            return date
        }
        let parts = raw.split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.calendar?.date(from: components)
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

    private static func loadCandidate(rootPath: String) throws -> PokemonCatalogBuildResult {
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        return PokemonCatalogBuildResult(
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
      --input PATH          Catalog overrides/fallbacks JSON
      --discovery-policy PATH
                             Scheduled discovery policy JSON
      --active-release PATH Existing release envelope or payload
      --revision NUMBER     New strictly higher release revision
      --generated-at DATE   ISO-8601 timestamp (use a fixed value for reproducible output)
      --report PATH         Write the public review report to PATH
      --candidate-root PATH Write or read the unsigned validated candidate
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
