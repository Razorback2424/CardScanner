import Foundation

/// The last authoritative headline Portfolio published for one store.
///
/// Launch shows this immediately instead of a blank "Calculating portfolio…"
/// screen while the replay rebuilds today's value. It is presentation only:
/// it never seeds the ledger, history, closes or live price deltas, and the
/// engine marks the summary built from it as provisional until a replay of the
/// current store replaces it.
struct PortfolioLaunchSnapshot: Codable, Equatable, Sendable {
    var storeID: UUID
    var valueTenThousandths: Int64
    var copyCount: Int?
    var unpricedCount: Int
    var otherCurrencyCount: Int
    var savedAt: Date

    /// A provisional summary: never authoritative, so nothing that depends on
    /// replayed history renders or publishes from it.
    var provisionalSummary: PortfolioSummary {
        var summary = PortfolioSummary(
            currentValue: Money(tenThousandths: valueTenThousandths),
            copyCount: copyCount,
            unpricedCount: unpricedCount,
            otherCurrencyCount: otherCurrencyCount
        )
        summary.isAuthoritative = false
        summary.isProvisional = true
        return summary
    }
}

/// Persists one launch snapshot, scoped to the store that produced it so a
/// different storage session (iCloud vs. on-device, another account, a reset
/// collection) never opens on someone else's number.
@MainActor
final class PortfolioLaunchSnapshotStore {
    static let shared = PortfolioLaunchSnapshotStore(defaults: .standard)

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults, key: String = "portfolioLaunchSnapshot.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load(storeID: UUID?) -> PortfolioLaunchSnapshot? {
        guard let storeID,
              let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(PortfolioLaunchSnapshot.self, from: data),
              snapshot.storeID == storeID else { return nil }
        return snapshot
    }

    /// Records an authoritative, defect-free summary. An empty collection
    /// clears the snapshot: its own empty state is fast and must stay honest.
    func record(_ summary: PortfolioSummary, storeID: UUID?, now: Date = .now) {
        guard let storeID else { return }
        guard summary.isAuthoritative, !summary.isProvisional, summary.defects.isEmpty,
              summary.currentValue.isValid else { return }
        guard let copies = summary.copyCount, copies > 0 else {
            clear()
            return
        }
        let snapshot = PortfolioLaunchSnapshot(
            storeID: storeID,
            valueTenThousandths: summary.currentValue.tenThousandths,
            copyCount: copies,
            unpricedCount: summary.unpricedCount,
            otherCurrencyCount: summary.otherCurrencyCount,
            savedAt: now
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
