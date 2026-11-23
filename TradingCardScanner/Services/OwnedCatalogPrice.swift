import Foundation

enum OwnedPriceRecheckPolicy {
    static let interval = PriceRefreshController.automaticRefreshInterval

    static func needsForcedRefresh(
        _ entries: [CatalogOwnershipCardSnapshot], lastForcedAt: Date?, now: Date
    ) -> Bool {
        entries.contains { entry in
            guard entry.selectedPrice.state(now: now) == .stale else { return false }
            let lastCheck = [entry.selectedPrice.lastCheckedAt, lastForcedAt]
                .compactMap { $0 }.filter { $0 <= now }.max()
            return lastCheck.map { now.timeIntervalSince($0) >= interval } ?? true
        }
    }
}

enum OwnedPriceRetentionReason: Equatable, Sendable {
    case olderSourceDate(PriceSource, Date)
    case missingSourceDate(PriceSource)
    case laterReceipt
    case invalidated
    case unavailable

    var caption: String {
        switch self {
        case let .olderSourceDate(source, date):
            return String(localized: "Keeping your saved price. The price from \(source.label) is older (\(date.formatted(date: .abbreviated, time: .shortened))).")
        case let .missingSourceDate(source):
            return String(localized: "Keeping your saved price. \(source.label) didn’t say when its price was last updated.")
        case .laterReceipt:
            return String(localized: "Keeping your saved price because we received it more recently.")
        case .invalidated:
            return String(localized: "The price we found is from before the correction.")
        case .unavailable:
            return String(localized: "Keeping your saved price. We didn’t find a newer price.")
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
