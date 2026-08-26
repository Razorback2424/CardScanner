import Foundation

/// One ledger row, flattened into a value type.
struct LedgerEntry: Equatable, Sendable {
    var eventID: UUID
    var operationID: UUID
    var leg: InventoryCorrectionLeg?
    var kind: InventoryEventKind
    var occurredAt: Date
    /// When this device wrote the row. Only a revision needs it: an event with
    /// an `occurredAt` before a published boundary and a `recordedAt` after it
    /// is late ownership truth, not new activity.
    var recordedAt: Date
    /// The row this entry explicitly takes back. Reversal semantics belong to
    /// the accounting walk, not to the physical kind of the inverse row.
    var reversesEventID: UUID?
    var collectionKey: String
    var priceStorageKey: String
    var deltaQuantity: Int
    /// The price the event was stamped with. Evidence and provenance — the walk
    /// values flows from its own running price, so the two agreeing is a
    /// property to check rather than something to rely on.
    var unitPrice: Money?
    /// The knowledge time of the value this event was priced with. The
    /// tie-break basis when an event and an observation land on the same
    /// instant.
    var priceReceivedAtEvent: Date?
}

/// One price observation, flattened into a value type.
struct ObservationEntry: Equatable, Sendable {
    var id: UUID
    var instrumentKey: String
    var kind: PriceObservationKind
    /// `nil` for an explicit invalidation. Non-USD amounts are normalised to
    /// `nil` on the way in — the portfolio total has no exchange rate and says
    /// so rather than guessing one.
    var amount: Money?
    var receivedAt: Date
}

/// The daily close and the attribution walk.
///
/// Pure `nonisolated static` functions over value types, in the shape of
/// `CollectionQuery`: no view, no container, no clock. Everything here is
/// testable by handing it two arrays.
enum PortfolioClose {

    // MARK: - State carried through the walk

    /// Quantities, prices and the position-to-instrument mapping as of one
    /// instant.
    struct State: Equatable, Sendable {
        /// Position quantity, keyed by collection key.
        var quantities: [String: Int] = [:]
        /// Unit price, keyed by *instrument* — one price values every position
        /// that shares it, which is the whole reason prices are not stored on
        /// the card.
        var prices: [String: Money] = [:]
        /// Which instrument each position is currently valued through.
        var instruments: [String: String] = [:]

        /// `Σ qty × price` over every position whose instrument has a USD
        /// price. Unpriced and non-USD positions are excluded, never zeroed
        /// into the total and never converted at a rate the app does not have.
        var value: Money {
            quantities.reduce(Money.zero) { total, entry in
                guard entry.value != 0,
                      let instrument = instruments[entry.key],
                      let price = prices[instrument] else { return total }
                return total + price * entry.value
            }
        }

        var pricedPositionCount: Int {
            quantities.reduce(0) { count, entry in
                guard entry.value != 0,
                      let instrument = instruments[entry.key],
                      prices[instrument] != nil else { return count }
                return count + 1
            }
        }

        var heldInstrumentKeys: Set<String> {
            Set(quantities.compactMap { key, quantity in
                guard quantity != 0 else { return nil }
                return instruments[key]
            })
        }

        var excludedQuantity: Int {
            quantities.reduce(0) { count, entry in
                guard entry.value != 0,
                      let instrument = instruments[entry.key],
                      prices[instrument] != nil else {
                    return count + Swift.abs(entry.value)
                }
                return count
            }
        }
    }

    /// The state as of `instant`, from everything strictly before it.
    ///
    /// Half-open on purpose: `qty` uses events with `occurredAt < instant` and
    /// price uses observations with `receivedAt < instant`, so an event landing
    /// exactly on a boundary belongs to the day the boundary opens.
    nonisolated static func state(
        events: [LedgerEntry],
        observations: [ObservationEntry],
        asOf instant: Date
    ) -> State {
        var state = State()
        let timeline = orderedTimeline(
            events: events.filter { $0.occurredAt < instant },
            observations: observations.filter { $0.receivedAt < instant }
        )

        for item in timeline {
            switch item {
            case let .observation(observation):
                apply(observation, to: &state)
            case let .operation(legs):
                for event in legs {
                    state.quantities[event.collectionKey, default: 0] += event.deltaQuantity
                    state.instruments[event.collectionKey] = event.priceStorageKey
                }
            }
        }

        return state
    }

