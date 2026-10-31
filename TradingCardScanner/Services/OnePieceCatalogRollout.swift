import Foundation

enum OnePieceCatalogRolloutMode: String, Sendable {
    case disabled
    case remoteValidationOnly = "remote-validation-only"
    case remoteAuthority = "remote-authority"

    static func from(rawValue: String?) -> Self {
        guard let rawValue else { return .disabled }
        return Self(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .disabled
    }

    static var configured: Self {
        from(rawValue: Bundle.main.object(forInfoDictionaryKey: "ONE_PIECE_CATALOG_ROLLOUT_MODE") as? String)
    }
}
