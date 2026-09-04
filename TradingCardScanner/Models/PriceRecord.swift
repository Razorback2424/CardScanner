import Foundation
import SwiftData

/// Where a number came from. Stored so a mapping that later turns out to be
/// wrong can be found and re-evaluated rather than silently living on.
enum PriceSource: String, Codable, Hashable, Sendable {
    case tcgplayer
    case scryfall
    /// Used only where TCGdex carries no TCGplayer figure. Quotes euros, and is
    /// stored and shown as euros — see `PriceRecord.currencyCode`.
    case cardmarket
    /// The product-level fallback, consulted only for cards the catalog cannot
    /// price. Quotes USD, which is why it is tried ahead of Cardmarket.
    case justTCG
    case importedCSV

    var label: String {
        switch self {
        case .tcgplayer: return "TCGplayer"
        case .scryfall: return "Scryfall"
        case .cardmarket: return "Cardmarket"
        case .justTCG: return "JustTCG"
        case .importedCSV: return "Imported CSV"
        }
    }

    /// Whether the provider publishes its own "this data is current through"
    /// timestamp. When it does not, the app may only ever say when *it* checked.
    var publishesSourceTimestamp: Bool {
        switch self {
        case .tcgplayer: return true
        case .scryfall: return false
        case .cardmarket: return true
        case .justTCG: return true
        case .importedCSV: return true
        }
    }
}

