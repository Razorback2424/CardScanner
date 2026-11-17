import Foundation

/// Process-wide pacing for `api.scryfall.com`.
///
/// Scryfall publishes hard per-endpoint limits and counts every request from
/// this device together, whichever feature sent it. Browse, the scanner and
/// the Catalog Health export therefore share one pacer: a long export must not
/// push an interactive Browse search over the limit, and one 429 must quiet
/// every caller instead of only the one that received it.
///
/// Published limits (https://scryfall.com/docs/api/rate-limits):
/// `/cards/search`, `/cards/named`, `/cards/random` and `/cards/collection`
/// allow 2 requests per second; other API methods allow 10 per second. A 429
/// limits access for 30 seconds. The `*.scryfall.io` file origins (images and
/// bulk data) have no rate limit and are not paced.
actor ScryfallRequestPacer {
    static let shared = ScryfallRequestPacer()

    enum Bucket: Hashable, Sendable {
        /// The 2-per-second card query endpoints.
        case search
        /// Every other `api.scryfall.com` method.
        case general
    }

    /// Margin above the published 500 ms so network jitter cannot compress
    /// two request arrivals below the limit.
    static let searchSpacing: Duration = .milliseconds(600)
    /// Margin above the published 100 ms.
    static let generalSpacing: Duration = .milliseconds(120)
    /// Scryfall's documented access limitation after a 429.
    static let rateLimitLockout: TimeInterval = 30

    private let clock = ContinuousClock()
    private let searchSpacing: Duration
    private let generalSpacing: Duration
    private let now: @Sendable () -> Date
    private var nextStart: [Bucket: ContinuousClock.Instant] = [:]
    private var lockedUntil: Date?

    init(searchSpacing: Duration = ScryfallRequestPacer.searchSpacing,
         generalSpacing: Duration = ScryfallRequestPacer.generalSpacing,
         now: @escaping @Sendable () -> Date = { .now }) {
        self.searchSpacing = searchSpacing
        self.generalSpacing = generalSpacing
        self.now = now
    }

    /// `nil` means the URL is not a rate-limited Scryfall API request.
    nonisolated static func bucket(for url: URL) -> Bucket? {
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == "api.scryfall.com" else {
            return nil
        }
        switch url.path {
        case "/cards/search", "/cards/named", "/cards/random", "/cards/collection": return .search
        default: return .general
        }
    }

    /// Waits until this request may start. While a rate-limit lockout is
    /// active the call fails immediately with `ScryfallError.rateLimited`
    /// rather than queueing more requests behind it.
    ///
    /// A waiter claims its slot only once it is due, so a cancelled request
    /// (for example a superseded Browse search) never delays later callers.
    func acquire(for url: URL) async throws {
        guard let bucket = Self.bucket(for: url) else { return }
        while true {
            try Task.checkCancellation()
            if let remaining = lockoutRemaining {
                throw ScryfallError.rateLimited(retryAfter: remaining)
            }
            let current = clock.now
            if let next = nextStart[bucket], current < next {
                try await clock.sleep(until: next)
            } else {
                nextStart[bucket] = current.advanced(by: bucket == .search ? searchSpacing : generalSpacing)
                return
            }
        }
    }

    /// Records a 429. Scryfall limits access for at least 30 seconds, so a
    /// shorter or missing Retry-After still observes that floor.
    func recordRateLimit(retryAfter: TimeInterval?) {
        extendLockout(by: max(retryAfter ?? 0, Self.rateLimitLockout))
    }

    /// Records a server-requested pause that is not a rate limit, such as a
    /// 503 with Retry-After.
    func recordRetryAfter(_ seconds: TimeInterval) {
        guard seconds.isFinite, seconds > 0 else { return }
        extendLockout(by: seconds)
    }

    /// Remaining lockout in seconds, or `nil` when requests may proceed.
    var lockoutRemaining: TimeInterval? {
        guard let lockedUntil else { return nil }
        let remaining = lockedUntil.timeIntervalSince(now())
        return remaining > 0 ? remaining : nil
    }

    /// Sends one request through the pacer and records a 429 or 503
    /// Retry-After from its response. Status handling otherwise stays with
    /// the caller.
    func data(for request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        if let url = request.url { try await acquire(for: url) }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse { record(http) }
        return (data, response)
    }

    func record(_ response: HTTPURLResponse) {
        let header = response.value(forHTTPHeaderField: "Retry-After")
        switch response.statusCode {
        case 429:
            recordRateLimit(retryAfter: ScryfallService.retryAfter(from: header, now: now()))
        case 503:
            if let delay = ScryfallService.retryAfter(from: header, now: now()) { recordRetryAfter(delay) }
        default:
            break
        }
    }

    private func extendLockout(by seconds: TimeInterval) {
        let until = now().addingTimeInterval(seconds)
        if lockedUntil.map({ until > $0 }) ?? true { lockedUntil = until }
    }
}
