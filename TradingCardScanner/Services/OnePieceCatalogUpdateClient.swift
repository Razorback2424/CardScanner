import Foundation
import OnePieceCatalogCore

protocol OnePieceCatalogUpdateFetching: Sendable {
    func fetch() async throws -> SignedCatalogFetchResult<OnePieceCatalogReleaseEnvelope>
    func resetConditionalState() async
}

actor OnePieceCatalogUpdateClient: OnePieceCatalogUpdateFetching {
    private let transport: SignedCatalogUpdateClient<OnePieceCatalogReleaseEnvelope>

    init(endpoint: URL, configuration: URLSessionConfiguration = .ephemeral) throws {
        transport = try .init(endpoint: endpoint, configuration: configuration)
    }
    func fetch() async throws -> SignedCatalogFetchResult<OnePieceCatalogReleaseEnvelope> { try await transport.fetch() }
    func resetConditionalState() async { await transport.resetConditionalState() }
}
