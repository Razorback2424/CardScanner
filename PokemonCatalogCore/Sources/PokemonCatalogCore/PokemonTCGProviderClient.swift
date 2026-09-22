import Foundation

public enum PokemonCatalogSecondaryProviderFetchError: Error, CustomStringConvertible, Sendable {
    case invalidURL
    case badResponse(path: String, statusCode: Int)
    case network(path: String, message: String)

    public var description: String {
        switch self {
        case .invalidURL: return "Invalid secondary provider URL"
        case let .badResponse(path, statusCode):
            return "Secondary provider returned HTTP \(statusCode) for \(path)"
        case let .network(path, message):
            return "Secondary provider request failed for \(path): \(message)"
        }
    }
}

/// Bounded client for the public pokemontcg.io set/card metadata surface.
/// Artwork URLs are evidence only and are accepted by the publisher's probe
/// before entering a descriptor.
public struct PokemonCatalogSecondaryProviderClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.pokemontcg.io/v2")!
    private static let maxRequestAttempts = 3

    private let session: URLSession
    private let baseURL: URL

    public init(
        session: URLSession = .shared,
        baseURL: URL = PokemonCatalogSecondaryProviderClient.defaultBaseURL
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    public func fetchSets() async throws -> [PokemonCatalogSecondarySet] {
        struct Response: Decodable {
            let data: [Set]
        }
        struct Set: Decodable {
            struct Images: Decodable {
                let logo: String?
                let symbol: String?
            }

            let id: String
            let name: String
            let ptcgoCode: String?
            let releaseDate: String?
            let printedTotal: Int?
            let total: Int?
            let images: Images?
        }

        // The API's default set query intermittently returns HTTP 500/502.
        // Prefer the compact projection, then fall back to the same stable
        // sort without projection when that backend path is unavailable.
        let queryVariants: [[URLQueryItem]] = [
            [
                URLQueryItem(name: "orderBy", value: "id"),
                URLQueryItem(
                    name: "select",
                    value: "id,name,ptcgoCode,releaseDate,printedTotal,total,images"
                )
            ],
            [URLQueryItem(name: "orderBy", value: "id")]
        ]
        var lastError: Error?
        for queryItems in queryVariants {
            do {
                let response: Response = try await request(
                    path: "sets",
                    queryItems: queryItems
                )
                return response.data.map {
                    PokemonCatalogSecondarySet(
                        id: $0.id,
                        name: $0.name,
                        ptcgoCode: $0.ptcgoCode,
                        releaseDate: $0.releaseDate,
                        printedTotal: $0.printedTotal,
                        total: $0.total,
                        logoURL: $0.images?.logo,
                        symbolURL: $0.images?.symbol
                    )
                }
            } catch {
                lastError = error
            }
        }
        throw lastError ?? PokemonCatalogSecondaryProviderFetchError.network(
            path: "/v2/sets",
            message: "all query variants failed"
        )
    }

    public func fetchCardArtwork(
        setID: String,
        limit: Int = 3
    ) async throws -> [String] {
        struct Response: Decodable {
            let data: [Card]
        }
        struct Card: Decodable {
            struct Images: Decodable {
                let small: String?
                let large: String?
            }
            let images: Images?
        }

        let cappedLimit = max(0, min(limit, 3))
        guard cappedLimit > 0 else { return [] }
        let baseQueryItems = [
            URLQueryItem(name: "q", value: "set.id:\(setID)"),
            URLQueryItem(name: "pageSize", value: String(cappedLimit)),
            URLQueryItem(name: "page", value: "1"),
            // A stable ID sort avoids the compound number,id path, which
            // returns HTTP 500 for some newly listed subsets such as me55c.
            URLQueryItem(name: "orderBy", value: "id")
        ]
        let queryVariants = [
            baseQueryItems + [URLQueryItem(name: "select", value: "images")],
            baseQueryItems
        ]
        var lastError: Error?
        for queryItems in queryVariants {
            do {
                let response: Response = try await request(
                    path: "cards",
                    queryItems: queryItems
                )
                return response.data
                    .compactMap { $0.images?.large ?? $0.images?.small }
                    .prefix(cappedLimit)
                    .map { $0 }
            } catch {
                lastError = error
            }
        }
        throw lastError ?? PokemonCatalogSecondaryProviderFetchError.network(
            path: "/v2/cards",
            message: "all query variants failed"
        )
    }

    /// Fetches the bounded per-card artwork surface needed to fill cards for
    /// sets whose TCGdex briefs have no image. The two providers do not share
    /// collector numbering, so the caller retains both name and number and
    /// performs the conservative cross-provider join separately.
    public func fetchCards(
        setID: String,
        limit: Int = 400
    ) async throws -> [PokemonCatalogSecondaryCard] {
        struct Response: Decodable {
            let data: [Card]
        }
        struct Card: Decodable {
            let number: String
            let name: String

            struct Images: Decodable {
                let small: String?
                let large: String?
            }

            let images: Images?
        }

        let cappedLimit = max(0, limit)
        guard cappedLimit > 0 else { return [] }
        let pageSize = min(cappedLimit, 250)
        let baseQueryItems = [
            URLQueryItem(name: "q", value: "set.id:\(setID)"),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "orderBy", value: "id")
        ]
        let queryVariants = [
            baseQueryItems + [
                URLQueryItem(name: "select", value: "id,number,name,images")
            ],
            baseQueryItems
        ]

        var cards: [PokemonCatalogSecondaryCard] = []
        cards.reserveCapacity(min(cappedLimit, pageSize * 2))
        for page in 1...2 {
            let pageQueryVariants = queryVariants.map { queryItems in
                queryItems + [URLQueryItem(name: "page", value: String(page))]
            }
            var pageCards: [PokemonCatalogSecondaryCard]?
            var lastError: Error?
            for queryItems in pageQueryVariants {
                do {
                    let response: Response = try await request(
                        path: "cards",
                        queryItems: queryItems
                    )
                    pageCards = response.data.map {
                        PokemonCatalogSecondaryCard(
                            number: $0.number,
                            name: $0.name,
                            thumbnailURL: $0.images?.small,
                            imageURL: $0.images?.large
                        )
                    }
                    break
                } catch {
                    lastError = error
                }
            }
            guard let pageCards else {
                throw lastError ?? PokemonCatalogSecondaryProviderFetchError.network(
                    path: "/v2/cards",
                    message: "all query variants failed"
                )
            }

            cards.append(contentsOf: pageCards)
            if pageCards.count < pageSize || cards.count >= cappedLimit {
                break
            }
        }
        return Array(cards.prefix(cappedLimit))
    }

    private func request<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw PokemonCatalogSecondaryProviderFetchError.invalidURL
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw PokemonCatalogSecondaryProviderFetchError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("TradingCardScanner catalog publisher", forHTTPHeaderField: "User-Agent")
        var lastError: PokemonCatalogSecondaryProviderFetchError?
        for attempt in 0..<Self.maxRequestAttempts {
            if attempt > 0 {
                try await Task.sleep(for: .milliseconds(250 * attempt))
            }
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw PokemonCatalogSecondaryProviderFetchError.badResponse(
                        path: url.path,
                        statusCode: 0
                    )
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw PokemonCatalogSecondaryProviderFetchError.badResponse(
                        path: url.path,
                        statusCode: http.statusCode
                    )
                }
                do {
                    return try JSONDecoder().decode(T.self, from: data)
                } catch {
                    throw PokemonCatalogSecondaryProviderFetchError.network(
                        path: url.path,
                        message: "decode: \(error)"
                    )
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as PokemonCatalogSecondaryProviderFetchError {
                lastError = error
                guard attempt + 1 < Self.maxRequestAttempts,
                      Self.isTransient(error) else {
                    throw error
                }
            } catch {
                let wrapped = PokemonCatalogSecondaryProviderFetchError.network(
                    path: url.path,
                    message: String(describing: error)
                )
                lastError = wrapped
                guard attempt + 1 < Self.maxRequestAttempts else {
                    throw wrapped
                }
            }
        }
        throw lastError ?? .network(path: url.path, message: "request exhausted")
    }

    private static func isTransient(
        _ error: PokemonCatalogSecondaryProviderFetchError
    ) -> Bool {
        switch error {
        case .badResponse(_, let statusCode):
            return [500, 502, 503, 504].contains(statusCode)
        case .network:
            return true
        case .invalidURL:
            return false
        }
    }
}