    /// `Close(D)` — the value of what was owned, at the prices known, as of the
    /// boundary that closes day `D`.
    nonisolated static func closeValue(
        events: [LedgerEntry],
        observations: [ObservationEntry],
        boundary: Date
    ) -> Money {
        state(events: events, observations: observations, asOf: boundary).value
    }

    // MARK: - Attribution

    struct Attribution: Equatable, Sendable {
        var closeValue: Money = .zero
        var market: Money = .zero
        var added: Money = .zero
        /// A positive magnitude. It is *subtracted* in the identity.
        var removed: Money = .zero
        var corrections: Money = .zero
        var pricingAdjustment: Money = .zero
        var currentValue: Money = .zero
        var pricedPositionCount: Int = 0

        /// What the app claims happened since the close.
        var totalChange: Money {
            market + added - removed + corrections + pricingAdjustment
        }

        /// What it cannot account for. Displayed, never absorbed: computing
        /// market movement as the leftover instead would make this zero by
        /// construction and prove nothing at all.
        var unexplained: Money {
            currentValue - closeValue - totalChange
        }

        var balances: Bool { unexplained.isZero }
    }

    /// Walks `[boundary, now]` as one ordered timeline of inventory events and
    /// price observations, carrying running quantities and prices.
    ///
    /// It has to be a walk rather than a set of independent formulas. Removing
    /// five of ten copies at noon and then watching the price rise means the
    /// afternoon's movement applies to five copies, not ten — which no formula
    /// evaluated over start-and-end states can see.
    ///
    /// `currentValue` is measured independently, from the collection itself.
    /// Feeding the walk's own ending value back in would make the residual
    /// vacuous.
    nonisolated static func attribute(
        events: [LedgerEntry],
        observations: [ObservationEntry],
        boundary: Date,
        now: Date,
        currentValue: Money,
        includeEndpoint: Bool = true
    ) -> Attribution {
        var state = state(events: events, observations: observations, asOf: boundary)
        var result = Attribution()
        result.closeValue = state.value
        result.currentValue = currentValue

        let inPeriod: (Date) -> Bool = { instant in
            instant >= boundary && (includeEndpoint ? instant <= now : instant < now)
        }
        let periodEvents = events.filter { inPeriod($0.occurredAt) }
        let eventByID = Dictionary(uniqueKeysWithValues: events.map { ($0.eventID, $0) })

        // An operation and its explicit undo in the same unpublished period
        // are audit rows, but not user-facing economic activity. Removing both
        // from the walk makes an add+Undo disappear and makes a remove+Undo
        // behave as though the temporary inventory mutation never happened.
        // Price observations still apply to the position that was actually
        // held across the period.
        var collapsedEventIDs: Set<UUID> = []
        for reversal in periodEvents {
            guard let originalID = reversal.reversesEventID,
                  let original = eventByID[originalID],
                  inPeriod(original.occurredAt) else { continue }
            collapsedEventIDs.insert(originalID)
            collapsedEventIDs.insert(reversal.eventID)
        }

        let timeline = orderedTimeline(
            events: periodEvents.filter { !collapsedEventIDs.contains($0.eventID) },
            observations: observations.filter { inPeriod($0.receivedAt) }
        )

        for item in timeline {
            switch item {
            case let .observation(observation):
                let instrument = observation.instrumentKey
                let old = state.prices[instrument]
                let new = observation.amount
                let quantity = quantityPriced(through: instrument, in: state)
                let difference = (new ?? .zero) - (old ?? .zero)

                // Market movement is only what the market did to a value the
                // app already held and still holds. An instrument arriving at
                // or leaving USD-priceability is a change in what the app
                // *knows*, and a restatement is history being rewritten;
                // neither is performance.
                let isMarketMovement = observation.kind == .marketUpdate
                    && old != nil
                    && new != nil

                if isMarketMovement {
                    result.market += difference * quantity
                } else {
                    result.pricingAdjustment += difference * quantity
                }

                apply(observation, to: &state)

            case let .operation(legs):
                // Both legs of a correction move together or the ledger does
                // not balance. Interleaving an observation between them would
                // value one identity before a price change and the other after.
                for event in legs {
                    let price = currentPrice(for: event, in: state)
                    let value = (price ?? .zero) * event.deltaQuantity

                    if event.reversesEventID != nil {
                        // Reversing an operation from an already-published
                        // period is today's correction. The old close remains
                        // immutable; the correction is valued at today's
                        // running price and keeps negative Added/Removed out of
                        // the UI.
                        result.corrections += value
                    } else {
                    switch event.kind {
                    case .correction:
                        result.corrections += value
                    case .dispose:
                        result.removed += Money(tenThousandths: -value.tenThousandths)
                    case .quantityAdjust:
                        result.corrections += value
                    case .acquire, .recordExisting, .initialBalance:
                        // A signed add: an undo of an acquisition retracts it
                        // from "Added" rather than reporting it as a sale.
                        result.added += value
                    }
                    }

                    state.quantities[event.collectionKey, default: 0] += event.deltaQuantity
                    state.instruments[event.collectionKey] = event.priceStorageKey
                }
            }
        }

        result.pricedPositionCount = state.pricedPositionCount
        return result
    }

