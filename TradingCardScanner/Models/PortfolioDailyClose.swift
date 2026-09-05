import Foundation
import SwiftData

/// Why a published close was rewritten.
///
/// The two are deliberately not equivalent. Ownership being incomplete is a
/// reconciliation the close *should* absorb; market information arriving late
/// is not, and never rewrites a day that has already been published.
enum PortfolioRevisionReason: String, Codable, Hashable, Sendable {
    /// Another device synced an event that genuinely occurred before the
    /// cutoff. The day's ownership was incomplete when it was first computed.
    case lateInventoryTruth
    /// Recomputed for a reason that is not a correction of the record — a
    /// backfill, a repaired price key.
    case recomputed
}

/// How much of the collection the app actually managed to reprice on a day.
enum PortfolioCoverageState: String, Codable, Hashable, Sendable {
    /// Every held instrument had a successful check that day.
    case complete
    /// Some did not, and their previous value carried forward.
    case partial
    /// The day predates the ledger, so there is no evidence either way. Said
    /// out loud rather than presented as completeness.
    case unknown
}

/// One published daily close.
///
/// Local-only and revisioned. A close is a *derived* fact, and two devices with
/// different refresh histories legitimately derive different ones until there
/// is a shared pricing service — so this table records what this device could
/// honestly conclude, and keeps every earlier conclusion alongside it.
///
/// Revisions are additive: revision 1 is retained, the latest revision
/// displays, and the audit trail survives. A close that could be silently
/// overwritten would be worth exactly as much as the number it replaced.
@Model
final class PortfolioDailyClose {
    /// The day being closed — `startOfDay` in `timeZoneIdentifier`.
    var date: Date = Date.now
    var revision: Int = 1
    /// Stamped, not looked up. The zone the boundary was measured in is part of
    /// what the number means.
    var timeZoneIdentifier: String = TimeZone.current.identifier

    var closeValueTenThousandths: Int64 = 0
    var marketContributionTenThousandths: Int64 = 0
    var flowContributionTenThousandths: Int64 = 0
    /// Added after the original close schema, so old rows may have no
    /// side-specific values. Those rows fall back to the sign of `flow` until
    /// a replay republishes an exact attribution.
    var addedContributionTenThousandths: Int64?
    var removedContributionTenThousandths: Int64?
    var correctionContributionTenThousandths: Int64 = 0
    var newlyAddedValueTenThousandths: Int64 = 0
    var pricingAdjustmentTenThousandths: Int64 = 0
    var carriedForwardValueTenThousandths: Int64 = 0

    var coverageStateRaw: String = PortfolioCoverageState.unknown.rawValue
    var refreshedInstrumentCount: Int = 0
    var carriedForwardInstrumentCount: Int = 0
    var pricedPositionCount: Int = 0
    /// Positions held but absent from the total — unpriced, or priced in a
    /// currency with no rate to convert at.
    var excludedCount: Int = 0

    /// What the inputs looked like when this revision was computed. A changed
    /// fingerprint is what makes a revision necessary; an unchanged one is what
    /// makes recomputation free.
    var inputsFingerprint: String = ""
    var revisionReasonRaw: String?
    var computedAt: Date = Date.now

    init(
        date: Date,
        revision: Int,
        timeZoneIdentifier: String,
        closeValue: Money,
        market: Money,
        flow: Money,
        corrections: Money,
        newlyAddedValue: Money = .zero,
        pricingAdjustment: Money,
        carriedForwardValue: Money,
        coverage: PortfolioCoverageState,
        refreshedInstrumentCount: Int,
        carriedForwardInstrumentCount: Int,
        pricedPositionCount: Int,
        excludedCount: Int,
        inputsFingerprint: String,
        revisionReason: PortfolioRevisionReason?,
        computedAt: Date = .now,
        added: Money? = nil,
        removed: Money? = nil
    ) {
        self.date = date
        self.revision = revision
        self.timeZoneIdentifier = timeZoneIdentifier
        self.closeValueTenThousandths = closeValue.tenThousandths
        self.marketContributionTenThousandths = market.tenThousandths
        self.flowContributionTenThousandths = flow.tenThousandths
        self.addedContributionTenThousandths = added?.tenThousandths
        self.removedContributionTenThousandths = removed?.tenThousandths
        self.correctionContributionTenThousandths = corrections.tenThousandths
        self.newlyAddedValueTenThousandths = newlyAddedValue.tenThousandths
        self.pricingAdjustmentTenThousandths = pricingAdjustment.tenThousandths
        self.carriedForwardValueTenThousandths = carriedForwardValue.tenThousandths
        self.coverageStateRaw = coverage.rawValue
        self.refreshedInstrumentCount = refreshedInstrumentCount
        self.carriedForwardInstrumentCount = carriedForwardInstrumentCount
        self.pricedPositionCount = pricedPositionCount
        self.excludedCount = excludedCount
        self.inputsFingerprint = inputsFingerprint
        self.revisionReasonRaw = revisionReason?.rawValue
        self.computedAt = computedAt
    }

    var closeValue: Money { Money(tenThousandths: closeValueTenThousandths) }
    var marketContribution: Money { Money(tenThousandths: marketContributionTenThousandths) }
    var flowContribution: Money { Money(tenThousandths: flowContributionTenThousandths) }
    var addedContribution: Money {
        Money(tenThousandths: addedContributionTenThousandths ?? max(0, flowContributionTenThousandths))
    }
    var removedContribution: Money {
        Money(tenThousandths: removedContributionTenThousandths ?? max(0, -flowContributionTenThousandths))
    }
    var correctionContribution: Money { Money(tenThousandths: correctionContributionTenThousandths) }
    var newlyAddedValue: Money { Money(tenThousandths: newlyAddedValueTenThousandths) }
    var pricingAdjustment: Money { Money(tenThousandths: pricingAdjustmentTenThousandths) }
    var carriedForwardValue: Money { Money(tenThousandths: carriedForwardValueTenThousandths) }

    var coverageState: PortfolioCoverageState {
        PortfolioCoverageState(rawValue: coverageStateRaw) ?? .unknown
    }

    var revisionReason: PortfolioRevisionReason? {
        revisionReasonRaw.flatMap(PortfolioRevisionReason.init(rawValue:))
    }

    /// The sentence shown under a revised close — "reconciled after another
    /// device synced". A close that changed has to say why, or the next number
    /// the user sees is one they have no reason to believe.
    var revisionNote: String? {
        guard revision > 1, let revisionReason else { return nil }
        switch revisionReason {
        case .lateInventoryTruth:
            return "reconciled after another device synced"
        case .recomputed:
            return "recomputed from corrected inputs"
        }
    }
}
