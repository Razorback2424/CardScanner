import Foundation
import OnePieceCatalogCore

protocol OnePieceCatalogUpdateFetching: Sendable {
    func fetch() async throws -> SignedCatalogFetchResult<OnePieceCatalogReleaseEnvelope>
    func useVerifiedEnvelope(_ envelope: OnePieceCatalogReleaseEnvelope?) async
    func rememberVerifiedEnvelope(_ envelope: OnePieceCatalogReleaseEnvelope) async
    func resetConditionalState() async
}

extension OnePieceCatalogUpdateFetching {
    func useVerifiedEnvelope(_ envelope: OnePieceCatalogReleaseEnvelope?) async {}
    func rememberVerifiedEnvelope(_ envelope: OnePieceCatalogReleaseEnvelope) async {}
}

actor OnePieceCatalogUpdateClient: OnePieceCatalogUpdateFetching {
    private struct VerifiedValidator: Codable {
        let endpoint: URL
        let keyID: String
        let signature: String
        let etag: String?
        let modified: String?
    }

    private let transport: SignedCatalogUpdateClient<OnePieceCatalogReleaseEnvelope>
    private let endpoint: URL
    private let conditionalStateURL: URL?
    private var verifiedValidator: VerifiedValidator?

    init(endpoint: URL, configuration: URLSessionConfiguration = .ephemeral,
         conditionalStateURL: URL? = nil) throws {
        transport = try .init(endpoint: endpoint, configuration: configuration)
        self.endpoint = endpoint
        self.conditionalStateURL = conditionalStateURL
        if let conditionalStateURL, let handle = try? FileHandle(forReadingFrom: conditionalStateURL) {
            defer { try? handle.close() }
            if let data = try? handle.read(upToCount: 8_193), data.count <= 8_192,
               let cached = try? JSONDecoder().decode(VerifiedValidator.self, from: data),
               Self.validHeader(cached.etag) != nil {
                verifiedValidator = cached
            }
        }
    }
    func fetch() async throws -> SignedCatalogFetchResult<OnePieceCatalogReleaseEnvelope> { try await transport.fetch() }

    func useVerifiedEnvelope(_ envelope: OnePieceCatalogReleaseEnvelope?) async {
        let validator = verifiedValidator.flatMap { cached in
            cached.endpoint == endpoint && cached.keyID == envelope?.keyID && cached.signature == envelope?.signature
                ? cached : nil
        }
        await transport.useConditionalHeaders(etag: Self.validHeader(validator?.etag),
            modified: Self.validHeader(validator?.modified))
    }

    func rememberVerifiedEnvelope(_ envelope: OnePieceCatalogReleaseEnvelope) async {
        let headers = await transport.conditionalHeaders()
        let etag = Self.validHeader(headers.etag)
        let modified = Self.validHeader(headers.modified)
        guard etag != nil || modified != nil else {
            await resetConditionalState()
            return
        }
        let record = VerifiedValidator(endpoint: endpoint, keyID: envelope.keyID, signature: envelope.signature,
            etag: etag, modified: modified)
        verifiedValidator = record
        guard let conditionalStateURL else { return }
        // Only a verified ETag survives restart. Last-Modified retains its
        // in-process behavior when an origin does not send an ETag.
        if etag != nil, let data = try? JSONEncoder().encode(record) {
            try? FileManager.default.createDirectory(at: conditionalStateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try? data.write(to: conditionalStateURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: conditionalStateURL)
        }
    }

    private static func validHeader(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.utf8.count <= 1_024 else { return nil }
        return value
    }

    func resetConditionalState() async {
        verifiedValidator = nil
        if let conditionalStateURL { try? FileManager.default.removeItem(at: conditionalStateURL) }
        await transport.resetConditionalState()
    }
}
