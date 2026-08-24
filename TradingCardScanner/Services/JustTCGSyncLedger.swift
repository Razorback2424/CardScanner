import Foundation

/// The persisted record of how much of the vendor's allowance has been spent.
///
/// Not an actor: it is only ever touched from inside `JustTCGTransport`, which
/// is one. Keeping it a plain type makes it directly testable against an
/// injected `UserDefaults` suite without awaiting anything.
struct JustTCGRequestLedger: Sendable {
    struct Snapshot: Equatable, Sendable {
        let usedToday: Int
        let remainingToday: Int
        let usedThisMonth: Int
        let remainingThisMonth: Int
        let dailyResetAt: Date
        let monthlyResetAt: Date
        let retryAt: Date?

        /// What the collection status line reports.
        var dailyDescription: String {
            "\(remainingToday)/\(JustTCGQuota.dailyHardLimit) requests available today"
        }

        var monthlyDescription: String {
            "\(remainingThisMonth)/\(JustTCGQuota.monthlyHardLimit) requests available this month"
        }
    }

    enum Reservation: Equatable, Sendable {
        case allowed
        case dailyReached(resetAt: Date)
        case monthlyReached(resetAt: Date)
        case rateLimited(retryAt: Date)
    }

    private let defaults: UserDefaults
    private let dayKey = "justTCGBudgetDay"
    private let monthKey = "justTCGBudgetMonth"
    private let usedTodayKey = "justTCGRequestsUsedToday"
    private let usedMonthKey = "justTCGRequestsUsedThisMonth"
    private let blockedUntilKey = "justTCGBlockedUntil"
    private let runKey = "justTCGRunRequests"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func beginRun() {
        defaults.set(0, forKey: runKey)
        rolloverIfNeeded(now: .now)
    }

    /// Take one request from the allowance, or explain why it cannot.
    ///
    /// The lane decides the ceiling: background work stops at 75 so the last 15
    /// stay available for whatever the user asks for directly.
    func reserve(lane: JustTCGRequestLane, now: Date = .now) -> Reservation {
        rolloverIfNeeded(now: now)

        if let retryAt = defaults.object(forKey: blockedUntilKey) as? Date, retryAt > now {
            return .rateLimited(retryAt: retryAt)
        }

        let usedMonth = defaults.integer(forKey: usedMonthKey)
        guard usedMonth < JustTCGQuota.monthlyHardLimit else {
            return .monthlyReached(resetAt: nextMonthStart(after: now))
        }

        let usedToday = defaults.integer(forKey: usedTodayKey)
        guard usedToday < lane.ceiling else {
            return .dailyReached(resetAt: nextDayStart(after: now))
        }

        defaults.set(usedToday + 1, forKey: usedTodayKey)
        defaults.set(usedMonth + 1, forKey: usedMonthKey)
        defaults.set(defaults.integer(forKey: runKey) + 1, forKey: runKey)
        return .allowed
    }

    /// A 429 blocks every lane until the server's own retry moment. Recorded
    /// without consuming an allowance — being told to wait is not a request the
    /// user got any value from.
    func recordRateLimit(until date: Date) {
        defaults.set(date, forKey: blockedUntilKey)
    }

    /// Correct the local count against the vendor's own, which every response
    /// carries.
    ///
    /// A local counter can only ever be a guess. It starts at zero on a fresh
    /// install while the account may already have spent most of the day's
    /// allowance; it knows nothing about requests made from another device or
    /// from a script; and it cannot see the vendor's own accounting. The server
    /// reports the truth on every reply, so the local number exists only to
    /// avoid making a request that is already known to fail — and it defers to
    /// this the moment real numbers arrive.
    ///
    /// Takes the higher of the two counts, never the lower: if the app believes
    /// it has spent more than the server has recorded yet, spending down to the
    /// server's number would overshoot the limit.
    func syncFromServer(_ metadata: JustTCGQuotaMetadata, now: Date = .now) {
        rolloverIfNeeded(now: now)
        if let used = metadata.apiDailyRequestsUsed {
            defaults.set(max(used, defaults.integer(forKey: usedTodayKey)), forKey: usedTodayKey)
        }
        if let used = metadata.apiRequestsUsed {
            defaults.set(max(used, defaults.integer(forKey: usedMonthKey)), forKey: usedMonthKey)
        }
    }

