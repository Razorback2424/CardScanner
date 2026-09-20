import Foundation

public enum PokemonCatalogProviderFetchError: Error, CustomStringConvertible, Sendable {
    case invalidURL(String)
    case badResponse(path: String, statusCode: Int)
    case network(path: String, message: String)
    case pocketSeriesUnavailable

    public var description: String {
        switch self {
        case .invalidURL(let path): return "Invalid TCGdex URL: \(path)"
        case let .badResponse(path, statusCode):
            return "TCGdex returned HTTP \(statusCode) for \(path)"
        case let .network(path, message): return "TCGdex request failed for \(path): \(message)"
        case .pocketSeriesUnavailable:
            return "TCGdex Pocket series could not be loaded; publication stopped"
        }
    }
}

public enum PokemonCatalogArtworkKind: String, Sendable {
    case logo
    case symbol
}

/// Bounded, provider-side artwork probing. A successful probe is deliberately
/// stricter than an HTTP success: the CDN must identify the body as an image so
/// extensionless HTML guidance pages never become signed artwork URLs.
public struct PokemonCatalogTCGdexArtworkResolver: Sendable {
    public typealias Loader = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let loader: Loader

    public init(
        loader: @escaping Loader = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PokemonCatalogProviderFetchError.badResponse(
                    path: request.url?.absoluteString ?? "",
                    statusCode: 0
                )
            }
            return (data, http)
        }
    ) {
        self.loader = loader
    }

    public func resolve(
        seriesID: String,
        setID: String,
        kind: PokemonCatalogArtworkKind
    ) async -> String? {
        for language in ["en", "univ"] {
            guard let url = Self.candidateURL(
                language: language,
                seriesID: seriesID,
                setID: setID,
                kind: kind
            ) else { continue }

            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            guard let (_, response) = try? await loader(request),
                  (200..<300).contains(response.statusCode),
                  let contentType = response.value(forHTTPHeaderField: "Content-Type")?
                    .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
                    .first,
                  contentType.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .hasPrefix("image/") else {
                continue
            }
            return url.absoluteString
        }
        return nil
    }

    private static func candidateURL(
        language: String,
        seriesID: String,
        setID: String,
        kind: PokemonCatalogArtworkKind
    ) -> URL? {
        var url = URL(string: "https://assets.tcgdex.net")
        for component in [language, seriesID, setID, kind.rawValue + ".png"] {
            url = url?.appendingPathComponent(component)
        }
        return url
    }
}

