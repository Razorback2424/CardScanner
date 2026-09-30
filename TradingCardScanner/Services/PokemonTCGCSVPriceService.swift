import Foundation

enum PokemonTCGCSVError: Error {
    case unsupportedSet, invalidResponse, identityMismatch, retryLater
}

struct PokemonTCGCSVSnapshot: Codable, Sendable {
    let schemaVersion: Int
    let setID: String
    let feedBuild: String
    let fetchedAt: Date
    var validatedAt: Date
    let valuesByCardID: [String: Double]

    func quote(cardID: String, variant: PhysicalVariant?, printRun: PokemonPrintRun?) -> PriceLookup? {
        guard PokemonTCGCSVMapping.byCardID[cardID]?.setID == setID,
              variant == .holo, printRun == nil || printRun == .unlimited else { return nil }
        guard let amount = valuesByCardID[cardID] else { return .unavailable(.tcgCSV) }
        return .price(NormalizedPrice(
            unitMarketPriceUSD: amount, currencyCode: "USD", source: .tcgCSV,
            sourceVariantID: "holofoil", sourceUpdatedAt: nil, fetchedAt: fetchedAt
        ))
    }
}

protocol PokemonTCGCSVPriceSource: Sendable {
    func snapshot(setID: String, retry: Bool) async throws -> PokemonTCGCSVSnapshot
}

/// One device-local, daily download shared by Browse, scanning and collection refresh.
/// It never participates in card recognition or publishes prices to ScanStash servers.
actor PokemonTCGCSVPriceService: PokemonTCGCSVPriceSource {
    static let shared = PokemonTCGCSVPriceService()
    private let session: URLSession
    private let baseURL: URL
    private let cacheDirectory: URL
    private let now: @Sendable () -> Date
    private let spacing: TimeInterval
    private var snapshots: [String: PokemonTCGCSVSnapshot] = [:]
    private var tasks: [String: Task<PokemonTCGCSVSnapshot, Error>] = [:]
    private var failures: [String: Date] = [:]
    private var build: (value: String, checkedAt: Date)?
    private var buildTask: Task<String, Error>?
    private var nextRequestAt = Date.distantPast

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://tcgcsv.com")!,
        cacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TCGCSV-v1", isDirectory: true),
        now: @escaping @Sendable () -> Date = { .now },
        spacing: TimeInterval = 0.1
    ) {
        self.session = session
        self.baseURL = baseURL
        self.cacheDirectory = cacheDirectory
        self.now = now
        self.spacing = spacing
    }

    func snapshot(setID: String, retry: Bool = false) async throws -> PokemonTCGCSVSnapshot {
        let key = setID.lowercased()
        guard let groupID = PokemonTCGCSVMapping.groupID(for: key) else {
            throw PokemonTCGCSVError.unsupportedSet
        }
        try Task.checkCancellation()
        if let cached = load(key), isFresh(cached.validatedAt) { return cached }
        if let task = tasks[key] {
            return try await waitFor(task)
        }
        if !retry, let failure = failures[key], now().timeIntervalSince(failure) < 15 * 60 {
            throw PokemonTCGCSVError.retryLater
        }
        let task = Task {
            do {
                let result = try await self.download(setID: key, groupID: groupID)
                self.snapshots[key] = result
                self.failures[key] = nil
                self.tasks[key] = nil
                return result
            } catch {
                self.tasks[key] = nil
                if !(error is CancellationError) { self.failures[key] = self.now() }
                throw error
            }
        }
        tasks[key] = task
        return try await waitFor(task)
    }

    /// Cancellation belongs to a waiter, not the shared download another
    /// surface may need. A cancelled scanner need not wait for the HTTP timeout.
    private func waitFor(_ task: Task<PokemonTCGCSVSnapshot, Error>) async throws -> PokemonTCGCSVSnapshot {
        let stream = AsyncThrowingStream<PokemonTCGCSVSnapshot, Error> { continuation in
            let observer = Task {
                do { continuation.yield(try await task.value); continuation.finish() }
                catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in observer.cancel() }
        }
        for try await value in stream {
            try Task.checkCancellation()
            return value
        }
        throw CancellationError()
    }

    private func isFresh(_ date: Date) -> Bool {
        let age = now().timeIntervalSince(date)
        return age >= 0 && age < 24 * 60 * 60
    }

    private func load(_ key: String) -> PokemonTCGCSVSnapshot? {
        if let value = snapshots[key] { return value }
        guard let data = try? Data(contentsOf: cacheURL(key)),
              let value = try? JSONDecoder().decode(PokemonTCGCSVSnapshot.self, from: data),
              value.schemaVersion == 1, value.setID == key,
              value.valuesByCardID.allSatisfy({ cardID, amount in
                  PokemonTCGCSVMapping.byCardID[cardID]?.setID == key && amount.isFinite && amount >= 0
              }) else { return nil }
        snapshots[key] = value
        return value
    }

    private func cacheURL(_ key: String) -> URL {
        cacheDirectory.appendingPathComponent(key + ".json")
    }

    private func download(setID: String, groupID: Int) async throws -> PokemonTCGCSVSnapshot {
        let feedBuild = try await currentBuild()
        var result: PokemonTCGCSVSnapshot
        if var previous = load(setID), previous.feedBuild == feedBuild {
            previous.validatedAt = now()
            result = previous
        } else {
            let productsData = try await fetch("tcgplayer/3/\(groupID)/products")
            let pricesData = try await fetch("tcgplayer/3/\(groupID)/prices")
            result = try Self.decodeSnapshot(
                products: productsData, prices: pricesData, setID: setID,
                feedBuild: feedBuild, fetchedAt: now()
            )
        }
        // A cache write failure must not hide an otherwise valid current quote.
        if let data = try? JSONEncoder().encode(result) {
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try? data.write(to: cacheURL(setID), options: .atomic)
        }
        return result
    }

    private func currentBuild() async throws -> String {
        if let build, isFresh(build.checkedAt) { return build.value }
        if let task = buildTask { return try await task.value }
        let task = Task {
            let data = try await self.fetch("last-updated.txt")
            guard let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  raw.count < 100, ISO8601DateFormatter().date(from: raw) != nil else {
                throw PokemonTCGCSVError.invalidResponse
            }
            return raw
        }
        buildTask = task
        do {
            let value = try await task.value
            build = (value, now())
            buildTask = nil
            return value
        } catch {
            buildTask = nil
            throw error
        }
    }

    private func fetch(_ path: String) async throws -> Data {
        let requestAt = max(nextRequestAt, Date.now)
        nextRequestAt = requestAt.addingTimeInterval(spacing)
        let delay = requestAt.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("ScanStash/1.0 (iOS; daily set pricing)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PokemonTCGCSVError.invalidResponse
        }
        return data
    }

    static func decodeSnapshot(
        products: Data, prices: Data, setID: String, feedBuild: String, fetchedAt: Date
    ) throws -> PokemonTCGCSVSnapshot {
        guard let groupID = PokemonTCGCSVMapping.groupID(for: setID) else {
            throw PokemonTCGCSVError.unsupportedSet
        }
        let productResponse = try JSONDecoder().decode(Response<Product>.self, from: products)
        let priceResponse = try JSONDecoder().decode(Response<Price>.self, from: prices)
        guard productResponse.success, productResponse.errors.isEmpty,
              priceResponse.success, priceResponse.errors.isEmpty,
              productResponse.totalItems.map({ $0 == productResponse.results.count }) ?? true else {
            throw PokemonTCGCSVError.invalidResponse
        }
        let productsByID = Dictionary(grouping: productResponse.results, by: \.productId)
        let pricesByID = Dictionary(grouping: priceResponse.results, by: \.productId)
        var values: [String: Double] = [:]
        for mapping in PokemonTCGCSVMapping.entries where mapping.setID == setID {
            guard let matched = productsByID[mapping.productID], matched.count == 1,
                  let product = matched.first, product.categoryId == 3, product.groupId == groupID,
                  normalizedName(product.name) == normalizedName(mapping.productName),
                  product.extendedData.filter({ $0.name == "Number" }).count == 1,
                  let number = product.extendedData.first(where: { $0.name == "Number" })?.value,
                  normalizedNumber(number) == normalizedNumber(mapping.printedNumber) else {
                throw PokemonTCGCSVError.identityMismatch
            }
            let rows = (pricesByID[mapping.productID] ?? []).filter { $0.subTypeName == "Holofoil" }
            guard rows.count <= 1 else { throw PokemonTCGCSVError.invalidResponse }
            if let amount = rows.first?.marketPrice {
                guard amount.isFinite, amount >= 0 else { throw PokemonTCGCSVError.invalidResponse }
                values[mapping.cardID] = amount
            }
        }
        return PokemonTCGCSVSnapshot(
            schemaVersion: 1, setID: setID, feedBuild: feedBuild,
            fetchedAt: fetchedAt, validatedAt: fetchedAt, valuesByCardID: values
        )
    }

    private static func normalizedName(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "&", with: "and")
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    private static func normalizedNumber(_ value: String) -> String {
        value.split(separator: "/").map { Int($0).map(String.init) ?? String($0) }.joined(separator: "/")
    }

    private struct Response<T: Decodable>: Decodable {
        let success: Bool
        let errors: [String]
        let totalItems: Int?
        let results: [T]
    }
    private struct Product: Decodable {
        let productId: Int
        let name: String
        let categoryId: Int
        let groupId: Int
        let extendedData: [Field]
    }
    private struct Field: Decodable { let name: String; let value: String }
    private struct Price: Decodable {
        let productId: Int
        let subTypeName: String
        let marketPrice: Double?
    }
}

