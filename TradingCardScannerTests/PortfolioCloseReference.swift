import Foundation
@testable import TradingCardScanner

/// Independent accounting oracle retained in the test target. Production
/// portfolio values come from `PortfolioReplay`; this walk remains useful for
/// differential tests because it follows the older, deliberately explicit
/// timeline implementation.
extension PortfolioClose {
    struct State: Equatable, Sendable {
        var quantities: [String: Int] = [:]
        var prices: [String: Money] = [:]
        var instruments: [String: String] = [:]

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

    nonisolated static func closeValue(
        events: [LedgerEntry],
        observations: [ObservationEntry],
        boundary: Date
    ) -> Money {
        state(events: events, observations: observations, asOf: boundary).value
    }

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
        let eventByID = Dictionary(
            events.map { ($0.eventID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var pendingNewlyAddedQuantities: [String: Int] = [:]

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
                let newlyAddedQuantity: Int
                if old == nil, new != nil {
                    newlyAddedQuantity = min(
                        max(pendingNewlyAddedQuantities[instrument, default: 0], 0),
                        max(quantity, 0)
                    )
                } else {
                    newlyAddedQuantity = 0
                }

                let isMarketMovement = observation.kind == .marketUpdate
                    && old != nil
                    && new != nil
                if isMarketMovement {
                    result.market += difference * quantity
                } else {
                    result.newlyAddedValue += difference * newlyAddedQuantity
                    result.pricingAdjustment += difference * (quantity - newlyAddedQuantity)
                }

                pendingNewlyAddedQuantities.removeValue(forKey: instrument)
                apply(observation, to: &state)

            case let .operation(legs):
                for event in legs {
                    let price = currentPrice(for: event, in: state)
                    let value = (price ?? .zero) * event.deltaQuantity

                    if event.reversesEventID != nil {
                        result.corrections += value
                    } else {
                        switch event.kind {
                        case .correction:
                            result.corrections += value
                        case .dispose:
                            result.removed += -value
                        case .quantityAdjust:
                            result.corrections += value
                        case .acquire, .recordExisting, .initialBalance:
                            result.added += value
                        }
                    }

                    if event.deltaQuantity > 0,
                       (event.kind == .acquire || event.kind == .recordExisting),
                       price == nil {
                        pendingNewlyAddedQuantities[event.priceStorageKey, default: 0] += event.deltaQuantity
                    } else if event.deltaQuantity < 0 {
                        let remaining = max(
                            pendingNewlyAddedQuantities[event.priceStorageKey, default: 0] + event.deltaQuantity,
                            0
                        )
                        if remaining == 0 {
                            pendingNewlyAddedQuantities.removeValue(forKey: event.priceStorageKey)
                        } else {
                            pendingNewlyAddedQuantities[event.priceStorageKey] = remaining
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

    private enum TimelineItem: Equatable, Sendable {
        case observation(ObservationEntry)
        case operation([LedgerEntry])
    }

    private nonisolated static func orderedTimeline(
        events: [LedgerEntry],
        observations: [ObservationEntry]
    ) -> [TimelineItem] {
        var groups: [UUID: [LedgerEntry]] = [:]
        for event in events {
            groups[event.operationID, default: []].append(event)
        }

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
                .sorted { $0[0].eventID.uuidString < $1[0].eventID.uuidString }
            let tiedObservations = observations
                .filter { $0.receivedAt == instant }
                .sorted { $0.id.uuidString < $1.id.uuidString }

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

    private nonisolated static func apply(_ observation: ObservationEntry, to state: inout State) {
        if let amount = observation.amount {
            state.prices[observation.instrumentKey] = amount
        } else {
            state.prices.removeValue(forKey: observation.instrumentKey)
        }
    }

    private nonisolated static func quantityPriced(
        through instrument: String,
        in state: State
    ) -> Int {
        state.quantities.reduce(0) { total, entry in
            state.instruments[entry.key] == instrument ? total + entry.value : total
        }
    }

    private nonisolated static func currentPrice(
        for event: LedgerEntry,
        in state: State
    ) -> Money? {
        state.prices[event.priceStorageKey]
    }
}
