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

    /// Arithmetic never traps on malformed collection sizes or provider data.
    /// An overflow keeps the CPU's reporting partial value for diagnostics, but
    /// is marked invalid so no caller can mistake it for a real amount.
    private(set) var isOverflowed: Bool

    static let zero = Money(tenThousandths: 0)

    /// The scale factor between a dollar and the stored unit.
    static let scale: Int64 = 10_000

    init(tenThousandths: Int64, isOverflowed: Bool = false) {
        self.tenThousandths = tenThousandths
        self.isOverflowed = isOverflowed
    }

    /// The single conversion point from provider floating point. Invalid or
    /// unrepresentable quotes are rejected; they never become a real zero or a
    /// near-maximum integer that can overflow later arithmetic.
    init?(rounding dollars: Double) {
        guard dollars.isFinite else { return nil }
        let scaled = (dollars * Double(Money.scale)).rounded()
        guard scaled < Double(Int64.max), scaled > Double(Int64.min) else { return nil }
        self.tenThousandths = Int64(scaled)
        self.isOverflowed = false
    }

    /// True when this amount can safely be used as a financial value.
    var isValid: Bool { !isOverflowed }

    /// Lossy on purpose, and only for display and for the existing `Double`
    /// surfaces. Never feed this back into portfolio arithmetic.
    var doubleValue: Double {
        guard isValid else { return .nan }
        return Double(tenThousandths) / Double(Money.scale)
    }

    var isZero: Bool { isValid && tenThousandths == 0 }
    var magnitude: Money {
        guard tenThousandths < 0 else { return self }
        let (magnitude, overflowed) = Int64.zero.subtractingReportingOverflow(tenThousandths)
        return Money(
            tenThousandths: magnitude,
            isOverflowed: isOverflowed || overflowed
        )
    }

    static func + (lhs: Money, rhs: Money) -> Money {
        let (value, overflowed) = lhs.tenThousandths.addingReportingOverflow(rhs.tenThousandths)
        return Money(
            tenThousandths: value,
            isOverflowed: lhs.isOverflowed || rhs.isOverflowed || overflowed
        )
    }

    static func - (lhs: Money, rhs: Money) -> Money {
        let (value, overflowed) = lhs.tenThousandths.subtractingReportingOverflow(rhs.tenThousandths)
        return Money(
            tenThousandths: value,
            isOverflowed: lhs.isOverflowed || rhs.isOverflowed || overflowed
        )
    }

    static prefix func - (value: Money) -> Money {
        let (negated, overflowed) = Int64.zero.subtractingReportingOverflow(value.tenThousandths)
        return Money(
            tenThousandths: negated,
            isOverflowed: value.isOverflowed || overflowed
        )
    }

    /// Quantity is the only thing money is ever multiplied by here. There is no
    /// `Money × Money`, and no division: a portfolio total is a sum of
    /// `unit price × copies owned` and nothing else.
    static func * (lhs: Money, rhs: Int) -> Money {
        let (value, overflowed) = lhs.tenThousandths.multipliedReportingOverflow(by: Int64(rhs))
        return Money(
            tenThousandths: value,
            isOverflowed: lhs.isOverflowed || overflowed
        )
    }

    static func * (lhs: Int, rhs: Money) -> Money { rhs * lhs }

    static func += (lhs: inout Money, rhs: Money) { lhs = lhs + rhs }
    static func -= (lhs: inout Money, rhs: Money) { lhs = lhs - rhs }

    static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.tenThousandths < rhs.tenThousandths
    }

    /// Overflow is validity metadata, not part of monetary identity. Keeping
    /// equality aligned with `<` preserves Comparable's total-order contract;
    /// callers that need a usable amount check `isValid` explicitly.
    static func == (lhs: Money, rhs: Money) -> Bool {
        lhs.tenThousandths == rhs.tenThousandths
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(tenThousandths)
    }
}

extension Money: CustomStringConvertible {
    var description: String { formatted() }
}

extension Money {
    /// Checked forms are for boundaries that can report a provider or ledger
    /// defect instead of merely carrying an invalid intermediate amount.
    func adding(_ other: Money) -> Money? {
        let result = self + other
        return result.isValid ? result : nil
    }

    func subtracting(_ other: Money) -> Money? {
        let result = self - other
        return result.isValid ? result : nil
    }

    func multiplied(by quantity: Int) -> Money? {
        let result = self * quantity
        return result.isValid ? result : nil
    }

    /// Currency formatting for display. Two fraction digits, matching every
    /// existing price surface in the app; the extra stored precision exists for
    /// arithmetic, not for the user.
    func formatted(currencyCode: String = "USD") -> String {
        guard isValid else { return "Value unavailable" }
        return doubleValue.formatted(.currency(code: currencyCode).precision(.fractionLength(2)))
    }
}

extension Sequence where Element == Money {
    func sum() -> Money { reduce(Money.zero, +) }
}
