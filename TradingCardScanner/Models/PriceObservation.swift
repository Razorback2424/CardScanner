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
    /// to have been attached to the wrong market variant. The only thing that
    /// can remove a value.
    case explicitInvalidation
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
    var id: UUID = UUID()
    /// Matches `PriceRecord.key` — game, printing and physical variant. One
    /// observation values every copy owned of that exact object.
    var instrumentKey: String = ""
    var kindRaw: String = ""

    /// `nil` has exactly one meaning in this table: an `explicitInvalidation`
    /// withdrawing a value. It never means "the provider was unreachable" and
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

    init(
        instrumentKey: String,
        kind: PriceObservationKind,
        amount: Money?,
        currencyCode: String = "USD",
        source: PriceSource,
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
        self.sourceRaw = source.rawValue
        self.sourceVariantID = sourceVariantID
        self.marketVariantID = marketVariantID
        self.effectiveAt = effectiveAt
        self.receivedAt = receivedAt
        self.isSourceStamped = isSourceStamped
    }

    var kind: PriceObservationKind {
        PriceObservationKind(rawValue: kindRaw) ?? .marketUpdate
    }

    var source: PriceSource? { PriceSource(rawValue: sourceRaw) }

    var amount: Money? {
        amountUSDTenThousandths.map(Money.init(tenThousandths:))
    }

    /// A pre-Slice-6 generic provider amount can already be present in the
    /// append-only log under a treatment-qualified price key. Keep that history
    /// for diagnostics, but do not let it value the portfolio. Imported CSV is
    /// the only current source with an explicit treatment claim.
    var effectiveUSDAmount: Money? {
        guard currencyCode == "USD" else { return nil }
        if MagicTreatmentKeyCodec.containsPriceTreatmentSuffix(in: instrumentKey),
           source?.isProvenForMagicTreatment != true {
            return nil
        }
        return amount
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
