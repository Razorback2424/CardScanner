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

    enum EstablishmentError: LocalizedError {
        case baselineWriteFailed(String)
        /// The collection has rows but the ledger is empty, on a device where
        /// CloudKit may still be delivering. Not a failure — a reason to wait.
        case awaitingInitialSync

        var errorDescription: String? {
            switch self {
            case let .baselineWriteFailed(detail):
                return "Portfolio baseline could not be recorded: \(detail)"
            case .awaitingInitialSync:
                return "Portfolio tracking is waiting for iCloud to finish delivering this collection."
            }
        }
    }

    /// When this device first saw a collection it could not yet explain.
    static let deferralKey = "portfolioEpochDeferredSince"

    /// How long a collection-without-a-ledger is treated as an unfinished
    /// import rather than as a genuine pre-ledger collection.
    ///
    /// The wait almost never runs to completion: the moment any inventory event
    /// arrives, the ordinary "ownership accounting already exists" path takes
    /// over. The bound exists for the case the events are never coming — an
    /// install that predates the ledger — where the baseline is correct and
    /// must not be withheld forever.
    static let initialSyncGrace: TimeInterval = 120

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
        // Injected rather than read inline so the deferral is testable without a
        // keychain. This is the same condition `makeContainer()` uses to decide
        // whether SwiftData gets a mirrored configuration.
        isCloudSyncing: Bool = AppleAccountCredentials.isSignedIn,
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
        let hasAnyEvent = try ledger.hasAnyEvent()
        guard !hasAnyEvent else {
            defaults.removeObject(forKey: deferralKey)
            defaults.set(date.timeIntervalSince1970, forKey: defaultsKey)
            return date
        }

        // An empty ledger is only evidence that no ownership accounting exists
        // *anywhere* on a device that syncs nothing. Where CloudKit is
        // mirroring, it also describes an import that has delivered
        // `CollectedCard` rows but not yet the `InventoryEvent` rows that
        // explain them — the two are separate record types and either can
        // arrive first. Baselining in that window writes an `initialBalance`
        // for a position whose real acquisition is still in flight, and the
        // deterministic baseline id cannot dedupe against it: it only matches
        // another baseline, never a genuine `acquire`. The collection would
        // then be counted twice.
        //
        // So a collection with no ledger at all is given a bounded chance to
        // finish arriving before it is treated as pre-ledger history.
        if isAwaitingInitialSync(
            context: context,
            defaults: defaults,
            at: date,
            isCloudSyncing: isCloudSyncing
        ) {
            throw EstablishmentError.awaitingInitialSync
        }

        // Pins the portfolio timezone at the same moment, so the zone and the
        // first day boundary are established by one act rather than two.
        _ = PortfolioCalendar.timeZone(defaults: defaults)

        do {
            // One baseline event per *position*, not per stored row.
            //
            // The baseline id is deterministic on `collectionKey` so two
            // devices racing the migration produce the same idempotency key
            // and dedupe. This entire read-and-stage sequence is inside the
            // transaction: an unreadable collection or ledger lookup must
            // abort rather than being interpreted as an empty collection or
            // an absent event.
            let cards = try context.fetch(FetchDescriptor<CollectedCard>())
            let projection = LogicalCollection.project(cards: cards, ledger: ledger)
            for position in projection.positions where position.quantity != 0 {
                let outcome = ledger.record(
                    position.representative,
                    kind: .initialBalance,
                    source: .catalog,
                    deltaQuantity: position.quantity,
                    operationID: baselineOperationID(collectionKey: position.collectionKey),
                    occurredAt: date,
                    acquiredAt: position.representative.dateAdded
                )
                switch outcome {
                case .appended:
                    break
                case .duplicate:
                    throw EstablishmentError.baselineWriteFailed(
                        "baseline event already exists for \(position.collectionKey)"
                    )
                case let .conflict(defect), let .unreadableStore(defect):
                    throw EstablishmentError.baselineWriteFailed(defect.detail)
                }
            }
            try save(context)
            defaults.removeObject(forKey: deferralKey)
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

    /// Whether an empty ledger beside a non-empty collection should still be
    /// read as an unfinished CloudKit import.
    ///
    /// Gated on being signed in because that is the same condition
    /// `TradingCardScannerApp.makeContainer()` uses to decide whether to hand
    /// SwiftData a mirrored configuration. A local-only device cannot be
    /// waiting on anything, and must not be delayed.
    @MainActor
    private static func isAwaitingInitialSync(
        context: ModelContext,
        defaults: UserDefaults,
        at date: Date,
        isCloudSyncing: Bool
    ) -> Bool {
        guard isCloudSyncing else {
            defaults.removeObject(forKey: deferralKey)
            return false
        }
        var descriptor = FetchDescriptor<CollectedCard>()
        descriptor.fetchLimit = 1
        // No collection means nothing to baseline and nothing to protect. The
        // epoch opens now, exactly as it always did on a fresh install.
        guard let hasAnyCard = try? context.fetch(descriptor).isEmpty == false,
              hasAnyCard else {
            defaults.removeObject(forKey: deferralKey)
            return false
        }

        let started = defaults.double(forKey: deferralKey)
        guard started > 0 else {
            defaults.set(date.timeIntervalSince1970, forKey: deferralKey)
            return true
        }
        // A clock that moved backwards must not extend the wait indefinitely.
        let elapsed = date.timeIntervalSince(Date(timeIntervalSince1970: started))
        guard elapsed >= 0, elapsed < initialSyncGrace else {
            defaults.removeObject(forKey: deferralKey)
            return false
        }
        return true
    }

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
