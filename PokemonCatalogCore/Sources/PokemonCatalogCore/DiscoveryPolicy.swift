import Foundation

/// Scheduled discovery policy for the publisher. The historical ID list is a
/// migration snapshot of provider metadata, not a recurring per-set release
/// checklist. IDs outside the list are still inspected by their detailed
/// release date before they can become candidates.
public struct PokemonCatalogDiscoveryPolicy: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let automaticDiscoveryStartDate: String
    public let ignoredHistoricalProviderSetIDs: [String]

    public init(
        schemaVersion: Int = 1,
        automaticDiscoveryStartDate: String,
        ignoredHistoricalProviderSetIDs: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.automaticDiscoveryStartDate = automaticDiscoveryStartDate
        self.ignoredHistoricalProviderSetIDs = ignoredHistoricalProviderSetIDs
    }

    public var ignoredHistoricalIDs: Set<String> {
        Set(ignoredHistoricalProviderSetIDs.map { $0.lowercased() })
    }
}
