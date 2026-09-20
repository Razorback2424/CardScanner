import Foundation

/// Provider policy is deliberately split into three independent decisions.
/// Browse membership, OCR vocabulary, and child-set routing have different
/// safety boundaries and must not collapse into one boolean.
public enum MagicCatalogPolicy {
    public static let modernFooterStart = "2014-07-18"

    public static let browseExcludedSetTypes: Set<String> = [
        "token", "memorabilia", "minigame", "art_series"
    ]

    public static func normalizedCode(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func displayCode(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public static func isBrowseEligible(_ set: MagicCatalogProviderSet) -> Bool {
        !set.digital && !browseExcludedSetTypes.contains(set.setType.lowercased())
    }

    public static func isScannerEligible(_ set: MagicCatalogProviderSet) -> Bool {
        guard isBrowseEligible(set),
              let releasedAt = set.releasedAt,
              releasedAt >= modernFooterStart else {
            return false
        }
        let code = displayCode(set.code)
        return (3...4).contains(code.count)
            && code.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) })
    }

    public static func routingKind(
        for set: MagicCatalogProviderSet
    ) -> MagicCatalogRoutingKind? {
        guard !set.digital else { return nil }
        switch set.setType.lowercased() {
        case "token":
            return .token
        case "memorabilia" where set.name.localizedCaseInsensitiveContains("Art Series"):
            return .artCard
        default:
            return nil
        }
    }

    public static func releaseSort(
        _ lhs: MagicCatalogSetDescriptor,
        _ rhs: MagicCatalogSetDescriptor
    ) -> Bool {
        switch (lhs.releaseDate, rhs.releaseDate) {
        case let (left?, right?) where left != right:
            return left > right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            return MagicCatalogCoreContractNormalizedCode(lhs.code)
                < MagicCatalogCoreContractNormalizedCode(rhs.code)
        }
    }

    private static func MagicCatalogCoreContractNormalizedCode(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
