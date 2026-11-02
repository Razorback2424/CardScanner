import Foundation

enum OwnedPriceRetentionReason: Equatable, Sendable {
    case olderSourceDate(PriceSource, Date)
    case missingSourceDate(PriceSource)
    case laterReceipt
    case invalidated
    case unavailable

    var caption: String {
        switch self {
        case let .olderSourceDate(source, date):
            return "Checked \(source.label); its price data (as of \(date.formatted(date: .abbreviated, time: .shortened))) is older than the saved price"
        case let .missingSourceDate(source):
            return "Checked \(source.label); its quote has no source date. Keeping the saved price"
        case .laterReceipt:
            return "Keeping the more recently received price"
        case .invalidated:
            return "This quote predates the price correction"
        case .unavailable:
            return "No newer quote available"
        }
    }
}

struct OwnedPriceReconciliation: Equatable, Sendable {
    let selectedKey: String
    let display: PriceDisplay
    let retainedReason: OwnedPriceRetentionReason?
}

/// The same value snapshot used by Collection, reduced only for catalog slots
/// that can match more than one local entry. Never merges their identities.
struct OwnedCatalogPrice: Equatable, Sendable {
    let entries: [CatalogOwnershipCardSnapshot]
    let display: PriceDisplay
    let entriesDisagree: Bool

    init(rows: [CatalogOwnershipCardSnapshot]) {
        entries = rows.filter { $0.itemKind == .rawCard }.sorted { $0.collectionKey < $1.collectionKey }
        let valued = entries.filter { $0.selectedPrice.amount != nil }
        display = valued.max {
            ($0.selectedPrice.effectiveAsOf ?? .distantPast) < ($1.selectedPrice.effectiveAsOf ?? .distantPast)
        }?.selectedPrice ?? entries.first?.selectedPrice ?? .unknown
        if let first = entries.first {
            entriesDisagree = !entries.allSatisfy {
                $0.selectedPriceKey == first.selectedPriceKey
                    || ($0.selectedPrice.amount == first.selectedPrice.amount
                        && $0.selectedPrice.effectiveAsOf == first.selectedPrice.effectiveAsOf)
            }
        } else { entriesDisagree = false }
    }

    func reconcilableEntries(variant: PhysicalVariant, treatmentIDs: [String]) -> [CatalogOwnershipCardSnapshot] {
        let treatments = MagicTreatmentKeyCodec.storedIDs(from: treatmentIDs)
        return entries.filter {
            $0.variantID == variant.id
                && MagicTreatmentKeyCodec.storedIDs(from: $0.magicTreatmentIDsRaw) == treatments
        }
    }

    static func displayPrices(
        for cards: [CatalogCardSummary], catalogPrices: [String: Double], ownership: CatalogOwnershipIndex
    ) -> [String: Double] {
        var prices = catalogPrices
        for card in cards {
            let owned = Self(rows: ownership.matchingRows(for: card))
            if !owned.entries.isEmpty { prices[card.id] = owned.display.amount }
        }
        return prices
    }
}
