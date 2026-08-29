import Foundation

/// Serializes request start times across every JustTCG API client.
///
/// Waiters are held until their slot is actually available instead of reserving
/// timestamps in advance. That makes cancellation cheap: a cancelled waiter is
/// removed without consuming a request slot. Interactive work is selected ahead
/// of queued background work, while requests within each lane remain FIFO.
actor JustTCGPacer {
    static let shared = JustTCGPacer()

    private struct Waiter {
        let id: UUID
        let lane: JustTCGRequestLane
        let minimumInterval: TimeInterval
        let continuation: CheckedContinuation<Void, Error>
    }

    private var waiters: [Waiter] = []
    private var lastGrantedAt: Date?
    private var lastGrantedInterval: TimeInterval = 0
    private var timer: Task<Void, Never>?
    private var timerGeneration: UInt = 0

    func wait(
        lane: JustTCGRequestLane,
        minimumInterval: TimeInterval
    ) async throws {
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                enqueue(
                    Waiter(
                        id: id,
                        lane: lane,
                        minimumInterval: minimumInterval,
                        continuation: continuation
                    )
                )
            }
        }, onCancel: {
            Task { await self.cancel(id: id) }
        })
    }

    private func enqueue(_ waiter: Waiter) {
        guard !Task.isCancelled else {
            waiter.continuation.resume(throwing: CancellationError())
            return
        }
        waiters.append(waiter)
        restartTimer()
    }

    private func cancel(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
        restartTimer()
    }

    private func restartTimer() {
        timerGeneration &+= 1
        timer?.cancel()
        timer = nil
        scheduleNext()
    }

    private func scheduleNext() {
        guard timer == nil else { return }

        while !waiters.isEmpty {
            let index = nextWaiterIndex()
            let waiter = waiters[index]
            let now = Date.now
            let requiredGap = max(waiter.minimumInterval, lastGrantedInterval)
            let earliest = lastGrantedAt?.addingTimeInterval(requiredGap) ?? now
            let delay = earliest.timeIntervalSince(now)

            if delay > 0 {
                let generation = timerGeneration
                timer = Task { [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(delay))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    await self?.fireTimer(generation: generation)
                }
                return
            }

            let granted = waiters.remove(at: index)
            lastGrantedAt = now
            lastGrantedInterval = waiter.minimumInterval
            granted.continuation.resume()
        }
    }

    private func fireTimer(generation: UInt) {
        guard generation == timerGeneration else { return }
        timer = nil
        scheduleNext()
    }

    private func nextWaiterIndex() -> Int {
        waiters.firstIndex(where: { $0.lane == .interactive }) ?? 0
    }
}

/// Which lane a request is spending from.
///
/// Background refreshes stop short of the daily ceiling so that an explicit user
/// action — opening a sealed set, choosing a grade — still works at 5pm. Without
/// this, an overnight refresh would routinely leave the app unable to answer the
/// one question the user actually asked.
enum JustTCGRequestLane: Sendable, Equatable {
    /// Automatic refreshes. Stops at the background ceiling.
    case background
    /// Something the user is waiting on. May spend into the reserve.
    case interactive

    var ceiling: Int {
        switch self {
        case .background: return JustTCGQuota.backgroundDailyCeiling
        case .interactive: return JustTCGQuota.dailyHardLimit
        }
    }
}

/// The tier's published allowances, held below the documented limits so that a
/// vendor-side accounting difference cannot turn into a hard failure.
enum JustTCGQuota {
    /// Documented free tier is 100/day; keep five requests of headroom for
    /// provider-side accounting differences and out-of-app usage.
    static let dailyHardLimit = 95
    /// Documented free tier is 1,000/month; 900 keeps the same headroom.
    static let monthlyHardLimit = 900
    /// Background work stops here, leaving 20 for interactive work such as
    /// resolving sealed products and opening marketplace catalog screens.
    static let backgroundDailyCeiling = 75
    /// Free tier batch size. One request carries this many variants.
    static let batchSize = 20
    /// The largest `limit` a list request may ask for. The free plan rejects
    /// anything above this outright — `{"error": "Limit must be between 1 and
    /// 20 for your plan."}` — which failed the whole request rather than
    /// returning a short page, so sealed discovery came back empty and its
    /// products were left with neither a price nor a picture.
    static let maximumPageSize = 20

    /// One POST of `batchSize` items costs exactly one request. This is the
    /// whole reason batching matters: 2,000 variants is 100 requests, not 2,000.
    static func requestsNeeded(forVariants count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int((Double(count) / Double(batchSize)).rounded(.up))
    }
}

