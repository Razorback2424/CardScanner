import Foundation
import CryptoKit
import SwiftData

/// The moment portfolio tracking begins, and the synthetic baseline that opens
/// the ledger.
///
/// Existing holdings are snapshotted into `initialBalance` events at a single
/// instant. They are deliberately *not* scattered backwards across each card's
/// `dateAdded`: there are no price observations for those dates, so every close
/// derived from them would be a number the app cannot defend. `dateAdded`
/// survives as metadata, which is what it always was.
///
/// The day the epoch is created has no yesterday. The header says
/// "Portfolio tracking started today" and shows no reconciliation — the first
/// legitimate close forms at the first midnight boundary. Without that, the
/// entire baseline surfaces on day one as either a giant flow or a giant
/// residual, and the first thing the feature ever shows the user is a lie.
enum PortfolioEpoch {
    static let defaultsKey = "portfolioEpochStartedAt"

    /// Namespace for the deterministic baseline ids. Two devices that both
    /// establish an epoch before sync catches up must produce the *same*
    /// idempotency key per position, so the ledger dedupes them instead of
    /// doubling the collection.
    private static let namespace = "trading-card-scanner.portfolio-epoch"

    /// When tracking started, preferring the ledger's own evidence over local
    /// state — the baseline events sync, the `UserDefaults` value does not.
    @MainActor
    static func startedAt(
        context: ModelContext,
        defaults: UserDefaults = .standard
    ) -> Date? {
        if let earliest = earliestBaseline(in: context) { return earliest }
        let stored = defaults.double(forKey: defaultsKey)
        return stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    /// Whether `date` falls on the very first day of tracking.
    nonisolated static func isMigrationDay(
        _ date: Date,
        epoch: Date,
        timeZone: TimeZone
    ) -> Bool {
        PortfolioCalendar.day(containing: date, in: timeZone)
            == PortfolioCalendar.day(containing: epoch, in: timeZone)
    }

    /// Opens the ledger if it has not been opened. Safe to call on every
    /// launch: it writes nothing once a baseline exists, and its writes are
    /// idempotent per position if two devices race.
    @MainActor
    @discardableResult
    static func establishIfNeeded(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        at date: Date = .now
    ) -> Date {
        let ledger = InventoryLedger(context: context)

        if let existing = startedAt(context: context, defaults: defaults) {
            defaults.set(existing.timeIntervalSince1970, forKey: defaultsKey)
            return existing
        }

        // Any ledger activity at all means another device already opened this
        // collection's books. Adding a baseline now would double every position
        // it has since recorded.
        guard !ledger.hasAnyEvent() else {
            defaults.set(date.timeIntervalSince1970, forKey: defaultsKey)
            return date
        }

        // Pins the portfolio timezone at the same moment, so the zone and the
        // first day boundary are established by one act rather than two.
        _ = PortfolioCalendar.timeZone(defaults: defaults)

        let cards = (try? context.fetch(FetchDescriptor<CollectedCard>())) ?? []
        for card in cards where card.quantity != 0 {
            ledger.record(
                card,
                kind: .initialBalance,
                source: .catalog,
                deltaQuantity: card.quantity,
                operationID: baselineOperationID(collectionKey: card.collectionKey),
                occurredAt: date,
                acquiredAt: card.dateAdded
            )
        }

        try? context.save()
        defaults.set(date.timeIntervalSince1970, forKey: defaultsKey)
        return date
    }

    // MARK: -

    @MainActor
    private static func earliestBaseline(in context: ModelContext) -> Date? {
        let raw = InventoryEventKind.initialBalance.rawValue
        var descriptor = FetchDescriptor<InventoryEvent>(
            predicate: #Predicate { $0.kindRaw == raw },
            sortBy: [SortDescriptor(\.occurredAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor).first)?.occurredAt
    }

    /// A version-3 UUID over the position's collection key, so the id is a
    /// function of *what* is being baselined rather than of which device got
    /// there first.
    static func baselineOperationID(collectionKey: String) -> UUID {
        var bytes = Array(Insecure.MD5.hash(data: Data((namespace + ":" + collectionKey).utf8)))
        bytes[6] = (bytes[6] & 0x0F) | 0x30 // version 3
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
