import Foundation
import SwiftData

/// What a new observation *means*, decided at ingestion where the provider's
/// semantics are still known.
///
/// The portfolio engine must never re-derive this. By the time it walks a
/// timeline it has lost the provider context that separates "the market moved"
/// from "the vendor restated a number it had already published", and guessing
/// there is how a restatement gets shown to someone as a gain they never made.
enum PriceObservationKind: String, Codable, Hashable, Sendable {
    /// A new value the market genuinely arrived at. Contributes to market
    /// movement.
    case marketUpdate
    /// The provider republished a value for a period it had already reported.
    /// Contributes to pricing adjustment, never to performance.
    case sourceRestatement
    /// The app changed provider or corrected which provider-side object maps
    /// to this instrument. A value delta here is pricing provenance being
    /// repaired, not market performance.
    case sourceTransition
    /// The app is withdrawing a value it should not have held — a price found
    /// to have been attached to the wrong market variant.
    case explicitInvalidation
    /// A previously learned deadline elapsed; receivedAt is the deadline,
    /// effectiveAt is when the deadline evidence was learned (not a sale date).
    case eligibilityExpiry
    /// A physical-identity rule became known locally at receivedAt.
    case physicalReview
    /// Forward compatibility: unfamiliar semantics cannot reinstate a value.
    case unrecognized

    var withdrawsValue: Bool {
        switch self {
        case .explicitInvalidation, .eligibilityExpiry, .physicalReview, .unrecognized: return true
        default: return false
        }
    }

    /// Scheduled expiry precedes a genuine same-instant recovery. Explicit
    /// withdrawals and review rules dominate a quote at the same instant.
    var orderingPriority: Int {
        switch self {
        case .eligibilityExpiry: return 0
        case .marketUpdate, .sourceRestatement, .sourceTransition: return 1
        case .explicitInvalidation: return 2
        case .physicalReview: return 3
        case .unrecognized: return 4
        }
    }
}

/// One append-only entry in the price observation log.
///
/// Local-only and deliberately so: this table is where the app's *knowledge
/// history* lives, and knowledge history is per-device until a shared pricing
/// service exists. Syncing it would merge two devices' refresh schedules into a
/// history neither of them actually observed.
///
/// **Value-setting only.** A row exists here because the app now believes a
/// different value, or believes the same value about a different object. A
/// provider answering "I have nothing for this variant" is a *check outcome*,
/// not an observation: it writes `PriceCheckDay`, leaves the prior value
/// carrying forward, and writes nothing here.
@Model
final class PriceObservation {
    #Index<PriceObservation>([\.instrumentKey, \.receivedAt])

    var id: UUID = UUID()
    /// Matches `PriceRecord.key` — game, printing and physical variant. One
    /// observation values every copy owned of that exact object.
    var instrumentKey: String = ""
    var kindRaw: String = ""

    /// `nil` means a withdrawal (explicit or local eligibility). It never
    /// means "the provider was unreachable" and
    /// never means "no listing exists" — those write no row at all.
    var amountUSDTenThousandths: Int64?
    var currencyCode: String = "USD"

    var sourceRaw: String = ""
    /// The provider-side listing the number was read from. Part of the
    /// identity of what is being priced, not decoration.
    var sourceVariantID: String?
    /// The vendor's stable variant UUID, where one exists.
    var marketVariantID: String?

    /// The provider's own "current through" clock. Provenance, and the basis
    /// for classifying a restatement.
    var effectiveAt: Date = Date.now
    /// When *this app* learned the value. Knowledge time is what governs which
    /// side of a day boundary an observation falls on: a vendor backdating a
    /// price does not move a close that was already published.
    var receivedAt: Date = Date.now
    /// Whether `effectiveAt` is the provider's claim or merely a stand-in for
    /// the fetch time. False for Scryfall, which publishes no clock.
    var isSourceStamped: Bool = false

    /// Accepted local provider checks and synced-record reconciliation write
    /// this receipt. A remote checkedAt cannot establish local knowledge; the
    /// receipt records that local time without changing the price observation
    /// when only a deadline changes. Older histories keep this field absent.
    var syncedGradedQuoteEvidenceJSON: String?

