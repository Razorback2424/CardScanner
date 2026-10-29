import Foundation

/// Devices consume the app's server-ingested feeds. Upstream TCGCSV is only
/// contacted by the daily publisher, never by a user-facing app or a redirect.
enum TCGCSVPriceMirror {
    static var baseURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "TCGCSV_PRICE_BASE_URL") as? String,
              let url = URL(string: value), isPermitted(url),
              ["catalog.scan-stash.com", "scanstash-catalog-prod.web.app"].contains(url.host?.lowercased() ?? ""),
              url.path == "/market-prices/v1" else { return nil }
        return url
    }

    static func isPermitted(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(),
              !host.isEmpty, host != "tcgcsv.com", !host.hasSuffix(".tcgcsv.com"),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.port == nil || url.port == 443 else { return false }
        return true
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
    static let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)

    /// The server's original capture time survives CDN fetches and app relaunch.
    /// Matching daily-build markers prevent independently cached files mixing.
    static func captureDate(products: Data, prices: Data, expectedBuild: String? = nil,
                            now: Date = .now) throws -> Date {
        struct Metadata: Decodable { let sourceBuild: String; let sourceFetchedAt: String }
        func date(_ string: String) -> Date? {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
        }
        guard let product = try? JSONDecoder().decode(Metadata.self, from: products),
              let price = try? JSONDecoder().decode(Metadata.self, from: prices),
              product.sourceBuild == price.sourceBuild,
              expectedBuild.map({ $0 == price.sourceBuild }) ?? true,
              let build = date(price.sourceBuild), let captured = date(price.sourceFetchedAt),
              let productCaptured = date(product.sourceFetchedAt),
              build <= captured, build <= productCaptured,
              captured <= now, productCaptured <= now,
              now.timeIntervalSince(captured) < 86_400,
              now.timeIntervalSince(productCaptured) < 86_400 else { throw PriceQuoteError.providerUnavailable }
        return captured
    }
}