    // MARK: - Ordering (contract 6)

    enum TimelineItem: Equatable, Sendable {
        case observation(ObservationEntry)
        /// Every leg of one operation, processed atomically.
        case operation([LedgerEntry])
    }

    /// A total order over the merged timeline, never left to Swift's sort
    /// stability.
    ///
    /// 1. By timestamp — `occurredAt` for inventory, `receivedAt` for prices.
    /// 2. Ties resolve from the event's own valuation basis: if an inventory
    ///    event's `priceReceivedAtEvent` equals the tied instant, the event was
    ///    priced *using* that observation, so the observation goes first.
    ///    Otherwise the inventory event goes first.
    /// 3. Correction legs stay together as a group.
    /// 4. Final tiebreak on a stable id, so any run is byte-reproducible.
    nonisolated static func orderedTimeline(
        events: [LedgerEntry],
        observations: [ObservationEntry]
    ) -> [TimelineItem] {
        var groups: [UUID: [LedgerEntry]] = [:]
        for event in events {
            groups[event.operationID, default: []].append(event)
        }

        // Within an operation, `from` before `to`, then by event id.
        let operations = groups.values.map { legs in
            legs.sorted { lhs, rhs in
                if lhs.leg != rhs.leg {
                    return (lhs.leg == .from) || (rhs.leg == .to && lhs.leg != nil)
                }
                return lhs.eventID.uuidString < rhs.eventID.uuidString
            }
        }

        var instants = Set(operations.compactMap { $0.first?.occurredAt })
        instants.formUnion(observations.map(\.receivedAt))

        var ordered: [TimelineItem] = []
        for instant in instants.sorted() {
            let tiedOperations = operations
                .filter { $0.first?.occurredAt == instant }
                .sorted { lhs, rhs in
                    lhs[0].eventID.uuidString < rhs[0].eventID.uuidString
                }
            let tiedObservations = observations
                .filter { $0.receivedAt == instant }
                .sorted { $0.id.uuidString < $1.id.uuidString }

            // One instant can contain operations valued from both sides of the
            // observation. The ordering decision is per operation, not global:
            // old-basis operations → observations → new-basis operations.
            let oldBasis = tiedOperations.filter { legs in
                !legs.contains { $0.priceReceivedAtEvent == instant }
            }
            let newBasis = tiedOperations.filter { legs in
                legs.contains { $0.priceReceivedAtEvent == instant }
            }
            ordered.append(contentsOf: oldBasis.map(TimelineItem.operation))
            ordered.append(contentsOf: tiedObservations.map(TimelineItem.observation))
            ordered.append(contentsOf: newBasis.map(TimelineItem.operation))
        }

        return ordered
    }

    // MARK: -

    private nonisolated static func apply(_ observation: ObservationEntry, to state: inout State) {
        if let amount = observation.amount {
            state.prices[observation.instrumentKey] = amount
        } else {
            state.prices.removeValue(forKey: observation.instrumentKey)
        }
    }

    /// Total quantity currently valued through one instrument. One observation
    /// values every position sharing it, however many rows that is.
    private nonisolated static func quantityPriced(
        through instrument: String,
        in state: State
    ) -> Int {
        state.quantities.reduce(0) { total, entry in
            state.instruments[entry.key] == instrument ? total + entry.value : total
        }
    }

    /// The price a flow is valued at: the running price for its instrument,
    /// and nothing else.
    ///
    /// Deliberately not falling back to the price stamped on the event. An
    /// instrument with no running price is excluded from both the close and the
    /// current value, so valuing its flows at some other number would guarantee
    /// a residual. A position the app cannot price contributes zero to every
    /// line and is reported separately as unpriced — which is the honest
    /// answer, not a gap.
    private nonisolated static func currentPrice(
        for event: LedgerEntry,
        in state: State
    ) -> Money? {
        state.prices[event.priceStorageKey]
    }
}