/// Bounded TCGdex transport used by the macOS publisher. The resulting
/// fixture is a value type, so all validation and release output remains
/// deterministic and testable without a network.
public struct PokemonCatalogTCGdexProviderClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.tcgdex.net/v2/en")!

    private let session: URLSession
    private let baseURL: URL
    private let setConcurrency: Int
    private let cardConcurrency: Int
    private let artworkResolver: PokemonCatalogTCGdexArtworkResolver

    public init(
        session: URLSession = .shared,
        baseURL: URL = PokemonCatalogTCGdexProviderClient.defaultBaseURL,
        setConcurrency: Int = 3,
        cardConcurrency: Int = 8,
        artworkResolver: PokemonCatalogTCGdexArtworkResolver = .init()
    ) {
        self.session = session
        self.baseURL = baseURL
        self.setConcurrency = max(1, setConcurrency)
        self.cardConcurrency = max(1, cardConcurrency)
        self.artworkResolver = artworkResolver
    }

    /// Fetches only the lightweight directory and marks Pokémon Pocket rows.
    /// Detailed set/card requests are intentionally kept out of this method so
    /// scheduled discovery can decide which unknown IDs are due first.
    public func fetchDirectory() async throws -> [PokemonCatalogProviderDirectoryRow] {
        let rows: [PokemonCatalogProviderDirectoryRow] = try await request(
            pathComponents: ["sets"]
        )
        let pocketIDs = try await fetchPocketSetIDs()
        return rows.map { row in
            PokemonCatalogProviderDirectoryRow(
                id: row.id,
                name: row.name,
                logo: row.logo,
                symbol: row.symbol,
                cardCount: row.cardCount,
                releaseDate: row.releaseDate,
                tcgOnline: row.tcgOnline,
                isUnsupportedProduct: row.isUnsupportedProduct
                    || pocketIDs.contains(row.id.lowercased())
            )
        }
    }

    public func fetchFixture(
        authorizedSetIDs: Set<String>? = nil,
        additionalSetIDs: Set<String> = []
    ) async throws -> PokemonCatalogProviderFixture {
        let rows = try await fetchDirectory()
        return try await fetchFixture(
            directory: rows,
            authorizedSetIDs: authorizedSetIDs,
            additionalSetIDs: additionalSetIDs
        )
    }

    /// Builds a fixture from a previously fetched directory. Only the
    /// authorized rows fetch detailed set/card data; the signed release remains
    /// the only downstream scanner authority.
    public func fetchFixture(
        directory: [PokemonCatalogProviderDirectoryRow],
        authorizedSetIDs: Set<String>? = nil,
        additionalSetIDs: Set<String> = []
    ) async throws -> PokemonCatalogProviderFixture {
        let authorizedKeys = authorizedSetIDs.map { Set($0.map { $0.lowercased() }) }
        let scopedRows = directory.filter { row in
            guard let authorizedKeys else { return true }
            return authorizedKeys.contains(row.id.lowercased())
        }
        let scopedKeys = Set(scopedRows.map { $0.id.lowercased() })
        let supportingKeys = Set(additionalSetIDs.map { $0.lowercased() })
        let fetchRows = directory.filter { row in
            scopedKeys.contains(row.id.lowercased())
                || supportingKeys.contains(row.id.lowercased())
        }
        let supportedRows = fetchRows.filter { !$0.isUnsupportedProduct }
        let sets = try await mapBounded(
            supportedRows,
            limit: setConcurrency
        ) { row in
            let fetched: PokemonCatalogProviderSet = try await self.request(
                pathComponents: ["sets", row.id]
            )
            return await self.resolvedArtwork(
                fetched,
                directoryLogo: row.logo,
                directorySymbol: row.symbol
            )
        }
        let materializedKeys = Set(scopedRows.map { $0.id.lowercased() })
        let briefs = sets
            .filter { materializedKeys.contains($0.id.lowercased()) }
            .flatMap(\.cards)
        let uniqueBriefs = Dictionary(
            briefs.map { ($0.id.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let cards = try await mapBounded(
            Array(uniqueBriefs.values).sorted { $0.id < $1.id },
            limit: cardConcurrency
        ) { brief in
            try await self.request(
                pathComponents: ["cards", brief.id]
            ) as PokemonCatalogProviderCard
        }
        return PokemonCatalogProviderFixture(
            directory: scopedRows,
            sets: sets.sorted { $0.id < $1.id },
            cards: cards.sorted { $0.id < $1.id }
        )
    }

    /// Fetches set-level metadata without downloading card details. Scheduled
    /// discovery uses this bounded pass to classify historical, pending, and
    /// due IDs before preparing the full fixture.
    public func fetchSetMetadata(
        for rows: [PokemonCatalogProviderDirectoryRow]
    ) async throws -> [PokemonCatalogProviderSet] {
        try await mapBounded(rows.filter { !$0.isUnsupportedProduct }, limit: setConcurrency) { row in
            try await self.request(pathComponents: ["sets", row.id]) as PokemonCatalogProviderSet
        }
    }

    private func resolvedArtwork(
        _ providerSet: PokemonCatalogProviderSet,
        directoryLogo: String?,
        directorySymbol: String?
    ) async -> PokemonCatalogProviderSet {
        let explicitLogo = providerSet.logo ?? directoryLogo
        let explicitSymbol = providerSet.symbol ?? directorySymbol
        let seriesID = providerSet.serie?.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let setID = providerSet.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let logo: String?
        if let explicitLogo = nonEmpty(explicitLogo) {
            logo = explicitLogo
        } else if let seriesID, !seriesID.isEmpty, !setID.isEmpty {
            logo = await artworkResolver.resolve(
                seriesID: seriesID,
                setID: setID,
                kind: .logo
            )
        } else {
            logo = nil
        }
        let symbol: String?
        if let explicitSymbol = nonEmpty(explicitSymbol) {
            symbol = explicitSymbol
        } else if let seriesID, !seriesID.isEmpty, !setID.isEmpty {
            symbol = await artworkResolver.resolve(
                seriesID: seriesID,
                setID: setID,
                kind: .symbol
            )
        } else {
            symbol = nil
        }
        return PokemonCatalogProviderSet(
            id: providerSet.id,
            name: providerSet.name,
            cards: providerSet.cards,
            logo: logo,
            symbol: symbol,
            releaseDate: providerSet.releaseDate,
            tcgOnline: providerSet.tcgOnline,
            cardCount: providerSet.cardCount,
            serie: providerSet.serie,
            abbreviation: providerSet.abbreviation
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    private func fetchPocketSetIDs() async throws -> Set<String> {
        struct SeriesResponse: Decodable {
            struct Brief: Decodable { let id: String }
            let sets: [Brief]
        }
        do {
            let response: SeriesResponse = try await request(
                pathComponents: ["series", "tcgp"]
            )
            return Set(response.sets.map { $0.id.lowercased() })
        } catch {
            throw PokemonCatalogProviderFetchError.pocketSeriesUnavailable
        }
    }

    private func request<T: Decodable>(pathComponents: [String]) async throws -> T {
        guard !pathComponents.isEmpty else {
            throw PokemonCatalogProviderFetchError.invalidURL("")
        }
        let path = pathComponents.joined(separator: "/")
        let url = Self.makeURL(baseURL: baseURL, pathComponents: pathComponents)
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PokemonCatalogProviderFetchError.badResponse(path: path, statusCode: 0)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw PokemonCatalogProviderFetchError.badResponse(
                    path: path,
                    statusCode: http.statusCode
                )
            }
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw PokemonCatalogProviderFetchError.network(
                    path: path,
                    message: "decode: \(error)"
                )
            }
        } catch let error as PokemonCatalogProviderFetchError {
            throw error
        } catch {
            throw PokemonCatalogProviderFetchError.network(
                path: path,
                message: String(describing: error)
            )
        }
    }

    /// Builds a URL from raw path components. Each component is encoded once
    /// by Foundation; callers must not pre-encode IDs before passing them here.
    static func makeURL(baseURL: URL, pathComponents: [String]) -> URL {
        pathComponents.reduce(baseURL) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
    }

    private func mapBounded<Input: Sendable, Output: Sendable>(
        _ values: [Input],
        limit: Int,
        operation: @escaping @Sendable (Input) async throws -> Output
    ) async throws -> [Output] {
        guard !values.isEmpty else { return [] }
        var iterator = values.makeIterator()
        return try await withThrowingTaskGroup(of: Output.self, returning: [Output].self) { group in
            for _ in 0..<min(limit, values.count) {
                guard let value = iterator.next() else { break }
                group.addTask { try await operation(value) }
            }

            var results: [Output] = []
            while let result = try await group.next() {
                results.append(result)
                if let next = iterator.next() {
                    group.addTask { try await operation(next) }
                }
            }
            return results
        }
    }
}