/// Product-level USD market observations. No condition-specific SKU is claimed.
actor TCGCSVProductPriceSource {
    static let shared = TCGCSVProductPriceSource()
    private struct Response<Row: Decodable>: Decodable {
        let success: Bool
        let errors: [String]
        let results: [Row]
        let totalItems: Int?
    }
    private struct Product: Codable, Sendable {
        struct Field: Codable, Sendable { let name: String; let value: String }
        let productId: Int; let categoryId: Int; let groupId: Int
        let name: String; let extendedData: [Field]
    }
    private struct Price: Codable, Sendable {
        let productId: Int; let subTypeName: String; let marketPrice: Double?
    }
    private struct Snapshot: Codable, Sendable {
        let products: [Product]; let prices: [Price]; let fetchedAt: Date
        var catalogGeneration: String? = nil
    }
    private let session: URLSession
    private let baseURL: URL?
    private let cacheDirectory: URL
    private struct GroupKey: Hashable { let category: Int; let group: Int }
    private struct CacheKey: Hashable {
        let group: GroupKey
        let generation: String?
        let minimumFetchedAt: Date?
    }
    private struct LaneKey: Hashable {
        let productID: Int
        let lane: String
    }
    private var snapshots: [GroupKey: Snapshot] = [:]
    private var pending: [CacheKey: Task<Snapshot, Error>] = [:]
    private var failures: [CacheKey: Date] = [:]
    private var nextRequestAt = Date.distantPast
    init(baseURL: URL? = TCGCSVPriceMirror.baseURL,
         session: URLSession = TCGCSVPriceMirror.session,
         cacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TCGCSVProductPrices-v1")) {
        self.session = session; self.baseURL = baseURL; self.cacheDirectory = cacheDirectory
    }

    func quote(category: Int, group: Int, productID: Int, name: String, number: String?,
               lane: String, generation: String?, minimumFetchedAt: Date?) async throws -> PriceLookup {
        guard category > 0, group > 0, productID > 0, !name.isEmpty, number != "",
              ["Normal", "Foil", "Cold Foil", "Holofoil", "1st Edition", "Unlimited", "Limited"].contains(lane) else { throw PriceQuoteError.identityMismatch }
        let groupKey = GroupKey(category: category, group: group)
        let snapshot = try await snapshot(group: groupKey, generation: generation, minimumFetchedAt: minimumFetchedAt)
        try Task.checkCancellation()
        let products = snapshot.products.filter { $0.productId == productID }
        guard products.count == 1, let product = products.first,
              product.categoryId == category, product.groupId == group, product.name == name,
              product.extendedData.filter({ $0.name == "Number" }).map(\.value) == number.map({ [$0] }) ?? [] else {
            throw PriceQuoteError.identityMismatch
        }
        let rows = snapshot.prices.filter { $0.productId == productID && $0.subTypeName == lane }
        guard rows.count <= 1 else { throw PriceQuoteError.identityMismatch }
        guard let amount = rows.first?.marketPrice else { return .unavailable(.tcgCSV) }
        guard amount.isFinite, amount >= 0 else { throw PriceQuoteError.providerUnavailable }
        return .price(.init(unitMarketPriceUSD: amount, currencyCode: "USD", source: .tcgCSV,
            sourceVariantID: "tcgplayer:\(productID):\(lane)", sourceUpdatedAt: nil, fetchedAt: snapshot.fetchedAt))
    }

    private func snapshot(group: GroupKey, generation: String?, minimumFetchedAt: Date?) async throws -> Snapshot {
        // A withdrawal starts a new request cohort. It must not join a fetch
        // that began before its watermark, even within the same generation.
        let key = CacheKey(group: group, generation: generation, minimumFetchedAt: minimumFetchedAt)
        let file = cacheDirectory.appendingPathComponent("\(group.category)-\(group.group).json")
        if snapshots[group]?.catalogGeneration != generation || snapshots[group] == nil,
           let bytes = try? Data(contentsOf: file), bytes.count <= 16 * 1_024 * 1_024,
           let value = try? JSONDecoder().decode(Snapshot.self, from: bytes), value.catalogGeneration == generation,
           (try? validate(value, group: group)) != nil {
            snapshots[group] = value
        }
        if let cached = snapshots[group], cached.catalogGeneration == generation,
           minimumFetchedAt.map({ cached.fetchedAt > $0 }) ?? true,
           Date.now.timeIntervalSince(cached.fetchedAt) >= 0,
           Date.now.timeIntervalSince(cached.fetchedAt) < 86_400 { return cached }
        if let task = pending[key] {
            let result = try await task.value
            if minimumFetchedAt.map({ result.fetchedAt > $0 }) ?? true { return result }
            throw PriceQuoteError.providerUnavailable
        }
        if let failure = failures[key], Date.now.timeIntervalSince(failure) < 900 {
            throw PriceQuoteError.providerUnavailable
        }
        let task = Task {
            let productsData = try await self.fetch(group: group, resource: "products")
            let pricesData = try await self.fetch(group: group, resource: "prices")
            let fetchedAt = try TCGCSVPriceMirror.captureDate(products: productsData, prices: pricesData)
            let products = try JSONDecoder().decode(Response<Product>.self, from: productsData)
            let prices = try JSONDecoder().decode(Response<Price>.self, from: pricesData)
            guard products.success, products.errors.isEmpty, prices.success, prices.errors.isEmpty,
                  products.totalItems.map({ $0 == products.results.count }) ?? true,
                  prices.totalItems.map({ $0 == prices.results.count }) ?? true else {
                throw PriceQuoteError.providerUnavailable
            }
            let snapshot = Snapshot(products: products.results, prices: prices.results, fetchedAt: fetchedAt,
                catalogGeneration: generation)
            try self.validate(snapshot, group: group)
            return snapshot
        }
        pending[key] = task
        defer { pending[key] = nil }
        let value: Snapshot
        do { value = try await task.value; failures[key] = nil }
        catch {
            // A transport interruption is not a provider response. Let a later
            // user refresh retry when connectivity returns; retain the cooldown
            // for rejected HTTP responses and malformed/failed feed envelopes.
            if !(error is CancellationError), !(error is URLError) { failures[key] = .now }
            throw error
        }
        guard minimumFetchedAt.map({ value.fetchedAt > $0 }) ?? true else {
            throw PriceQuoteError.providerUnavailable
        }
        // A slower, older request must not replace a newer cached observation.
        if snapshots[group].map({ value.fetchedAt >= $0.fetchedAt }) ?? true {
            snapshots[group] = value
        }
        if snapshots[group]?.fetchedAt == value.fetchedAt, let bytes = try? JSONEncoder().encode(value) {
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try? bytes.write(to: file, options: .atomic)
        }
        return value
    }

    /// Reject invalid group responses before either cache can retain them for
    /// a day. Apply the same contract to disk snapshots from older app versions.
    private func validate(_ snapshot: Snapshot, group: GroupKey) throws {
        guard snapshot.products.allSatisfy({ $0.categoryId == group.category && $0.groupId == group.group }),
              Set(snapshot.products.map(\.productId)).count == snapshot.products.count,
              Set(snapshot.prices.map { LaneKey(productID: $0.productId, lane: $0.subTypeName) }).count == snapshot.prices.count else {
            throw PriceQuoteError.identityMismatch
        }
        guard snapshot.prices.allSatisfy({ row in
            guard let amount = row.marketPrice else { return true }
            return amount >= 0 && Money(rounding: amount) != nil
        }) else { throw PriceQuoteError.providerUnavailable }
    }

    private func fetch(group: GroupKey, resource: String) async throws -> Data {
        guard let baseURL, TCGCSVPriceMirror.isPermitted(baseURL) else { throw PriceQuoteError.providerUnavailable }
        let start = max(nextRequestAt, .now)
        nextRequestAt = start.addingTimeInterval(0.1)
        if start.timeIntervalSinceNow > 0 { try await Task.sleep(for: .seconds(start.timeIntervalSinceNow)) }
        var request = URLRequest(url: baseURL.appendingPathComponent("tcgplayer/\(group.category)/\(group.group)/\(resource)"))
        request.timeoutInterval = 15
        request.setValue("ScanStash/1.0 (iOS; daily product market pricing)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url == request.url,
              data.count <= 8 * 1_024 * 1_024 else { throw PriceQuoteError.providerUnavailable }
        return data
    }
}
