import Foundation
import SwiftData

/// Versioned rules for deciding which stored price evidence can participate in
/// valuation. The stamp is local because observations are local; it lets a
/// release that changes a read rule reconcile the value transition once rather
/// than silently changing the replay's basis underneath the user.
enum PriceReadabilityRules {
    /// Version 1 is the first stamped release. It covers the treatment-aware
    /// price keys and the legacy aliases that became readable without a new
    /// provider response.
    static let currentVersion = 1
    static let defaultsKey = "priceReadabilityRulesVersion"

    static func lastAppliedVersion(defaults: UserDefaults) -> Int {
        (defaults.object(forKey: defaultsKey) as? NSNumber)?.intValue ?? 0
    }
}

/// The classification rules for the price observation log, as pure functions
/// over value types.
///
/// Deliberately separate from the store so every rule here is testable without
/// a container, and so the *decision* stays at ingestion. Classification needs
/// provider semantics — whether the provider publishes its own clock at all —
/// and that context is gone by the time the portfolio engine walks a timeline.
enum PriceObservationRules {
    /// A provider answer, normalized into the terms the log reasons in.
    struct Candidate: Equatable, Sendable {
        var value: PriceObservationValue
        var source: PriceSource
        /// The provider's "current through" clock, or `nil` where it publishes
        /// none.
        var sourceUpdatedAt: Date?
        var receivedAt: Date

        /// Whether `effectiveAt` will be a real provider claim rather than a
        /// stand-in for the fetch time.
        var isSourceStamped: Bool {
            source.publishesSourceTimestamp && sourceUpdatedAt != nil
        }

        /// What gets stored as `effectiveAt`. Falls back to knowledge time for
        /// providers with no clock, with `isSourceStamped` recording which of
        /// the two it is so nothing downstream mistakes one for the other.
        var effectiveAt: Date { sourceUpdatedAt ?? receivedAt }
    }

    /// The newest existing observation for the same instrument.
    struct Previous: Equatable, Sendable {
        var value: PriceObservationValue
        var effectiveAt: Date
        var receivedAt: Date
        var isSourceStamped: Bool
    }

    enum Decision: Equatable, Sendable {
        /// Append a row of this kind.
        case append(PriceObservationKind)
        /// Nothing value-setting happened. The prior value stands, and the
        /// check is still recorded as coverage.
        case unchanged
        /// A non-finite or unrepresentable provider amount. Not a successful
        /// check and never persisted as value evidence.
        case rejectedInvalidQuote
        /// A response that was already received before an explicit
        /// invalidation. It is not allowed to become newer evidence merely
        /// because a delayed caller wrote it after the invalidation.
        case ignoredAfterInvalidation
    }

    /// Whether a provider answer is value-setting, and if so what it means.
    nonisolated static func decide(candidate: Candidate, previous: Previous?) -> Decision {
        if let previous,
           previous.value.amount == nil,
           previous.receivedAt >= candidate.receivedAt {
            return .ignoredAfterInvalidation
        }

        // Identical value *and* identical provenance: the app has learned
        // nothing new. Appending here would fill the log with thousands of
        // rows a day that say "still $42, still from the same object".
        if let previous, previous.value == candidate.value {
            return .unchanged
        }

        // A provider or mapping transition changes what the app is pricing.
        // Even if the new object is worth more, that delta is a pricing
        // adjustment, not appreciation.
        if let previous,
           previous.value.sourceRaw != candidate.value.sourceRaw
            || previous.value.sourceVariantID != candidate.value.sourceVariantID
            || previous.value.marketVariantID != candidate.value.marketVariantID {
            return .append(.sourceTransition)
        }

        // A provider that publishes its own clock and hands back a clock at or
        // before the one already recorded is republishing a period it has
        // already reported. That is a restatement of history, not the market
        // moving, and it must not read as performance. Only meaningful when
        // the previous row was itself source-stamped — comparing a provider
        // clock against a fetch time compares two different kinds of moment.
        if let previous,
           previous.isSourceStamped,
           candidate.isSourceStamped,
           candidate.effectiveAt <= previous.effectiveAt {
            return .append(.sourceRestatement)
        }

        // Everything else — including every value from a provider with no
        // clock, such as Scryfall — is a market update unless separate
        // evidence says otherwise.
        return .append(.marketUpdate)
    }
}