    func snapshot(now: Date = .now) -> Snapshot {
        rolloverIfNeeded(now: now)
        let usedToday = defaults.integer(forKey: usedTodayKey)
        let usedMonth = defaults.integer(forKey: usedMonthKey)
        return Snapshot(
            usedToday: usedToday,
            remainingToday: max(JustTCGQuota.dailyHardLimit - usedToday, 0),
            usedThisMonth: usedMonth,
            remainingThisMonth: max(JustTCGQuota.monthlyHardLimit - usedMonth, 0),
            dailyResetAt: nextDayStart(after: now),
            monthlyResetAt: nextMonthStart(after: now),
            retryAt: (defaults.object(forKey: blockedUntilKey) as? Date).flatMap {
                $0 > now ? $0 : nil
            }
        )
    }

    // MARK: - Rollover

    private func rolloverIfNeeded(now: Date) {
        let calendar = Self.utcCalendar
        let today = calendar.startOfDay(for: now)
        if defaults.object(forKey: dayKey) as? Date != today {
            defaults.set(today, forKey: dayKey)
            defaults.set(0, forKey: usedTodayKey)
            defaults.removeObject(forKey: blockedUntilKey)
            defaults.set(0, forKey: runKey)
        }

        let month = calendar.dateInterval(of: .month, for: now)?.start ?? today
        if defaults.object(forKey: monthKey) as? Date != month {
            defaults.set(month, forKey: monthKey)
            defaults.set(0, forKey: usedMonthKey)
        }
    }

    private func nextDayStart(after date: Date) -> Date {
        let calendar = Self.utcCalendar
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
            ?? date.addingTimeInterval(24 * 60 * 60)
    }

    private func nextMonthStart(after date: Date) -> Date {
        let calendar = Self.utcCalendar
        let start = calendar.dateInterval(of: .month, for: date)?.start ?? date
        return calendar.date(byAdding: .month, value: 1, to: start)
            ?? date.addingTimeInterval(30 * 24 * 60 * 60)
    }

    /// UTC so the reset moment does not move when the user travels, and so two
    /// devices in different zones agree about which day it is.
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

/// Where synchronisation stands per game and API version, persisted.
///
/// The rule this exists to enforce: `updated_after` is only safe once a complete
/// pass has succeeded. Before that, a variant missing from a delta response is
/// indistinguishable from one that was never fetched.
struct JustTCGSyncLedger: Sendable {
    private let defaults: UserDefaults
    private let key = "justTCGSyncCheckpoints"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func checkpoint(game: CardGame, apiVersion: String) -> JustTCGSyncCheckpoint {
        all()[Self.identifier(game: game, apiVersion: apiVersion)]
            ?? JustTCGSyncCheckpoint(game: game.rawValue, apiVersion: apiVersion)
    }

    /// The moment to pass as `updated_after`, or nil when a full pass is still
    /// required.
    func deltaCutoff(game: CardGame, apiVersion: String) -> Date? {
        let checkpoint = self.checkpoint(game: game, apiVersion: apiVersion)
        guard checkpoint.supportsDeltaSync else { return nil }
        return checkpoint.lastCompleteSyncAt
    }

    func recordProviderClock(game: CardGame, apiVersion: String, updatedAt: Date?) {
        var checkpoint = self.checkpoint(game: game, apiVersion: apiVersion)
        checkpoint.providerLastUpdated = updatedAt
        write(checkpoint)
    }

    /// Only called when *every* batch in a pass succeeded. A partial pass must
    /// not advance the checkpoint, or the next delta would skip whatever the
    /// failed batch contained.
    func recordCompleteSync(game: CardGame, apiVersion: String, at date: Date = .now) {
        var checkpoint = self.checkpoint(game: game, apiVersion: apiVersion)
        checkpoint.lastCompleteSyncAt = date
        write(checkpoint)
    }

    private func all() -> [String: JustTCGSyncCheckpoint] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(
                [String: JustTCGSyncCheckpoint].self, from: data
              ) else {
            return [:]
        }
        return decoded
    }

    private func write(_ checkpoint: JustTCGSyncCheckpoint) {
        var checkpoints = all()
        checkpoints[Self.identifier(game: checkpoint.game, apiVersion: checkpoint.apiVersion)] = checkpoint
        guard let data = try? JSONEncoder().encode(checkpoints) else { return }
        defaults.set(data, forKey: key)
    }

    private static func identifier(game: CardGame, apiVersion: String) -> String {
        identifier(game: game.rawValue, apiVersion: apiVersion)
    }

    private static func identifier(game: String, apiVersion: String) -> String {
        "\(game)|\(apiVersion)"
    }
}