    init(
        instrumentKey: String,
        kind: PriceObservationKind,
        amount: Money?,
        currencyCode: String = "USD",
        source: PriceSource? = nil,
        sourceVariantID: String?,
        marketVariantID: String?,
        effectiveAt: Date,
        receivedAt: Date,
        isSourceStamped: Bool
    ) {
        self.id = UUID()
        self.instrumentKey = instrumentKey
        self.kindRaw = kind.rawValue
        self.amountUSDTenThousandths = amount?.tenThousandths
        self.currencyCode = currencyCode
        self.sourceRaw = source?.rawValue ?? ""
        self.sourceVariantID = sourceVariantID
        self.marketVariantID = marketVariantID
        self.effectiveAt = effectiveAt
        self.receivedAt = receivedAt
        self.isSourceStamped = isSourceStamped
    }

    var kind: PriceObservationKind {
        PriceObservationKind(rawValue: kindRaw) ?? .unrecognized
    }

    var source: PriceSource? { PriceSource(rawValue: sourceRaw) }

    var amount: Money? {
        amountUSDTenThousandths.map { Money(tenThousandths: $0) }
    }

    /// USD is comparable for portfolio valuation regardless of whether the
    /// exact provider printing also carries a Magic treatment identity. Non-USD
    /// observations remain visible to diagnostics but cannot enter the USD
    /// valuation.
    var effectiveUSDAmount: Money? {
        guard !kind.withdrawsValue else { return nil }
        return PortfolioPriceEligibility.eligibleUnitPrice(
            amount: amount?.doubleValue,
            currencyCode: currencyCode
        )
    }

    static func isNewer(_ candidate: PriceObservation, than incumbent: PriceObservation) -> Bool {
        if candidate.receivedAt != incumbent.receivedAt { return candidate.receivedAt > incumbent.receivedAt }
        if candidate.kind.orderingPriority != incumbent.kind.orderingPriority {
            return candidate.kind.orderingPriority > incumbent.kind.orderingPriority
        }
        return candidate.id.uuidString > incumbent.id.uuidString
    }

    /// The value-setting content of this row, as the pure ingestion logic sees
    /// it. Provenance is part of it on purpose — see `PriceObservationValue`.
    var value: PriceObservationValue {
        PriceObservationValue(
            amount: amount,
            currencyCode: currencyCode,
            sourceRaw: sourceRaw,
            sourceVariantID: sourceVariantID,
            marketVariantID: marketVariantID
        )
    }

    var syncedGradedQuoteReceipt: SyncedGradedQuoteReceipt? {
        get {
            guard let data = syncedGradedQuoteEvidenceJSON?.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(SyncedGradedQuoteReceipt.self, from: data)
        }
        set {
            syncedGradedQuoteEvidenceJSON = newValue.flatMap { receipt in
                (try? JSONEncoder().encode(receipt)).flatMap { String(data: $0, encoding: .utf8) }
            }
        }
    }

    var validatedSyncedGradedQuoteReceipt: SyncedGradedQuoteReceipt? {
        syncedGradedQuoteReceipt.flatMap { $0.matches(self) ? $0 : nil }
    }

    var validatedWithdrawnGradedQuoteReceipt: SyncedGradedQuoteReceipt? {
        syncedGradedQuoteReceipt.flatMap { $0.matchesWithdrawal(self) ? $0 : nil }
    }

    /// Receipt provenance is usable only while every part of the observed
    /// quote still matches. Equal amounts alone cannot identify a quote.
    func isReceiptOfSyncedQuote(_ evidence: ExactGradedQuoteEvidence, record: PriceRecord) -> Bool {
        guard let receipt = validatedSyncedGradedQuoteReceipt else { return false }
        return receipt.evidence == evidence && receipt.sourceUpdatedAt == record.sourceUpdatedAt
            && matchesStoredExactQuoteValue(evidence, record: record)
    }

    func matchesStoredExactQuote(_ evidence: ExactGradedQuoteEvidence, record: PriceRecord) -> Bool {
        guard matchesStoredExactQuoteValue(evidence, record: record) else { return false }
        if let updatedAt = record.sourceUpdatedAt {
            return isSourceStamped && effectiveAt == updatedAt
        }
        return !isSourceStamped
    }

