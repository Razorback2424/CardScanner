import Foundation
import os

actor PokemonCatalogUpdateClient {
    private static let logger = Logger(
        subsystem: "com.scan-stash.TradingCardScanner",
        category: "pokemonCatalogUpdate"
    )

    enum UpdateError: Error {
        case invalidURL
        case badResponse(statusCode: Int)
        case payloadTooLarge(bytes: Int)
        case networkFailure(Error)
    }

    enum FetchResult: Sendable {
        case fetched(PokemonCatalogReleaseEnvelope)
        case notModified
    }

    private static let maxPayloadBytes = 512 * 1024
    static let productionBaseURL = URL(string: "https://catalog.scan-stash.com")!
    static let stagingBaseURL = URL(string: "https://catalog-staging.scan-stash.com")!
    static let allowedCatalogOriginHosts: Set<String> = [
        "catalog.scan-stash.com",
        "catalog-staging.scan-stash.com"
    ]

    /// Returns true only for the two owner-controlled HTTPS catalog origins.
    /// The optional expected host provides the stronger per-build boundary:
    /// production builds accept only production and staging builds accept only
    /// staging.
    static func isAllowedCatalogOrigin(_ url: URL, expectedHost: String? = nil) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              allowedCatalogOriginHosts.contains(host),
              expectedHost == nil || host == expectedHost?.lowercased(),
              url.port == nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              url.path.isEmpty || url.path == "/" else {
            return false
        }
        return true
    }

    private static var configuredOriginHost: String {
        guard let rawHost = Bundle.main.object(
            forInfoDictionaryKey: "POKEMON_CATALOG_ALLOWED_ORIGIN_HOST"
        ) as? String else {
            return productionBaseURL.host!
        }
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allowedCatalogOriginHosts.contains(host) ? host : productionBaseURL.host!
    }

    private static func originURL(for host: String) -> URL {
        URL(string: "https://\(host)")!
    }

    /// A staging build supplies this through Info.plist/Xcode configuration.
    /// If the setting is absent or unresolved, production remains the safe
    /// release default so ordinary app builds keep the existing endpoint.
    static var defaultBaseURL: URL {
        let expectedHost = configuredOriginHost
        if let raw = Bundle.main.object(forInfoDictionaryKey: "POKEMON_CATALOG_BASE_URL") as? String,
           let configured = URL(string: raw),
           isAllowedCatalogOrigin(configured, expectedHost: expectedHost),
           !raw.contains("$(") {
            return configured
        }
        return originURL(for: expectedHost)
    }
    private static let pointerPath = "v1/current.json"
    private static let maxRetries = 2
    private static let retryBaseDelay: TimeInterval = 2

    private let session: URLSession
    private let baseURL: URL
    private let diagnostics: PokemonCatalogRolloutDiagnostics
    private var lastETag: String?
    private var lastModified: String?

    init(
        session: URLSession = .shared,
        baseURL: URL = PokemonCatalogUpdateClient.defaultBaseURL,
        diagnostics: PokemonCatalogRolloutDiagnostics = .shared
    ) {
        self.session = session
        self.baseURL = Self.isAllowedCatalogOrigin(
            baseURL,
            expectedHost: Self.configuredOriginHost
        )
            ? baseURL
            : Self.originURL(for: Self.configuredOriginHost)
        self.diagnostics = diagnostics
    }

    func fetch() async throws -> FetchResult {
        let url = baseURL.appendingPathComponent(Self.pointerPath)
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        if let etag = lastETag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let modified = lastModified {
            request.setValue(modified, forHTTPHeaderField: "If-Modified-Since")
        }

        var lastError: Error?
        for attempt in 0...Self.maxRetries {
            try Task.checkCancellation()
            if attempt > 0 {
                let jitter = Double.random(in: 0...0.5)
                let delay = Self.retryBaseDelay * pow(2, Double(attempt - 1)) + jitter
                try await Task.sleep(for: .seconds(delay))
                try Task.checkCancellation()
            }
            let networkState = PerformanceSignpost.beginInterval(
                "pokemonCatalogNetwork",
                id: PerformanceSignpost.makeID(),
                "attempt=\(attempt)"
            )
            defer {
                PerformanceSignpost.endInterval(
                    "pokemonCatalogNetwork",
                    networkState,
                    "attempt=\(attempt)"
                )
            }
            await diagnostics.recordNetworkRequest(attempt: attempt)
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw UpdateError.badResponse(statusCode: 0)
                }

                await diagnostics.recordNetworkResponse(
                    statusCode: http.statusCode,
                    bytes: data.count,
                    attempt: attempt
                )

                if http.statusCode == 304 {
                    await diagnostics.recordNotModified()
                    Self.logger.info("Catalog release not modified (304)")
                    return .notModified
                }

                guard (200..<300).contains(http.statusCode) else {
                    let error = UpdateError.badResponse(statusCode: http.statusCode)
                    if http.statusCode >= 500 {
                        lastError = error
                        continue
                    }
                    throw error
                }

                guard data.count <= Self.maxPayloadBytes else {
                    throw UpdateError.payloadTooLarge(bytes: data.count)
                }

                lastETag = http.value(forHTTPHeaderField: "ETag")
                lastModified = http.value(forHTTPHeaderField: "Last-Modified")

                let decoder = JSONDecoder()
                let envelope = try decoder.decode(PokemonCatalogReleaseEnvelope.self, from: data)
                Self.logger.info("Fetched catalog release envelope")
                return .fetched(envelope)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as UpdateError {
                throw error
            } catch {
                lastError = UpdateError.networkFailure(error)
                if attempt < Self.maxRetries {
                    continue
                }
                await diagnostics.recordNetworkFailure(error)
            }
        }
        throw lastError ?? UpdateError.networkFailure(
            NSError(domain: "PokemonCatalogUpdateClient", code: -1)
        )
    }

    #if DEBUG
    func resetConditionalState() {
        lastETag = nil
        lastModified = nil
    }
    #endif
}
