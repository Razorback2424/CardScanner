import Foundation

enum MagicCatalogRolloutMode: String, Equatable, Sendable {
    case legacyLive = "legacy-live"
    case remoteValidationOnly = "remote-validation-only"
    case remoteAuthority = "remote-authority"

    static let infoPlistKey = "MAGIC_CATALOG_ROLLOUT_MODE"

    static var configured: Self {
        from(rawValue: Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String)
    }

    static func from(rawValue: String?) -> Self {
        guard let rawValue else { return .legacyLive }
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        return Self(rawValue: normalized) ?? .legacyLive
    }
}

enum MagicCatalogParitySurface: String, CaseIterable, Sendable {
    case scanner
    case browse
    case routing
}

struct MagicCatalogParityMismatch: Equatable, Sendable {
    let surface: MagicCatalogParitySurface
    let details: String
}
