import Foundation

enum CardScannerExternalLinks {
    static var privacyPolicy: URL? {
        configuredURL(forInfoKey: "PrivacyPolicyURL", requiredPath: "/privacy")
    }

    static var support: URL? {
        configuredURL(forInfoKey: "SupportURL", requiredPath: "/support")
    }

    static func configuredURL(
        forInfoKey key: String,
        requiredPath: String? = nil,
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) -> URL? {
        guard let value = infoDictionary?[key] as? String,
              let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty,
              !host.localizedCaseInsensitiveContains("localhost"),
              !host.localizedCaseInsensitiveContains("example"),
              !host.contains("$"),
              requiredPath.map({ url.path == $0 }) ?? true else {
            return nil
        }
        return url
    }
}
