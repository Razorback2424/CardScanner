import Foundation

/// Exact USD money, stored as a signed count of ten-thousandths of a dollar.
///
/// Portfolio arithmetic has to reconcile to *exactly* zero, not to within an
/// epsilon: the whole point of a ledger is that `current − close − market −
/// flows` is either balanced or is a defect worth surfacing. Doubles cannot
/// promise that, so provider `Double`s are converted once at ingestion and
/// every computation downstream is integer.
///
/// Four decimal places absorbs any precision a price provider publishes, and
/// `Int64` leaves headroom to roughly $9 × 10¹⁴ — far past anything a
/// collection can hold.
struct Money: Hashable, Comparable, Sendable {
    /// Ten-thousandths of a dollar. Public because it is what gets persisted;
    /// SwiftData stores the scalar, never this type.
    var tenThousandths: Int64

    static let zero = Money(tenThousandths: 0)

    /// The scale factor between a dollar and the stored unit.
    static let scale: Int64 = 10_000

    init(tenThousandths: Int64) {
        self.tenThousandths = tenThousandths
    }

    /// The single conversion point from provider floating point. Invalid or
    /// unrepresentable quotes are rejected; they never become a real zero or a
    /// near-maximum integer that can overflow later arithmetic.
    init?(rounding dollars: Double) {
        guard dollars.isFinite else { return nil }
        let scaled = (dollars * Double(Money.scale)).rounded()
        guard scaled < Double(Int64.max), scaled > Double(Int64.min) else { return nil }
        self.tenThousandths = Int64(scaled)
    }

    /// Lossy on purpose, and only for display and for the existing `Double`
    /// surfaces. Never feed this back into portfolio arithmetic.
    var doubleValue: Double { Double(tenThousandths) / Double(Money.scale) }

    var isZero: Bool { tenThousandths == 0 }
    var magnitude: Money { Money(tenThousandths: Swift.abs(tenThousandths)) }

    static func + (lhs: Money, rhs: Money) -> Money {
        Money(tenThousandths: lhs.tenThousandths + rhs.tenThousandths)
    }

    static func - (lhs: Money, rhs: Money) -> Money {
        Money(tenThousandths: lhs.tenThousandths - rhs.tenThousandths)
    }

    static prefix func - (value: Money) -> Money {
        Money(tenThousandths: -value.tenThousandths)
    }

    /// Quantity is the only thing money is ever multiplied by here. There is no
    /// `Money × Money`, and no division: a portfolio total is a sum of
    /// `unit price × copies owned` and nothing else.
    static func * (lhs: Money, rhs: Int) -> Money {
        Money(tenThousandths: lhs.tenThousandths * Int64(rhs))
    }

    static func * (lhs: Int, rhs: Money) -> Money { rhs * lhs }

    static func += (lhs: inout Money, rhs: Money) { lhs = lhs + rhs }
    static func -= (lhs: inout Money, rhs: Money) { lhs = lhs - rhs }

    static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.tenThousandths < rhs.tenThousandths
    }
}

extension Money: CustomStringConvertible {
    var description: String { formatted() }
}

extension Money {
    /// Currency formatting for display. Two fraction digits, matching every
    /// existing price surface in the app; the extra stored precision exists for
    /// arithmetic, not for the user.
    func formatted(currencyCode: String = "USD") -> String {
        doubleValue.formatted(.currency(code: currencyCode).precision(.fractionLength(2)))
    }
}

extension Sequence where Element == Money {
    func sum() -> Money { reduce(Money.zero, +) }
}