/// Reads and appends the price observation log, and records the separate
/// evidence that a check actually succeeded.
///
/// Three provider outcomes, three different sets of writes:
///
/// | Outcome                     | Observation | `PriceCheckDay` | `lastSuccessfulCheckAt` |
/// |-----------------------------|-------------|-----------------|-------------------------|
/// | priced, value changed       | append      | write           | set                     |
/// | priced, value unchanged     | none        | write           | set                     |
/// | unavailable for this variant| none        | write           | set                     |
/// | request failed              | none        | none            | untouched               |
///
/// "Unavailable" writing no observation is the load-bearing part. It is a real,
/// current answer — the app asked and the provider has nothing for this exact
/// physical variant — so it counts as coverage, but it must not remove a price
/// the app legitimately holds. Only an `explicitInvalidation` can do that.
struct PriceObservationLog {
    let context: ModelContext
    let index: PriceRefreshDataIndex?

    init(context: ModelContext, index: PriceRefreshDataIndex? = nil) {
        self.context = context
        self.index = index
    }

    /// Observation rows are local-only, so two SwiftData contexts in the same
    /// process can otherwise both observe the same absence and seed it. The
    /// portfolio computation actor is the production owner, while this narrow
    /// process-wide lock keeps a background computation and a foreground retry
    /// from racing during the handoff. The second context fetches again after
    /// the first context saves, so the absence check remains idempotent without
    /// adding a synced schema watermark to `PriceRecord`.
    private static let backfillLock = NSLock()
    /// Reading the log must not be able to establish the portfolio epoch as a
    /// side effect. The epoch owner pins the zone explicitly; this fallback is
    /// only for callers that operate before an epoch exists.
    var timeZone: TimeZone = PortfolioCalendar.pinnedTimeZone() ?? .current

    // MARK: - Reading

