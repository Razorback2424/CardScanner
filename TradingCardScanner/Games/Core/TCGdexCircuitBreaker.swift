import Foundation

actor TCGdexCircuitBreaker {
    /// Outage state belongs to the host, not to whichever type noticed first.
    /// The catalog and the price refresher both talk to TCGdex, and a private
    /// breaker each meant the second caller re-paid the connect timeout the
    /// first had already established was hopeless.
    static let shared = TCGdexCircuitBreaker()
    /// Scryfall has a separate quota and outage domain from TCGdex, but uses the
    /// same circuit implementation. Keeping a distinct instance prevents a
    /// Scryfall outage from suppressing Pokémon lookups (and vice versa).
    static let scryfallShared = TCGdexCircuitBreaker()

    /// How badly the provider failed, which decides how long to stay away.
    ///
    /// These are not the same outage. A 5xx is a host that answered — the next
    /// request may well succeed, and banishing it for ten minutes would throw
    /// away a working provider. A refused or timed-out connection is a host
    /// that is not there, and re-probing it costs the full timeout every time.
    enum Failure: Equatable {
        /// The host answered, badly. Retry soon.
        case serverError
        /// Nothing answered: connection refused, DNS failure, or timeout.
        case unreachable
        /// The provider explicitly asked the client to wait.
        case rateLimited

        var base: TimeInterval {
            switch self {
            case .serverError: return 10
            case .unreachable: return 30
            case .rateLimited: return 60
            }
        }

        var cap: TimeInterval {
            switch self {
            case .serverError: return 60
            case .unreachable: return 600
            case .rateLimited: return 600
            }
        }
    }

    private let baseCooldown: TimeInterval?
    private var unavailableUntil: Date?
    /// Survives cooldown expiry on purpose. A probe that fails again must back
    /// off further than the one before it, which cannot happen if the count is
    /// cleared every time the door is reopened.
    private var consecutiveFailures = 0

    /// - Parameter cooldown: fixes the cooldown at one value, for tests that
    ///   need a deterministic window. Production leaves this nil and lets the
    ///   failure kind decide.
    init(cooldown: TimeInterval? = nil) {
        self.baseCooldown = cooldown.map { max($0, 0) }
    }

    func permitsRequest(now: Date = .now) -> Bool {
        guard let unavailableUntil else { return true }
        if now >= unavailableUntil {
            self.unavailableUntil = nil
            return true
        }
        return false
    }

    func recordSuccess() {
        unavailableUntil = nil
        consecutiveFailures = 0
    }

    func recordFailure(
        _ failure: Failure = .unreachable,
        now: Date = .now,
        cooldownOverride: TimeInterval? = nil
    ) {
        consecutiveFailures += 1
        unavailableUntil = now.addingTimeInterval(
            max(cooldownOverride ?? cooldown(for: failure), 0)
        )
    }

    private func cooldown(for failure: Failure) -> TimeInterval {
        if let baseCooldown { return baseCooldown }
        // 30s, 60, 120, 240 … capped. `consecutiveFailures` is at least 1 here.
        let exponent = min(consecutiveFailures - 1, 16)
        let scaled = failure.base * pow(2, Double(exponent))
        return min(scaled, failure.cap)
    }
}

/// The two provider calls used on the Pokémon scan path. Keeping them behind a
/// single seam makes the fallback order testable without URL loading, while the
/// concrete adapter preserves the production timeouts and retry behavior.
