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

    /// When this device began accumulating portfolio knowledge.
    ///
    /// Ownership events sync; price observations and closes do not. Therefore
    /// a remote baseline is evidence of when ownership accounting began, not
    /// evidence that this device knew any prices on that date.
    /// Takes a `context` it no longer reads: local knowledge time lives in
    /// `UserDefaults`, because a synced baseline is evidence of when ownership
    /// accounting began, not that this device knew any prices then.
    nonisolated static func startedAt(
        context: ModelContext? = nil,
        defaults: UserDefaults = .standard
    ) -> Date? {
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
        at date: Date = .now,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Date {
        let ledger = InventoryLedger(context: context)

        if let existing = startedAt(context: context, defaults: defaults) {
            defaults.set(existing.timeIntervalSince1970, forKey: defaultsKey)
            return existing
        }

        // Any ledger activity means ownership accounting already exists,
        // usually because CloudKit delivered it from another device. This
        // device starts local history today and does not add another baseline.
        guard !ledger.hasAnyEvent() else {
            defaults.set(date.timeIntervalSince1970, forKey: defaultsKey)
            return date
        }

        // Pins the portfolio timezone at the same moment, so the zone and the
        // first day boundary are established by one act rather than two.
        _ = PortfolioCalendar.timeZone(defaults: defaults)

        // One baseline event per *position*, not per stored row.
        //
        // The baseline id is deterministic on `collectionKey` so two devices
        // racing the migration produce the same key and dedupe. That is
        // precisely why iterating physical rows was wrong: two rows claiming
        // one key would either collapse into a single event — opening the
        // books below what is owned — or collide as an idempotency conflict,
        // and neither outcome starts the ledger at the right quantity.
        let cards = (try? context.fetch(FetchDescriptor<CollectedCard>())) ?? []
        let projection = LogicalCollection.project(cards: cards, ledger: ledger)
        for position in projection.positions where position.quantity != 0 {
            ledger.record(
                position.representative,
                kind: .initialBalance,
                source: .catalog,
                deltaQuantity: position.quantity,
                operationID: baselineOperationID(collectionKey: position.collectionKey),
                occurredAt: date,
                acquiredAt: position.representative.dateAdded
            )
        }

        do {
            try save(context)
        } catch {
            // The epoch flag is the public claim that the books are open. If
            // the baseline transaction did not commit, roll its inserted rows
            // back and leave that claim unset so the next launch retries.
            context.rollback()
            throw error
        }
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

    /// Synced ownership epoch, for diagnostics only. It must not be used as the
    /// local close/observation epoch.
    @MainActor
    static func ownershipStartedAt(context: ModelContext) -> Date? {
        earliestBaseline(in: context)
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
