import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct MagicCatalogScryfallProviderClient: Sendable {
    public enum Error: Swift.Error, CustomStringConvertible, Sendable {
        case invalidURL
        case badResponse(Int)
        case decodeFailed(String)

        public var description: String {
            switch self {
            case .invalidURL: return "Could not build the Scryfall /sets URL"
            case .badResponse(let status): return "Scryfall /sets returned HTTP \(status)"
            case .decodeFailed(let message): return "Scryfall /sets decode failed: \(message)"
            }
        }
    }

    public let endpoint: URL
    private let session: URLSession

    public init(
        endpoint: URL = URL(string: "https://api.scryfall.com/sets")!,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.session = session
    }

    public func fetchDirectory() async throws -> MagicCatalogProviderFixture {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 20
        request.setValue("TradingCardScanner/1.0 (Magic catalog publisher)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Error.badResponse(0)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Error.badResponse(http.statusCode)
        }
        do {
            return MagicCatalogProviderFixture(
                sets: try MagicCatalogProviderJSON.decodeDirectory(from: data)
            )
        } catch {
            throw Error.decodeFailed(String(describing: error))
        }
    }
}
