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
    /// Reads `UserDefaults`, not the store: a synced baseline is evidence of
    /// when ownership accounting began, not that this device knew any prices
    /// then. It carried a `ModelContext` it never read until that was removed.
    nonisolated static func startedAt(
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
        // keychain. Production callers must pass the storage mode selected by
        // `TradingCardScannerApp.makeContainer()`; account credentials alone
        // do not prove that this launch is using a mirrored container.
        isCloudSyncing: Bool,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Date {
        let ledger = InventoryLedger(context: context)

        // Pinned here, before any early return, because *every* path below can
        // open the books: a device that inherits a synced ledger sets the epoch
        // without writing a baseline, and used to leave the zone unpinned. Each
        // reader then falls back to `TimeZone.current`, so day boundaries would
        // follow the person as they travelled and silently recut closes that had
        // already been published. This is also self-healing for a device already
        // in that state: the epoch owner is the only thing that pins the zone,
        // and it does so on the first launch that reaches this method.
        _ = PortfolioCalendar.timeZone(defaults: defaults)

        if let existing = startedAt(defaults: defaults) {
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
            let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
            var activityQuantities: [String: Int] = [:]
            for activity in activities {
                let (quantity, overflow) = activityQuantities[activity.collectionKey, default: 0]
                    .addingReportingOverflow(activity.signedQuantity)
                guard !overflow else {
                    throw EstablishmentError.baselineWriteFailed(
                        "activity quantity overflow for \(activity.collectionKey)"
                    )
                }
                activityQuantities[activity.collectionKey] = quantity
            }
            var activityRepresentatives: [String: CollectionActivity] = [:]
            var activitiesByKey: [String: [CollectionActivity]] = [:]
            for activity in activities {
                activitiesByKey[activity.collectionKey, default: []].append(activity)
                if let existing = activityRepresentatives[activity.collectionKey],
                   existing.occurredAt >= activity.occurredAt {
                    continue
                }
                activityRepresentatives[activity.collectionKey] = activity
            }
            // Resolve every candidate price key from one in-memory evidence
            // index. The ledger overload performs two SwiftData fetches per
            // candidate key, which is acceptable for one event but turns epoch
            // establishment into thousands of main-actor fetches for a large
            // collection.
            let observations = try context.fetch(FetchDescriptor<PriceObservation>())
            let records = try context.fetch(FetchDescriptor<PriceRecord>())
            let valuations = PortfolioReplaySnapshotBuilder.valuationIndex(
                observations: observations,
                records: records
            )
            let projection = LogicalCollection.project(cards: cards) {
                valuations.priceStorageKey(for: $0)
            }
            let positionKeys = Set(
                projection.positions
                    .filter { $0.quantity != 0 }
                    .map(\.collectionKey)
            )
            for position in projection.positions where position.quantity != 0 {
                let (activityDelta, activityDeltaOverflow) = position.quantity
                    .subtractingReportingOverflow(activityQuantities[position.collectionKey, default: 0])
                guard !activityDeltaOverflow else {
                    throw EstablishmentError.baselineWriteFailed(
                        "activity quantity overflow for \(position.collectionKey)"
                    )
                }
                let operationID = baselineOperationID(collectionKey: position.collectionKey)
                let outcome = ledger.record(
                    collectionKey: position.collectionKey,
                    priceStorageKey: position.priceStorageKey,
                    valuation: valuations.valuation(for: position.priceStorageKey),
                    kind: .initialBalance,
                    source: .catalog,
                    deltaQuantity: position.quantity,
                    operationID: operationID,
                    occurredAt: date,
                    acquiredAt: position.representative.dateAdded
                )
                switch outcome {
                case .appended:
                    // Startup backfill may already have written an `.added`
                    // activity for this pre-ledger holding. Add only the
                    // difference needed to make the activity projection agree
                    // with the baseline; otherwise these writers count the
                    // same collection twice.
                    if activityDelta != 0 {
                        guard activityDelta != Int.min else {
                            throw EstablishmentError.baselineWriteFailed(
                                "activity quantity magnitude overflow for \(position.collectionKey)"
                            )
                        }
                        context.insert(
                            CollectionActivity(
                                card: position.representative,
                                source: .catalog,
                                quantity: abs(activityDelta),
                                occurredAt: date,
                                kind: .quantityAdjusted,
                                deltaQuantity: activityDelta,
                                ledgerOperationIDs: [operationID]
                            )
                        )
                    }
                case .duplicate:
                    throw EstablishmentError.baselineWriteFailed(
                        "baseline event already exists for \(position.collectionKey)"
                    )
                case let .conflict(defect), let .unreadableStore(defect):
                    throw EstablishmentError.baselineWriteFailed(defect.detail)
                }
            }

            // Before the ledger existed, removing a card deleted its row but
            // left its `.added` activity behind. Reconcile those activity-only
            // identities to zero so they cannot keep the portfolio permanently
            // non-authoritative. There is no inventory event to link because
            // the card no longer exists.
            for collectionKey in activityQuantities.keys.sorted()
                where !positionKeys.contains(collectionKey) {
                for activity in activitiesByKey[collectionKey, default: []]
                    where activity.kind.hasQuantityClaim {
                    activity.resolvedQuantity = activity.claimedQuantity
                }
                let activityQuantity = activityQuantities[collectionKey, default: 0]
                guard activityQuantity != 0 else { continue }
                let (deltaQuantity, overflow) = 0.subtractingReportingOverflow(activityQuantity)
                guard !overflow else {
                    throw EstablishmentError.baselineWriteFailed(
                        "activity quantity overflow for \(collectionKey)"
                    )
                }
                guard let representative = activityRepresentatives[collectionKey] else {
                    throw EstablishmentError.baselineWriteFailed(
                        "activity is missing for \(collectionKey)"
                    )
                }
                context.insert(
                    CollectionActivity(
                        reconciling: representative,
                        deltaQuantity: deltaQuantity,
                        occurredAt: date
                    )
                )
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
        DeterministicUUID.make(
            namespace: namespace + ":",
            material: collectionKey
        )
    }
}
