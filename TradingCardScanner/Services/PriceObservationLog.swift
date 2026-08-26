import Foundation
import SwiftData

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
    }

    /// Whether a provider answer is value-setting, and if so what it means.
    nonisolated static func decide(candidate: Candidate, previous: Previous?) -> Decision {
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
    var timeZone: TimeZone = PortfolioCalendar.timeZone()

    // MARK: - Reading

    func newestObservation(instrumentKey: String) -> PriceObservation? {
        var descriptor = FetchDescriptor<PriceObservation>(
            predicate: #Predicate { $0.instrumentKey == instrumentKey },
            sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func observations(instrumentKey: String) -> [PriceObservation] {
        let descriptor = FetchDescriptor<PriceObservation>(
            predicate: #Predicate { $0.instrumentKey == instrumentKey },
            sortBy: [SortDescriptor(\.receivedAt, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func checkDay(instrumentKey: String, day: Date) -> PriceCheckDay? {
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
        guard let previous = newestObservation(instrumentKey: instrumentKey),
              previous.amount != nil else { return nil }

        let observation = PriceObservation(
            instrumentKey: instrumentKey,
            kind: .explicitInvalidation,
            amount: nil,
            currencyCode: previous.currencyCode,
            source: source,
            sourceVariantID: previous.sourceVariantID,
            marketVariantID: previous.marketVariantID,
            effectiveAt: date,
            receivedAt: date,
            isSourceStamped: false
        )
        context.insert(observation)
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
            return
        }
        context.insert(
            PriceCheckDay(
                instrumentKey: instrumentKey,
                portfolioDay: day,
                lastSuccessfulCheckAt: date,
                source: source
            )
        )
    }

    // MARK: - Backfill

    /// Gives every already-priced instrument a first observation.
    ///
    /// `PriceRecord` overwrites in place, so every valuation this app computed
    /// before the log existed is already gone. What survives is the *current*
    /// value and when it was fetched, and that is enough to open the log
    /// honestly: "as of this moment, this is what the app believed".
    ///
    /// Runs on every launch and is idempotent — it writes only where an
    /// instrument has a usable value and no observation at all. That also
    /// covers the case the ledger baseline cannot: a second device inherits the
    /// synced `PriceRecord`s but none of the first device's local observations,
    /// and seeds its own.
    @discardableResult
    func backfillFromRecords(receivedAt localKnowledgeTime: Date = .now) -> Int {
        let records = PriceStore(context: context).allRecords()
        var written = 0

        for record in records {
            guard let amount = record.unitMarketPriceUSD,
                  record.currencyCode == "USD",
                  let source = record.source,
                  let money = Money(rounding: amount),
                  newestObservation(instrumentKey: record.key) == nil else { continue }

            context.insert(
                PriceObservation(
                    instrumentKey: record.key,
                    kind: .marketUpdate,
                    amount: money,
                    currencyCode: record.currencyCode,
                    source: source,
                    sourceVariantID: record.sourceVariantID,
                    marketVariantID: record.marketVariantID,
                    effectiveAt: record.sourceUpdatedAt ?? localKnowledgeTime,
                    // A synced PriceRecord's fetchedAt belongs to the device
                    // that originally fetched it. This device learned the
                    // inherited value now and must never fabricate history by
                    // copying the remote timestamp into local knowledge time.
                    receivedAt: localKnowledgeTime,
                    isSourceStamped: source.publishesSourceTimestamp && record.sourceUpdatedAt != nil
                )
            )
            written += 1
        }

        if written > 0 { try? context.save() }
        return written
    }

    // MARK: -

    private func previous(forKey key: String) -> PriceObservationRules.Previous? {
        guard let newest = newestObservation(instrumentKey: key) else { return nil }
        return PriceObservationRules.Previous(
            value: newest.value,
            effectiveAt: newest.effectiveAt,
            isSourceStamped: newest.isSourceStamped
        )
    }

    private func append(
        candidate: PriceObservationRules.Candidate,
        kind: PriceObservationKind,
        instrumentKey: String
    ) {
        context.insert(
            PriceObservation(
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
        )
    }
}
