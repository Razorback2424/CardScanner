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

/// Bounded TCGdex transport used by the macOS publisher. The resulting
/// fixture is a value type, so all validation and release output remains
/// deterministic and testable without a network.
public struct PokemonCatalogTCGdexProviderClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.tcgdex.net/v2/en")!

    private let session: URLSession
    private let baseURL: URL
    private let setConcurrency: Int
    private let cardConcurrency: Int

    public init(
        session: URLSession = .shared,
        baseURL: URL = PokemonCatalogTCGdexProviderClient.defaultBaseURL,
        setConcurrency: Int = 3,
        cardConcurrency: Int = 8
    ) {
        self.session = session
        self.baseURL = baseURL
        self.setConcurrency = max(1, setConcurrency)
        self.cardConcurrency = max(1, cardConcurrency)
    }

    public func fetchFixture(
        authorizedSetIDs: Set<String>? = nil
    ) async throws -> PokemonCatalogProviderFixture {
        let rows: [PokemonCatalogProviderDirectoryRow] = try await request(
            pathComponents: ["sets"]
        )
        let pocketIDs = authorizedSetIDs == nil ? try await fetchPocketSetIDs() : []
        let markedRows = rows.map { row in
            PokemonCatalogProviderDirectoryRow(
                id: row.id,
                name: row.name,
                logo: row.logo,
                symbol: row.symbol,
                cardCount: row.cardCount,
                tcgOnline: row.tcgOnline,
                isUnsupportedProduct: row.isUnsupportedProduct
                    || pocketIDs.contains(row.id.lowercased())
            )
        }
        let scopedRows = markedRows.filter { row in
            guard let authorizedSetIDs else { return true }
            return authorizedSetIDs.contains(row.id.lowercased())
        }
        let supportedRows = scopedRows.filter { !$0.isUnsupportedProduct }
        let sets = try await mapBounded(
            supportedRows,
            limit: setConcurrency
        ) { row in
            try await self.request(
                pathComponents: ["sets", row.id]
            ) as PokemonCatalogProviderSet
        }
        let briefs = sets.flatMap(\.cards)
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
