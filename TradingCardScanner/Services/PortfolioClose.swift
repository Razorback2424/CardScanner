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

/// Production-owned result values for portfolio attribution.
///
/// The reference walk that populates these values lives in the test target. The
/// app uses the newer replay engine; keeping this small result type in the app
/// target preserves the public shape used by history and UI models without
/// shipping a second production calculation path.
enum PortfolioClose {
    struct Attribution: Equatable, Sendable {
        var closeValue: Money = .zero
        var market: Money = .zero
        var added: Money = .zero
        /// A positive magnitude. It is *subtracted* in the identity.
        var removed: Money = .zero
        var corrections: Money = .zero
        /// Value that arrived when a position newly recorded in the tracked
        /// portfolio received its first usable price. This is kept separate
        /// from ordinary pricing adjustments so an imported, initially
        /// unpriced collection does not look like a vendor repricing.
        var newlyAddedValue: Money = .zero
        var pricingAdjustment: Money = .zero
        var currentValue: Money = .zero
        var pricedPositionCount: Int = 0

        /// What the app claims happened since the close.
        var totalChange: Money {
            market + added - removed + corrections + newlyAddedValue + pricingAdjustment
        }

        /// What it cannot account for. Displayed, never absorbed: computing
        /// market movement as the leftover instead would make this zero by
        /// construction and prove nothing at all.
        var unexplained: Money {
            currentValue - closeValue - totalChange
        }

        var balances: Bool { unexplained.isZero }
    }
}
