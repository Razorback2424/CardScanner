import Foundation

actor MagicCatalogUpdateClient {
    enum UpdateError: Error, Sendable {
        case invalidURL
        case badResponse(statusCode: Int)
        case payloadTooLarge(bytes: Int)
        case networkFailure(Error)
    }

    enum FetchResult: Sendable {
        case fetched(MagicCatalogReleaseEnvelope)
        case notModified
    }

    static let productionBaseURL = URL(string: "https://catalog.scan-stash.com")!
    private static let allowedHost = "catalog.scan-stash.com"
    private static let pointerPath = "magic/v1/current.json"
    private static let maxPayloadBytes = 512 * 1024
    private static let maxRetries = 2

    private let session: URLSession
    private let baseURL: URL
    private var lastETag: String?
    private var lastModified: String?
    private var lastFetchedEnvelope: MagicCatalogReleaseEnvelope?
    private var pointerURL: URL { baseURL.appendingPathComponent(Self.pointerPath) }

    init(
        session: URLSession = .shared,
        baseURL: URL = MagicCatalogUpdateClient.defaultBaseURL
    ) {
        self.session = session
        self.baseURL = Self.isAllowedOrigin(baseURL) ? baseURL : Self.productionBaseURL
    }

    static var defaultBaseURL: URL {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "MAGIC_CATALOG_BASE_URL") as? String,
              !raw.contains("$("),
              let url = URL(string: raw),
              isAllowedOrigin(url) else {
            return productionBaseURL
        }
        return url
    }

    static func isAllowedOrigin(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == allowedHost
            && url.port == nil
            && url.user == nil
            && url.password == nil
            && url.query == nil
            && url.fragment == nil
            && (url.path.isEmpty || url.path == "/")
    }

    func fetch() async throws -> FetchResult {
        var request = URLRequest(url: pointerURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let lastETag { request.setValue(lastETag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }

        var lastError: Error?
        for attempt in 0...Self.maxRetries {
            try Task.checkCancellation()
            if attempt > 0 { try await Task.sleep(for: .seconds(Double(attempt))) }
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw UpdateError.badResponse(statusCode: 0)
                }
                if http.statusCode == 304 {
                    guard request.value(forHTTPHeaderField: "If-None-Match") != nil
                        || request.value(forHTTPHeaderField: "If-Modified-Since") != nil else {
                        throw UpdateError.badResponse(statusCode: 304)
                    }
                    return .notModified
                }
                guard (200..<300).contains(http.statusCode) else {
                    let error = UpdateError.badResponse(statusCode: http.statusCode)
                    if http.statusCode >= 500, attempt < Self.maxRetries {
                        lastError = error
                        continue
                    }
                    throw error
                }
                guard data.count <= Self.maxPayloadBytes else {
                    throw UpdateError.payloadTooLarge(bytes: data.count)
                }
                let envelope = try MagicCatalogJSON.decode(
                    MagicCatalogReleaseEnvelope.self,
                    from: data
                )
                lastFetchedEnvelope = envelope
                lastETag = http.value(forHTTPHeaderField: "ETag")
                lastModified = http.value(forHTTPHeaderField: "Last-Modified")
                return .fetched(envelope)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as UpdateError {
                throw error
            } catch {
                lastError = UpdateError.networkFailure(error)
                if attempt == Self.maxRetries { throw lastError! }
            }
        }
        throw lastError ?? UpdateError.networkFailure(
            NSError(domain: "MagicCatalogUpdateClient", code: -1)
        )
    }

    func resetConditionalState() {
        lastFetchedEnvelope = nil
        lastETag = nil
        lastModified = nil
    }

    func useVerifiedETag(for envelope: MagicCatalogReleaseEnvelope, from file: URL) {
        lastETag = VerifiedCatalogETag.load(from: file, endpoint: pointerURL, keyID: envelope.keyID, signature: envelope.signature)
    }

    func rememberVerifiedETag(for envelope: MagicCatalogReleaseEnvelope, at file: URL) {
        guard envelope == lastFetchedEnvelope else { return }
        guard let lastETag else { try? FileManager.default.removeItem(at: file); return }
        VerifiedCatalogETag(endpoint: pointerURL, keyID: envelope.keyID, signature: envelope.signature, etag: lastETag)
            .save(to: file)
    }
}
