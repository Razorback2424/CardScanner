import Foundation
import SwiftData

/// Where a number came from. Stored so a mapping that later turns out to be
/// wrong can be found and re-evaluated rather than silently living on.
enum PriceSource: String, Codable, Hashable, Sendable {
    case tcgplayer
    case scryfall

    var label: String {
        switch self {
        case .tcgplayer: return "TCGplayer"
        case .scryfall: return "Scryfall"
        }
    }

    /// Whether the provider publishes its own "this data is current through"
    /// timestamp. When it does not, the app may only ever say when *it* checked.
    var publishesSourceTimestamp: Bool {
        switch self {
        case .tcgplayer: return true
        case .scryfall: return false
        }
    }
}

/// One price observation for one physical variant of one printing.
///
/// Deliberately not a field on the card. A card does not "cost $42 forever"; what
/// is true is that this physical variant's latest known market price was $42 as
/// of a particular moment, from a particular source. That is a mutable
/// observation with its own lifecycle, and it is shared by every copy the user
/// owns — eight copies of one printing are one price to refresh, not eight.
@Model
final class PriceRecord {
    @Attribute(.unique) var key: String

    var game: String
    var printingID: String
    var variantID: String?

    /// `nil` means the provider exposes no price we are willing to attribute to
    /// this physical variant. It never means zero, and it must never be filled in
    /// with a different finish's price merely to produce a number.
    var unitMarketPriceUSD: Double?
    var currencyCode: String = "USD"

    var sourceRaw: String?
    /// The provider-side listing the number was read from, e.g. `reverse-holofoil`.
    var sourceVariantID: String?
    /// When the *market data* is current through, per the provider.
    var sourceUpdatedAt: Date?
    /// When this app last retrieved the value it is currently showing.
    var fetchedAt: Date?
    /// When this app last asked, successfully or not.
    var lastCheckedAt: Date?
    /// Set when the most recent attempt failed. Cleared on the next success, so a
    /// stale-but-real price is never replaced by nothing.
    var lastFailureAt: Date?

    init(
        key: String,
        game: CardGame,
        printingID: String,
        variantID: String?
    ) {
        self.key = key
        self.game = game.rawValue
        self.printingID = printingID
        self.variantID = variantID
    }

    static func key(game: CardGame, printingID: String, variantID: String?) -> String {
        "\(game.rawValue):\(printingID):\(variantID ?? "-")"
    }

    var source: PriceSource? {
        sourceRaw.flatMap(PriceSource.init(rawValue:))
    }

    func apply(_ price: NormalizedPrice) {
        unitMarketPriceUSD = price.unitMarketPriceUSD
        currencyCode = price.currencyCode
        sourceRaw = price.source.rawValue
        sourceVariantID = price.sourceVariantID
        sourceUpdatedAt = price.sourceUpdatedAt
        fetchedAt = price.fetchedAt
        lastCheckedAt = price.fetchedAt
        lastFailureAt = nil
    }

    /// The provider answered and had nothing for this variant. That is a real,
    /// current answer — "unavailable" — not a failure.
    func applyUnavailable(source: PriceSource?, at date: Date) {
        unitMarketPriceUSD = nil
        sourceRaw = source?.rawValue
        sourceVariantID = nil
        sourceUpdatedAt = nil
        fetchedAt = date
        lastCheckedAt = date
        lastFailureAt = nil
    }

    /// The attempt failed. Keep whatever price is already here.
    func recordFailure(at date: Date) {
        lastCheckedAt = date
        lastFailureAt = date
    }

    var display: PriceDisplay {
        PriceDisplay(
            amount: unitMarketPriceUSD,
            source: source,
            sourceUpdatedAt: sourceUpdatedAt,
            fetchedAt: fetchedAt,
            lastCheckedAt: lastCheckedAt,
            refreshFailed: lastFailureAt != nil
        )
    }
}

/// A price, plus everything needed to say honestly how much it can be trusted.
struct PriceDisplay: Equatable, Sendable {
    enum State: Equatable, Sendable {
        /// Recent enough to present as the current market price.
        case current
        /// Real, but old enough that the app has to say so.
        case stale
        /// The provider has no price it can attribute to this physical variant.
        case unavailable
        /// Never asked.
        case unknown
    }

    var amount: Double? = nil
    var source: PriceSource? = nil
    var sourceUpdatedAt: Date? = nil
    var fetchedAt: Date? = nil
    var lastCheckedAt: Date? = nil
    var refreshFailed: Bool = false

    static let unknown = PriceDisplay()

    /// Beyond this, a price is presented as stale rather than current.
    static let staleAfter: TimeInterval = 24 * 60 * 60

    /// The moment the *market data* is current through, as far as this app can
    /// honestly claim. Falls back to the fetch time only for providers that do
    /// not publish their own timestamp.
    var effectiveAsOf: Date? {
        sourceUpdatedAt ?? fetchedAt
    }

    func state(now: Date = .now) -> State {
        guard lastCheckedAt != nil || fetchedAt != nil else { return .unknown }
        guard amount != nil else { return refreshFailed ? .unknown : .unavailable }
        guard let asOf = effectiveAsOf else { return .stale }
        return now.timeIntervalSince(asOf) <= Self.staleAfter ? .current : .stale
    }
}