extension PriceSource {
    /// Current live providers do not publish a treatment-specific Magic
    /// listing. Imported CSV data is the only source that can carry an explicit
    /// user-supplied treatment claim until a reviewed provider mapping exists.
    var isProvenForMagicTreatment: Bool {
        self == .importedCSV
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
    // CloudKit does not support unique constraints, so uniqueness for this key
    // is enforced in code (PriceStore fetches by `key` before every insert)
    // rather than by the store.
    @Attribute var key: String = ""

    var game: String = ""
    var printingID: String = ""
    var variantID: String?
    /// Treatment identity is persisted separately from `variantID`; a Magic
    /// foil can be ordinary foil or a named foil treatment, and those prices
    /// must never collapse onto one record. The default preserves rows written
    /// before treatment identity existed.
    var magicTreatmentIDsRaw: [String] = []

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
    ///
    /// Deliberately not a freshness signal on its own: `recordFailure` sets it
    /// too, so a 3 PM failure would report as "checked at 3 PM" while erasing
    /// any trace of a good 9 AM check. Use `lastSuccessfulCheckAt` for anything
    /// that needs to know the app actually got an answer.
    var lastCheckedAt: Date?
    /// When this app last received a real answer — a price, or an explicit
    /// "nothing for this variant". Untouched by failures, so a later failure
    /// can never overwrite the evidence of an earlier success.
    var lastSuccessfulCheckAt: Date?
    // MARK: - Market metadata
    //
    // All optional, so every record written before these existed keeps working
    // untouched.

    var itemKindRaw: String?
    /// The vendor's stable card UUID this observation came from.
    var canonicalMarketID: String?
    /// The vendor's stable *variant* UUID — the exact object priced.
    var marketVariantID: String?
    var marketRegionRaw: String?
    /// The vendor's own "this game was repriced at" clock, distinct from both
    /// when the app checked and when this variant's price last moved. Used to
    /// avoid spending a request on a game that has not been repriced.
    var providerGameUpdatedAt: Date?

    // Summary statistics, populated only when history is explicitly requested
    // from an item's detail screen. Routine refreshes never ask for history.
    var historyObservationCount: Int?
    var periodChangeCount: Int?
    var periodLow: Double?
    var periodHigh: Double?
    var coefficientOfVariation: Double?

    var itemKind: CollectionItemKind? {
        itemKindRaw.flatMap(CollectionItemKind.init(rawValue:))
    }

    /// Set when the most recent attempt failed. Cleared on the next success, so a
    /// stale-but-real price is never replaced by nothing.
    var lastFailureAt: Date?
    /// Stable support-facing diagnosis for rejected data or request failures.
    var lastFailureReasonRaw: String?

    /// The last time this record's value was explicitly withdrawn because it
    /// was attached to the wrong market variant. The observation log is the
    /// historical source of truth; this synced watermark is the read-path
    /// guard that keeps collection/detail surfaces (which only receive
    /// `PriceRecord`s) from resurrecting the withdrawn amount.
    var invalidatedAt: Date?

    init(
        key: String,
        game: CardGame,
        printingID: String,
        variantID: String?,
        magicTreatmentIDs: [String] = []
    ) {
        self.key = key
        self.game = game.rawValue
        self.printingID = printingID
        self.variantID = variantID
        self.magicTreatmentIDsRaw = MagicTreatmentKeyCodec.storedIDs(from: magicTreatmentIDs)
    }

    static func key(
        game: CardGame,
        printingID: String,
        variantID: String?,
        treatmentIDs: [String] = []
    ) -> String {
        let base = "\(game.rawValue):\(printingID):\(variantID ?? "-")"
        guard game == .magic else { return base }
        return MagicTreatmentKeyCodec.appendPriceSuffix(to: base, rawIDs: treatmentIDs)
    }

    var source: PriceSource? {
        sourceRaw.flatMap(PriceSource.init(rawValue:))
    }

    @discardableResult
    func apply(_ price: NormalizedPrice) -> Bool {
        // A response learned before an invalidation is stale evidence. It may
        // still be useful in the append-only history, but it must not restore
        // the mutable record's value or clear the invalidation watermark.
        if let invalidatedAt, price.fetchedAt <= invalidatedAt { return false }

        unitMarketPriceUSD = price.unitMarketPriceUSD
        currencyCode = price.currencyCode
        sourceRaw = price.source.rawValue
        sourceVariantID = price.sourceVariantID
        sourceUpdatedAt = price.sourceUpdatedAt
        fetchedAt = price.fetchedAt
        lastCheckedAt = price.fetchedAt
        lastSuccessfulCheckAt = price.fetchedAt
        lastFailureAt = nil
        lastFailureReasonRaw = nil
        self.invalidatedAt = nil
        return true
    }

    /// Keeps the exact per-variant market value supplied by an import while
    /// leaving the record eligible for an immediate live provider check.
    @discardableResult
    func applyImported(amount: Double, sourceUpdatedAt: Date?, importedAt: Date = .now) -> Bool {
        if let invalidatedAt, importedAt <= invalidatedAt { return false }

        unitMarketPriceUSD = amount
        currencyCode = "USD"
        sourceRaw = PriceSource.importedCSV.rawValue
        sourceVariantID = variantID
        self.sourceUpdatedAt = sourceUpdatedAt
        fetchedAt = importedAt
        // An import is not a provider check. Leaving both check fields empty
        // keeps the row eligible for an immediate live check and keeps the
        // imported value out of today's coverage numbers.
        lastCheckedAt = nil
        lastSuccessfulCheckAt = nil
        lastFailureAt = nil
        lastFailureReasonRaw = nil
        invalidatedAt = nil
        return true
    }

    /// Withdraws the current amount without pretending that the provider
    /// answered "no price". A later valid observation is allowed to replace
    /// this state through `apply(_:)` or `applyImported`.
    @discardableResult
    func invalidate(at date: Date) -> Bool {
        if let invalidatedAt, invalidatedAt > date { return false }
        if invalidatedAt == nil, let fetchedAt, fetchedAt > date { return false }
        invalidatedAt = date
        unitMarketPriceUSD = nil
        return true
    }

    var isInvalidated: Bool { invalidatedAt != nil }

    /// The key marker is included for rows written by a pre-Slice-6 build that
    /// had already adopted the treatment-qualified key but had not yet stored
    /// the mirrored treatment column. It also keeps this check correct if a
    /// future sync delivers the key and column in separate transactions.
    var isMagicTreatmentQualified: Bool {
        (game == CardGame.magic.rawValue && !magicTreatmentIDsRaw.isEmpty)
            || MagicTreatmentKeyCodec.containsPriceTreatmentSuffix(in: key)
    }

    /// A pre-Slice-6 build could store Scryfall's generic `usd_foil` value under
    /// a treatment-qualified key. Keep that historical row readable for
    /// migration, but never expose it as current collection evidence. The same
    /// quarantine covers the generic JustTCG fallback and any future live source
    /// until it explicitly proves the treatment.
    var isUnprovenMagicTreatmentPrice: Bool {
        guard isMagicTreatmentQualified else { return false }
        return !(source?.isProvenForMagicTreatment ?? false)
    }

    /// The amount that a read path may safely expose. Keeping this derived
    /// property next to the mutable record makes the invalidation rule explicit
    /// for services that do not have access to the local observation log.
    var effectiveUnitMarketPriceUSD: Double? {
        guard !isInvalidated, !isUnprovenMagicTreatmentPrice else { return nil }
        return unitMarketPriceUSD
    }

    /// The provider answered and had nothing for this variant. That is a real,
    /// current answer — "unavailable" — not a failure.
    func applyUnavailable(source: PriceSource?, at date: Date) {
        // A provider lacking this exact variant does not invalidate a known,
        // dated price imported for that same variant.
        if effectiveUnitMarketPriceUSD == nil {
            unitMarketPriceUSD = nil
            sourceRaw = source?.rawValue
            sourceVariantID = nil
            sourceUpdatedAt = nil
            fetchedAt = date
        }
        lastCheckedAt = date
        lastSuccessfulCheckAt = date
        lastFailureAt = nil
    }

    /// The attempt failed. Keep whatever price is already here — and leave
    /// `lastSuccessfulCheckAt` alone, so today's coverage still reflects this
    /// morning's successful check rather than this afternoon's timeout.
    func recordFailure(at date: Date) {
        lastCheckedAt = date
        lastFailureAt = date
    }

    var display: PriceDisplay {
        PriceDisplay(
            amount: effectiveUnitMarketPriceUSD,
            currencyCode: currencyCode,
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
    /// The currency `amount` is quoted in. Not decoration: Cardmarket quotes
    /// euros, and formatting a euro figure with a dollar sign would misstate a
    /// number the user makes decisions on.
    var currencyCode: String = "USD"
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
