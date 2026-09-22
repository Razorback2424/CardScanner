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
            printDiscoveryWarnings(result.report)
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
            let requestedChangeClass = try parseChangeClass(options.value("--change-class"))
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
            if let requestedChangeClass,
               requestedChangeClass != result.report.changeClass {
                throw CLIError.message(
                    "--change-class does not match the candidate review report"
                )
            }
            let material = try PokemonCatalogSigningKeyLoader.load(
                environment: environment,
                changeClass: requestedChangeClass
            )
            let signed = try PokemonCatalogSigner.sign(result, material: material)
            let publisher = PokemonCatalogFilesystemPublisher(
                root: siteRoot,
                environment: environment
            )
            let receipt = try publisher.publish(signed)
            try writeReport(result.report, path: options.value("--report"))
            printDiscoveryWarnings(result.report)
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
        let generatedAt = try parseDate(options.value("--generated-at"))
        let fixture: PokemonCatalogProviderFixture
        if options.value("--live") == "true" {
            let client = PokemonCatalogTCGdexProviderClient()
            let directory = try await client.fetchDirectory()
            let secondaryClient = PokemonCatalogSecondaryProviderClient()
            let secondaryCandidates: [PokemonCatalogSecondarySet]
            let secondaryProviderAvailable: Bool
            do {
                secondaryCandidates = try await secondaryClient.fetchSets()
                secondaryProviderAvailable = true
            } catch {
                secondaryCandidates = []
                secondaryProviderAvailable = false
                print("secondary provider unavailable: \(error)")
            }
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
            let parentArtworkSetIDs = Set(
                humanInput.sets.compactMap(\.parentProviderSetID).map { $0.lowercased() }
            )
            let configuredParentChildIDs = Set(
                humanInput.sets
                    .filter {
                        guard let parent = $0.parentProviderSetID else { return false }
                        return !parent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    .map { $0.providerSetID.lowercased() }
            )
            let directoryIDs = Set(directory.map { $0.id.lowercased() })
            let derivedParentSetIDs: Set<String> = Set(
                authorizedSetIDs.compactMap { authorizedID in
                    guard !configuredParentChildIDs.contains(authorizedID) else { return nil }
                    return PokemonCatalogBuilder.derivedParentCandidateProviderSetID(
                        childID: authorizedID,
                        availableProviderSetIDs: directoryIDs
                    )
                }
            )
            let secondaryArtworkLoader: PokemonCatalogArtworkEnricher.SecondaryCardArtworkLoader?
            if secondaryProviderAvailable {
                secondaryArtworkLoader = { setID, limit in
                    try await secondaryClient.fetchCards(
                        setID: setID,
                        limit: limit
                    )
                }
            } else {
                secondaryArtworkLoader = nil
            }
            fixture = try await client.fetchFixture(
                directory: directory,
                authorizedSetIDs: authorizedSetIDs,
                additionalSetIDs: parentArtworkSetIDs.union(derivedParentSetIDs),
                secondaryCandidates: secondaryCandidates,
                secondaryProviderAvailable: secondaryProviderAvailable,
                secondaryCardArtworkLoader: secondaryArtworkLoader
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
        let fixtureForBuild: PokemonCatalogProviderFixture
        if options.value("--live") == "true" {
            fixtureForBuild = fixture
        } else {
            fixtureForBuild = await enrichRecordedFixture(fixture)
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
                fixture: fixtureForBuild,
                activeRelease: activeRelease,
                humanInputs: humanInput.sets,
                revision: revision,
                generatedAt: generatedAt
            )
        )
    }

    /// Recorded fixtures contain artwork URLs that were accepted during the
    /// live capture. Re-run the matcher and enrichment offline so fixture
    /// validation exercises the same secondary-provider path without probing
    /// the network again.
    private static func enrichRecordedFixture(
        _ fixture: PokemonCatalogProviderFixture
    ) async -> PokemonCatalogProviderFixture {
        guard let secondary = fixture.secondary else { return fixture }
        let offlineResolver = PokemonCatalogTCGdexArtworkResolver { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      // The recorded fixture models a TCGdex logo hit and a
                      // symbol miss, so offline validation covers precedence
                      // as well as secondary fallback without network access.
                      statusCode: url.path.hasSuffix("/sv99/logo.png") ? 200 : 404,
                      httpVersion: nil,
                      headerFields: ["Content-Type": "image/png"]
                  ) else {
                throw URLError(.badURL)
            }
            return (response.statusCode == 200 ? Data([1]) : Data(), response)
        }
        let recordedArtworkURLs = Set(
            secondary.sets
                .flatMap { candidate in
                    candidate.cardArtworkURLs
                        + [candidate.logoURL, candidate.symbolURL].compactMap { $0 }
                }
                .compactMap { URL(string: $0) }
            + (secondary.cards ?? [])
                .flatMap { [$0.thumbnailURL, $0.imageURL].compactMap { $0 } }
                .compactMap { URL(string: $0) }
        )
        let offlineSecondaryProbe = PokemonCatalogArtworkProbe { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: recordedArtworkURLs.contains(url) ? 200 : 404,
                      httpVersion: nil,
                      headerFields: ["Content-Type": "image/png"]
                  ) else {
                throw URLError(.badURL)
            }
            return (recordedArtworkURLs.contains(url) ? Data([1]) : Data(), response)
        }
        let enricher = PokemonCatalogArtworkEnricher(
            artworkResolver: offlineResolver,
            secondaryArtworkProbe: offlineSecondaryProbe,
            secondaryCandidates: secondary.sets,
            secondaryCardArtworkLoader: { _, _ in secondary.cards ?? [] }
        )
        let rowsByID = Dictionary(
            uniqueKeysWithValues: fixture.directory.map { ($0.id.lowercased(), $0) }
        )
        var ambiguousIDs = Set(secondary.ambiguousSetIDs)
        var enrichedSets: [PokemonCatalogProviderSet] = []
        enrichedSets.reserveCapacity(fixture.sets.count)
        for providerSet in fixture.sets {
            guard let row = rowsByID[providerSet.id.lowercased()] else {
                enrichedSets.append(providerSet)
                continue
            }
            let result = await enricher.enrich(providerSet, directoryRow: row)
            enrichedSets.append(result.providerSet)
            ambiguousIDs.formUnion(result.ambiguousSecondarySetIDs)
        }
        return PokemonCatalogProviderFixture(
            directory: fixture.directory,
            sets: enrichedSets,
            cards: fixture.cards,
            secondary: PokemonCatalogSecondaryFixture(
                sets: secondary.sets,
                cards: secondary.cards,
                ambiguousSetIDs: ambiguousIDs.sorted()
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
        return try loadSignedRelease(
            from: url,
            options: options,
            environment: environment,
            allowPreviousSchemaVersion: true
        )
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
        environment: PokemonCatalogPublicationEnvironment,
        allowPreviousSchemaVersion: Bool = false
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
            keys: try trustedKeys(options: options, environment: environment),
            allowPreviousSchemaVersion: allowPreviousSchemaVersion
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

    private static func parseChangeClass(
        _ raw: String?
    ) throws -> PokemonCatalogChangeClass? {
        guard let raw else { return nil }
        guard let changeClass = PokemonCatalogChangeClass(rawValue: raw) else {
            throw CLIError.message(
                "--change-class must be none, contentOnly, baselineMigration, authority, newSet, or unknown"
            )
        }
        return changeClass
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

    private static func printDiscoveryWarnings(_ report: PokemonCatalogReviewReport) {
        let admitted = report.sets
            .filter { $0.status == "added" && $0.recognitionKind == .notScannable }
            .map(\.providerSetID)
            .sorted()
        guard !admitted.isEmpty else { return }
        print("discovery admitted as not-scannable: \(admitted.joined(separator: ", "))")
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
      --active-release PATH Existing signed release envelope or payload
      --trusted-keys-file FILE  xcconfig containing POKEMON_CATALOG_PINNED_KEYS
      --trusted-keys VALUE  semicolon-separated keyID:base64url-public-key list
      --revision NUMBER     New strictly higher release revision
      --generated-at DATE   ISO-8601 timestamp (use a fixed value for reproducible output)
      --report PATH         Write the public review report to PATH
      --candidate-root PATH Write or read the unsigned validated candidate
      --site-root PATH      Firebase Hosting root for publish
      --environment NAME    production or staging
      --change-class NAME   Candidate class selected by prepare-production

      verify-release --path PATH --environment NAME [--expected-revision NUMBER]

    Production publish requires the matching GitHub Actions publication
    environment and the write-only POKEMON_CATALOG_SIGNING_KEY secret.
    Authority changes use the protected environment; content-only changes use
    the automatic production environment. Local and pull-request invocations
    can validate and report, but cannot sign or publish.
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