/// Authentication, pacing, quota accounting and rate-limit backoff for every
/// JustTCG call.
///
/// One actor so that its ledger cannot be raced and its pacing cannot be
/// defeated by concurrency. The legacy product fallback has a direct request
/// path, but it shares this type's pacer and persisted ledger.
actor JustTCGTransport {
    /// Collection refreshes and interactive Price Check requests share one
    /// pacer. The persisted ledger already shares quota; sharing the actor also
    /// keeps concurrent requests from bypassing the vendor's rate limit.
    static let shared = JustTCGTransport()

    struct Configuration: Sendable {
        var baseURL = URL(string: "https://api.justtcg.com")!
        /// Free tier allows 10 requests/minute.
        var minimumRequestInterval: TimeInterval = 6.5
        var timeout: TimeInterval = 25
    }

    enum TransportError: LocalizedError {
        case missingCredentials
        case invalidURL
        case badResponse(status: Int)
        case budgetReached(resetAt: Date)
        case monthlyBudgetReached(resetAt: Date)
        case rateLimited(retryAt: Date)

        var errorDescription: String? {
            switch self {
            case .missingCredentials: return "No pricing API key is saved."
            case .invalidURL: return "The pricing request could not be built."
            case let .badResponse(status): return "The pricing service returned \(status)."
            case .budgetReached: return "Today's pricing request budget is used up."
            case .monthlyBudgetReached: return "This month's pricing request budget is used up."
            case .rateLimited: return "The pricing service asked us to wait."
            }
        }
    }

    private let configuration: Configuration
    private let session: URLSession
    private let ledger: JustTCGRequestLedger
    private let pacer: JustTCGPacer
    private let apiKeyOverride: String?

    init(
        configuration: Configuration = Configuration(),
        session: URLSession = .shared,
        ledger: JustTCGRequestLedger = JustTCGRequestLedger(),
        pacer: JustTCGPacer = .shared,
        apiKeyOverride: String? = nil
    ) {
        self.configuration = configuration
        self.session = session
        self.ledger = ledger
        self.pacer = pacer
        self.apiKeyOverride = apiKeyOverride
    }

    func snapshot(now: Date = .now) -> JustTCGRequestLedger.Snapshot {
        ledger.snapshot(now: now)
    }

    // MARK: - Requests

    func get<Response: Decodable>(
        _ path: String,
        query: [(String, String)] = [],
        lane: JustTCGRequestLane,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let request = try buildRequest(path: path, query: query, method: "GET", body: nil)
        return try await perform(request, lane: lane)
    }

    func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        query: [(String, String)] = [],
        body: Body,
        lane: JustTCGRequestLane,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let encoded = try JSONEncoder().encode(body)
        let request = try buildRequest(path: path, query: query, method: "POST", body: encoded)
        return try await perform(request, lane: lane)
    }

    private func perform<Response: Decodable>(
        _ request: URLRequest,
        lane: JustTCGRequestLane
    ) async throws -> Response {
        // Pace before reserving. If a queued request is cancelled while waiting,
        // it never consumes the day's allowance.
        try await pace(lane: lane)
        guard !Task.isCancelled else { throw CancellationError() }

        // Reserve immediately before the call, never optimistically in advance,
        // so an abandoned plan does not silently consume the day's allowance.
        switch ledger.reserve(lane: lane) {
        case .allowed:
            break
        case let .dailyReached(resetAt):
            throw TransportError.budgetReached(resetAt: resetAt)
        case let .monthlyReached(resetAt):
            throw TransportError.monthlyBudgetReached(resetAt: resetAt)
        case let .rateLimited(retryAt):
            throw TransportError.rateLimited(retryAt: retryAt)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TransportError.badResponse(status: -1)
        }

        if http.statusCode == 429 {
            let retryAt = Self.retryDate(
                from: http.value(forHTTPHeaderField: "Retry-After"),
                now: .now
            ) ?? Date.now.addingTimeInterval(60 * 15)
            // Persisted, so a 429 near the end of a session still holds after a
            // relaunch rather than being retried immediately.
            ledger.recordRateLimit(until: retryAt)
            throw TransportError.rateLimited(retryAt: retryAt)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw TransportError.badResponse(status: http.statusCode)
        }

        // Every response carries the vendor's own view of the allowance. A
        // second cheap decode over bytes already in hand — no extra request —
        // keeps the local ledger honest against an account that may have been
        // spent from elsewhere.
        if let envelope = try? JSONDecoder().decode(QuotaEnvelope.self, from: data),
           let metadata = envelope.metadata {
            ledger.syncFromServer(metadata)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func buildRequest(
        path: String,
        query: [(String, String)],
        method: String,
        body: Data?
    ) throws -> URLRequest {
        guard let key = apiKeyOverride ?? PriceVendorCredentials.key else {
            throw TransportError.missingCredentials
        }
        guard var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw TransportError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        guard let url = components.url else { throw TransportError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = configuration.timeout
        request.httpBody = body
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        // Cloudflare fronts this API and rejects a default client User-Agent
        // with error 1010 — a 403 that reads exactly like an auth failure.
        request.setValue("TradingCardScanner/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func pace(lane: JustTCGRequestLane) async throws {
        try await pacer.wait(
            lane: lane,
            minimumInterval: configuration.minimumRequestInterval
        )
    }

    /// Just the quota block, for reading it out of any response regardless of
    /// what the caller asked to decode.
    private struct QuotaEnvelope: Decodable {
        let metadata: JustTCGQuotaMetadata?

        enum CodingKeys: String, CodingKey {
            case metadata = "_metadata"
        }
    }

    /// `Retry-After` is either delta-seconds or an HTTP date. Both are accepted
    /// because servers use both, and guessing wrong means either hammering a
    /// rate-limited endpoint or sleeping for hours.
    nonisolated static func retryDate(from value: String?, now: Date) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(value) { return now.addingTimeInterval(seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }
}