    func matchesStoredExactQuoteValue(_ evidence: ExactGradedQuoteEvidence, record: PriceRecord) -> Bool {
        guard record.marketVariantID == evidence.variantID,
              InventoryLedger.matchesExactGradedObservation(self, variantID: evidence.variantID, recordKey: record.key),
              source == record.source, currencyCode == record.currencyCode,
              sourceVariantID == record.sourceVariantID, marketVariantID == record.marketVariantID,
              amount == record.unitMarketPriceUSD.flatMap(Money.init(rounding:)) else { return false }
        return true
    }
}

/// A local receipt for a synced exact quote. Its value and observation-clock
/// snapshot prove the association even after the mutable PriceRecord is
/// replaced. A same-value provider update may advance sourceUpdatedAt without
/// rewriting the original observation's effectiveAt or receivedAt.
struct SyncedGradedQuoteReceipt: Codable, Equatable, Sendable {
    let version: Int
    let evidence: ExactGradedQuoteEvidence
    let learnedAt: Date
    let sourceUpdatedAt: Date?
    let instrumentKey: String
    let amountUSDTenThousandths: Int64?
    let currencyCode: String
    let sourceRaw: String
    let sourceVariantID: String?
    let marketVariantID: String?
    let observationEffectiveAt: Date
    let observationReceivedAt: Date
    let observationIsSourceStamped: Bool

    init(evidence: ExactGradedQuoteEvidence, learnedAt: Date, sourceUpdatedAt: Date?, observation: PriceObservation) {
        version = 1
        self.evidence = evidence
        self.learnedAt = learnedAt
        self.sourceUpdatedAt = sourceUpdatedAt
        instrumentKey = observation.instrumentKey
        amountUSDTenThousandths = observation.amountUSDTenThousandths
        currencyCode = observation.currencyCode
        sourceRaw = observation.sourceRaw
        sourceVariantID = observation.sourceVariantID
        marketVariantID = observation.marketVariantID
        observationEffectiveAt = observation.effectiveAt
        observationReceivedAt = observation.receivedAt
        observationIsSourceStamped = observation.isSourceStamped
    }

    func matches(_ observation: PriceObservation) -> Bool {
        version == 1 && learnedAt >= observation.receivedAt && learnedAt >= evidence.checkedAt
            && InventoryLedger.matchesExactGradedObservation(observation, variantID: evidence.variantID,
                                                             recordKey: instrumentKey)
            && observation.amountUSDTenThousandths == amountUSDTenThousandths
            && observation.currencyCode == currencyCode && observation.sourceRaw == sourceRaw
            && observation.sourceVariantID == sourceVariantID && observation.marketVariantID == marketVariantID
            && observation.effectiveAt == observationEffectiveAt && observation.receivedAt == observationReceivedAt
            && observation.isSourceStamped == observationIsSourceStamped
    }

    func matchesWithdrawal(_ observation: PriceObservation) -> Bool {
        guard version == 1, observation.kind == .eligibilityExpiry, observation.amount == nil,
              evidence.lifecycle.status == "current", let deadline = evidence.lifecycle.priceExpiresAt,
              deadline > learnedAt, observation.receivedAt == deadline, observation.effectiveAt == learnedAt,
              observation.instrumentKey == instrumentKey else { return false }
        return observation.currencyCode == currencyCode && observation.sourceRaw == sourceRaw
            && observation.sourceVariantID == sourceVariantID && observation.marketVariantID == marketVariantID
    }
}

/// The tuple that decides whether a new provider answer is worth a row.
///
/// Provenance is deliberately inside the identity. A vendor remapping a card
/// from one variant object to another that happens also to be worth $42 has
/// changed *what is being priced*, and a log whose whole job is to explain
/// where numbers came from has to say so — even though the dollar figure did
/// not move.
struct PriceObservationValue: Equatable, Sendable {
    var amount: Money?
    var currencyCode: String
    var sourceRaw: String
    var sourceVariantID: String?
    var marketVariantID: String?
}