/// Exact-identity fallback policy shared by all price surfaces. No recognition work.
struct PokemonMarketPriceResolver: Sendable {
    let source: any PokemonTCGCSVPriceSource
    init(source: any PokemonTCGCSVPriceSource = PokemonTCGCSVPriceService.shared) { self.source = source }

    func fallback(
        cardID: String, game: CardGame, variant: PhysicalVariant?, printRun: PokemonPrintRun?,
        retry: Bool = false
    ) async throws -> PriceLookup? {
        guard game == .pokemon, variant == .holo,
              printRun == nil || printRun == .unlimited,
              let mapping = PokemonTCGCSVMapping.byCardID[cardID] else { return nil }
        let snapshot = try await source.snapshot(setID: mapping.setID, retry: retry)
        try Task.checkCancellation()
        return snapshot.quote(cardID: cardID, variant: variant, printRun: printRun)
    }

    func price(for card: IdentifiedCard, variant: PhysicalVariant?, printRun: PokemonPrintRun?) async -> PriceLookup {
        let catalog = CardPricing.price(
            for: card, variant: variant, magicTreatments: card.magicTreatments(for: variant), pokemonPrintRun: printRun
        )
        if case let .price(price) = catalog, price.currencyCode == "USD" { return catalog }
        return (try? await fallback(cardID: card.providerID, game: card.game, variant: variant, printRun: printRun)) ?? catalog
    }
}