    func newestObservation(instrumentKey: String) -> PriceObservation? {
        if let index, index.isUsable {
            return index.newestObservation(forInstrumentKey: instrumentKey)
        }
        var descriptor = FetchDescriptor<PriceObservation>(
            predicate: #Predicate { $0.instrumentKey == instrumentKey },
            sortBy: [
                SortDescriptor(\.receivedAt, order: .reverse),
                SortDescriptor(\.id, order: .reverse)
            ]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func observations(instrumentKey: String) -> [PriceObservation] {
        let descriptor = FetchDescriptor<PriceObservation>(
            predicate: #Predicate { $0.instrumentKey == instrumentKey },
            sortBy: [
                SortDescriptor(\.receivedAt, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func checkDay(instrumentKey: String, day: Date) -> PriceCheckDay? {
        if let index, index.isUsable, index.canReadCheckDay(day) {
            return index.checkDay(instrumentKey: instrumentKey, day: day)
        }
        var descriptor = FetchDescriptor<PriceCheckDay>(
            predicate: #Predicate { $0.instrumentKey == instrumentKey && $0.portfolioDay == day }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Writing

    /// Records one successful provider answer: appends an observation if the
    /// answer is value-setting, and always records the coverage evidence.
    @discardableResult
    /// `recordsCoverage` is false for the one value-setting path that is not a
    /// provider check: a CSV import. The value is real and belongs in the log,
    /// but "1,276 of 1,284 repriced today" means a provider answered, and a
    /// spreadsheet did not.
    func ingest(
        _ lookup: PriceLookup,
        instrumentKey: String,
        marketVariantID: String?,
        recordsCoverage: Bool = true,
        at date: Date
    ) -> PriceObservationRules.Decision {
        let decision: PriceObservationRules.Decision
        let source: PriceSource?

        switch lookup {
        case let .price(price):
            guard let amount = Money(rounding: price.unitMarketPriceUSD) else {
                return .rejectedInvalidQuote
            }
            let candidate = PriceObservationRules.Candidate(
                value: PriceObservationValue(
                    amount: amount,
                    currencyCode: price.currencyCode,
                    sourceRaw: price.source.rawValue,
                    sourceVariantID: price.sourceVariantID,
                    marketVariantID: marketVariantID
                ),
                source: price.source,
                sourceUpdatedAt: price.sourceUpdatedAt,
                receivedAt: price.fetchedAt
            )
            decision = PriceObservationRules.decide(
                candidate: candidate,
                previous: previous(forKey: instrumentKey)
            )
            if case let .append(kind) = decision {
                append(candidate: candidate, kind: kind, instrumentKey: instrumentKey)
            }
            source = price.source

        case let .unavailable(unavailableSource):
            // No row. The prior value carries forward and goes stale, which is
            // exactly what `PriceRecord.applyUnavailable` already does on
            // purpose. Writing a `nil` observation here would make `nil` mean
            // two different things in the same column.
            decision = .unchanged
            source = unavailableSource
        }

        if recordsCoverage {
            recordSuccessfulCheck(instrumentKey: instrumentKey, source: source, at: date)
        }
        return decision
    }

    /// Withdraws a value the app should never have held — a price discovered to
    /// have been attached to the wrong market variant. The only thing that can
    /// remove a price, and the only place `amount == nil` is written.
    @discardableResult
    func recordInvalidation(
        instrumentKey: String,
        source: PriceSource,
        at date: Date = .now
    ) -> PriceObservation? {
        let record = PriceStore(context: context, index: index).record(forKey: instrumentKey)
        let previous = newestObservation(instrumentKey: instrumentKey)

        // Invalidation is idempotent. This also repairs a record created by an
        // older build that already has the invalidation row but did not mirror
        // the withdrawn state onto PriceRecord.
        if let previous, previous.kind == .explicitInvalidation {
            record?.invalidate(at: previous.receivedAt)
            return previous
        }

        // Backfilled or legacy records may not have an observation yet. They
        // are still valid invalidation targets; requiring a prior log row would
        // leave the collection/detail readers able to show the value forever.
        if let previous, previous.amount == nil { return nil }
        guard previous?.amount != nil
            || record?.effectiveUnitMarketPriceUSD != nil else {
            return nil
        }

        let observation = PriceObservation(
            instrumentKey: instrumentKey,
            kind: .explicitInvalidation,
            amount: nil,
            currencyCode: previous?.currencyCode ?? record?.currencyCode ?? "USD",
            source: source,
            sourceVariantID: previous?.sourceVariantID ?? record?.sourceVariantID,
            marketVariantID: previous?.marketVariantID ?? record?.marketVariantID,
            effectiveAt: date,
            receivedAt: date,
            isSourceStamped: false
        )
        if let record, !record.invalidate(at: date) { return nil }
        context.insert(observation)
        index?.insert(observation)
        return observation
    }

    /// One row per instrument per day, upserted. The timestamp advances so the
    /// day records the *latest* success, but the row's existence is the fact
    /// coverage actually reads.
    func recordSuccessfulCheck(
        instrumentKey: String,
        source: PriceSource?,
        at date: Date
    ) {
        let day = PortfolioCalendar.day(containing: date, in: timeZone)
        if let existing = checkDay(instrumentKey: instrumentKey, day: day) {
            if date > existing.lastSuccessfulCheckAt {
                existing.lastSuccessfulCheckAt = date
                existing.sourceRaw = source?.rawValue ?? existing.sourceRaw
            }
            index?.insert(existing)
            return
        }
        let checkDay = PriceCheckDay(
            instrumentKey: instrumentKey,
            portfolioDay: day,
            lastSuccessfulCheckAt: date,
            source: source
        )
        context.insert(checkDay)
        index?.insert(checkDay)
    }

    // MARK: - Synced-record reconciliation

    /// Reconciles the current synced price-record state into this device's
    /// local knowledge history.
    ///
    /// `PriceRecord` overwrites in place, so every valuation this app computed
    /// before the log existed is already gone. What survives is the *current*
    /// value and when it was fetched, and that is enough to open the log
    /// honestly: "as of this moment, this is what the app believed".
    ///
    /// A record can arrive from another device after this device has already
    /// observed an older value. Comparing only for an absent observation — the
    /// old backfill rule — leaves the portfolio walk on that older value. A
    /// materially different current record therefore becomes a new local
    /// observation, with `localKnowledgeTime` as `receivedAt`. The remote
    /// device's `fetchedAt` is never copied into this device's history.
    ///
    /// Explicitly invalidated records are reconciled too, including when this
    /// device has no prior local observation. An invalidation is authoritative
    /// state, not a missing-price fallback.
    ///
    /// A process-local mutex serializes the app's main and computation
    /// contexts, but it cannot deduplicate two devices' local-only observations;
    /// that cross-device limitation is intentional and remains value-neutral.
    @discardableResult
    func backfillFromRecords(
        receivedAt localKnowledgeTime: Date = .now,
        existingObservations: [PriceObservation]? = nil,
        defaults: UserDefaults = .standard
    ) -> Int {
        synchronizeRecords(
            receivedAt: localKnowledgeTime,
            existingObservations: existingObservations,
            defaults: defaults
        ).written
    }

    /// The computation actor already materialises the observation log for its
    /// replay. Return that same in-memory set with any newly seeded rows so the
    /// builder does not issue a second full-table fetch.
    func backfillFromRecordsAndReturnObservations(
        receivedAt localKnowledgeTime: Date = .now,
        existingObservations: [PriceObservation]? = nil,
        defaults: UserDefaults = .standard
    ) -> [PriceObservation] {
        reconcileSyncedRecordsAndReturnObservations(
            learnedAt: localKnowledgeTime,
            existingObservations: existingObservations,
            defaults: defaults
        )
    }

    /// Reconciles changed or invalidated synced records into the local
    /// observation history and returns the materialised rows for replay.
    func reconcileSyncedRecordsAndReturnObservations(
        learnedAt localKnowledgeTime: Date = .now,
        existingObservations: [PriceObservation]? = nil,
        defaults: UserDefaults = .standard
    ) -> [PriceObservation] {
        synchronizeRecords(
            receivedAt: localKnowledgeTime,
            existingObservations: existingObservations,
            defaults: defaults
        ).observations
    }

    #if DEBUG
    /// Test/support seam for a read failure. Production callers use the
    /// context-backed overloads above; this keeps the failure branch
    /// reproducible without manufacturing a corrupt SwiftData store.
    @discardableResult
    func backfillFromRecordsForTesting(
        receivedAt localKnowledgeTime: Date = .now,
        fetchExistingObservations: @escaping () throws -> [PriceObservation],
        defaults: UserDefaults = .standard
    ) -> Int {
        synchronizeRecords(
            receivedAt: localKnowledgeTime,
            existingObservations: nil,
            fetchExistingObservations: fetchExistingObservations,
            defaults: defaults
        ).written
    }
    #endif

    private func synchronizeRecords(
        receivedAt localKnowledgeTime: Date,
        existingObservations: [PriceObservation]?,
        fetchExistingObservations: (() throws -> [PriceObservation])? = nil,
        defaults: UserDefaults = .standard
    ) -> (written: Int, observations: [PriceObservation]) {
        Self.backfillLock.lock()
        defer { Self.backfillLock.unlock() }

        let allRecords = PriceStore(context: context, index: index).allRecords()
        var recordsByKey: [String: PriceRecord] = [:]
        for record in allRecords {
            if let existing = recordsByKey[record.key],
               !PriceStore.isPreferred(record, over: existing) {
                continue
            }
            recordsByKey[record.key] = record
        }
        let records = recordsByKey.values.sorted { $0.key < $1.key }
        var observations: [PriceObservation]
        if let existingObservations {
            observations = existingObservations
        } else {
            do {
                observations = try fetchExistingObservations?()
                    ?? context.fetch(FetchDescriptor<PriceObservation>())
            } catch {
                // An unreadable observation log is not an empty log. Seeding
                // from that unknown baseline would duplicate every priced
                // record while the computation is already reporting the store
                // defect.
                return (0, [])
            }
        }
        var newestByInstrument: [String: PriceObservation] = [:]
        for observation in observations {
            if let existing = newestByInstrument[observation.instrumentKey] {
                let existingIsNewer =
                    existing.receivedAt > observation.receivedAt
                    || (existing.receivedAt == observation.receivedAt
                        && existing.id.uuidString >= observation.id.uuidString)
                if existingIsNewer { continue }
            }
            newestByInstrument[observation.instrumentKey] = observation
        }
        var written = 0

        let previousRulesVersion = PriceReadabilityRules.lastAppliedVersion(defaults: defaults)
        let readabilityTransitionKeys: Set<String>
        if previousRulesVersion < PriceReadabilityRules.currentVersion {
            readabilityTransitionKeys = readRuleTransitionKeys(recordsByKey: recordsByKey)
        } else {
            readabilityTransitionKeys = []
        }

        // A read-rule migration is an app-knowledge transition, not a market
        // update. Force the one new usable value through the existing
        // `.sourceTransition` bucket so the replay can explain it. If the
        // newest observation already carries the same usable value, the
        // current replay has no value delta to reconcile and no duplicate row
        // is warranted.
        for key in readabilityTransitionKeys.sorted() {
            guard let record = recordsByKey[key],
                  let candidate = candidate(for: record, receivedAt: localKnowledgeTime)
            else { continue }
            let previous = newestByInstrument[key]
            if let previous, previous.value == candidate.value {
                continue
            }
            let observation = PriceObservation(
                instrumentKey: key,
                kind: .sourceTransition,
                amount: candidate.value.amount,
                currencyCode: candidate.value.currencyCode,
                source: candidate.source,
                sourceVariantID: candidate.value.sourceVariantID,
                marketVariantID: candidate.value.marketVariantID,
                effectiveAt: candidate.effectiveAt,
                receivedAt: candidate.receivedAt,
                isSourceStamped: candidate.isSourceStamped
            )
            context.insert(observation)
            observations.append(observation)
            newestByInstrument[key] = observation
            written += 1
        }

        for record in records {
            let previous = newestByInstrument[record.key]

            if record.isInvalidated {
                guard previous?.kind != .explicitInvalidation else { continue }
                if let previous, isOutOfOrder(record: record, comparedTo: previous) {
                    continue
                }
                let observation = PriceObservation(
                    instrumentKey: record.key,
                    kind: .explicitInvalidation,
                    amount: nil,
                    currencyCode: record.currencyCode,
                    source: record.source ?? previous?.source ?? .justTCG,
                    sourceVariantID: record.sourceVariantID ?? previous?.sourceVariantID,
                    marketVariantID: record.marketVariantID ?? previous?.marketVariantID,
                    effectiveAt: localKnowledgeTime,
                    receivedAt: localKnowledgeTime,
                    isSourceStamped: false
                )
                context.insert(observation)
                observations.append(observation)
                newestByInstrument[record.key] = observation
                written += 1
                continue
            }

            guard let amount = record.effectiveUnitMarketPriceUSD,
                  record.currencyCode == "USD",
                  let source = record.source,
                  let money = Money(rounding: amount) else { continue }
            if let previous, isOutOfOrder(record: record, comparedTo: previous) {
                continue
            }

            let candidate = PriceObservationRules.Candidate(
                value: PriceObservationValue(
                    amount: money,
                    currencyCode: record.currencyCode,
                    sourceRaw: source.rawValue,
                    sourceVariantID: record.sourceVariantID,
                    marketVariantID: record.marketVariantID
                ),
                source: source,
                sourceUpdatedAt: record.sourceUpdatedAt,
                // A synced PriceRecord's fetchedAt belongs to the device that
                // originally fetched it. This device learned the inherited
                // value now and must not fabricate history by copying that
                // remote timestamp into local knowledge time.
                receivedAt: localKnowledgeTime
            )
            guard case let .append(kind) = PriceObservationRules.decide(
                candidate: candidate,
                previous: previous.map {
                    PriceObservationRules.Previous(
                        value: $0.value,
                        effectiveAt: $0.effectiveAt,
                        receivedAt: $0.receivedAt,
                        isSourceStamped: $0.isSourceStamped
                    )
                }
            ) else { continue }

            let observation = PriceObservation(
                instrumentKey: record.key,
                kind: kind,
                amount: candidate.value.amount,
                currencyCode: candidate.value.currencyCode,
                source: candidate.source,
                sourceVariantID: candidate.value.sourceVariantID,
                marketVariantID: candidate.value.marketVariantID,
                effectiveAt: candidate.effectiveAt,
                receivedAt: candidate.receivedAt,
                isSourceStamped: candidate.isSourceStamped
            )
            context.insert(observation)
            observations.append(observation)
            newestByInstrument[record.key] = observation
            written += 1
        }

        if written > 0 {
            do {
                try context.save()
            } catch {
                // Reconciliation is best effort, but unsaved in-memory
                // observations must not be returned as durable evidence or
                // remain staged for a later unrelated save. The computation
                // actor will retry on its next pass.
                context.rollback()
                return (0, [])
            }
        }
        if previousRulesVersion < PriceReadabilityRules.currentVersion {
            defaults.set(PriceReadabilityRules.currentVersion, forKey: PriceReadabilityRules.defaultsKey)
        }
        return (written, observations)
    }

    /// Identifies values whose readability changed in the stamped release.
    /// Treatment-qualified records are exact provider identities. The alias
    /// pass covers the separate `priceLookupKeys` change: a treatment row may
    /// now read a real value already stored under its treatment-free identity.
    private func readRuleTransitionKeys(recordsByKey: [String: PriceRecord]) -> Set<String> {
        var keys = Set(
            recordsByKey.keys.filter { key in
                !MagicTreatmentKeyCodec.priceTreatmentIDs(from: key).isEmpty
            }
        )

        guard let cards = try? context.fetch(FetchDescriptor<CollectedCard>()) else {
            return keys
        }
        for card in cards where card.priceLookupKeys.count > 1 {
            let canonicalHasValue = card.priceLookupKeys.first
                .flatMap { recordsByKey[$0] }
                .flatMap { usableAmount(for: $0) } != nil
            guard !canonicalHasValue else { continue }
            for key in card.legacyPriceKeys {
                if let record = recordsByKey[key], usableAmount(for: record) != nil {
                    keys.insert(key)
                }
            }
        }
        return keys
    }

    private func candidate(
        for record: PriceRecord,
        receivedAt: Date
    ) -> PriceObservationRules.Candidate? {
        guard let amount = record.effectiveUnitMarketPriceUSD,
              record.currencyCode == "USD",
              let source = record.source,
              let money = Money(rounding: amount) else { return nil }
        return PriceObservationRules.Candidate(
            value: PriceObservationValue(
                amount: money,
                currencyCode: record.currencyCode,
                sourceRaw: source.rawValue,
                sourceVariantID: record.sourceVariantID,
                marketVariantID: record.marketVariantID
            ),
            source: source,
            sourceUpdatedAt: record.sourceUpdatedAt,
            receivedAt: receivedAt
        )
    }

    private func usableAmount(for record: PriceRecord) -> Money? {
        guard record.currencyCode == "USD",
              let amount = record.effectiveUnitMarketPriceUSD else { return nil }
        return Money(rounding: amount)
    }

    // MARK: -

    /// A delayed CloudKit row can expose an older remote record after this
    /// device has already learned a newer one. Source-stamped providers can be
    /// compared by their market clock; unstamped providers use the remote
    /// fetch/check watermark conservatively. A local invalidation is exempt so
    /// a genuinely newly learned recovery can restore a value.
    private func isOutOfOrder(record: PriceRecord, comparedTo previous: PriceObservation) -> Bool {
        guard previous.kind != .explicitInvalidation else { return false }
        let remoteKnowledge = [
            record.fetchedAt,
            record.lastSuccessfulCheckAt,
            record.lastCheckedAt
        ]
        .compactMap { $0 }
        .max() ?? .distantPast

        if let sourceUpdatedAt = record.sourceUpdatedAt,
           previous.isSourceStamped,
           sourceUpdatedAt < previous.effectiveAt {
            return remoteKnowledge <= previous.receivedAt
        }
        return remoteKnowledge <= previous.receivedAt
    }

    private func previous(forKey key: String) -> PriceObservationRules.Previous? {
        guard let newest = newestObservation(instrumentKey: key) else { return nil }
        return PriceObservationRules.Previous(
            value: newest.value,
            effectiveAt: newest.effectiveAt,
            receivedAt: newest.receivedAt,
            isSourceStamped: newest.isSourceStamped
        )
    }

    private func append(
        candidate: PriceObservationRules.Candidate,
        kind: PriceObservationKind,
        instrumentKey: String
    ) {
        let observation = PriceObservation(
            instrumentKey: instrumentKey,
            kind: kind,
            amount: candidate.value.amount,
            currencyCode: candidate.value.currencyCode,
            source: candidate.source,
            sourceVariantID: candidate.value.sourceVariantID,
            marketVariantID: candidate.value.marketVariantID,
            effectiveAt: candidate.effectiveAt,
            receivedAt: candidate.receivedAt,
            isSourceStamped: candidate.isSourceStamped
        )
        context.insert(observation)
        index?.insert(observation)
    }
}
