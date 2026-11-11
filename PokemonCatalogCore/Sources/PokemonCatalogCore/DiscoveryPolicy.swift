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

    /// Gives the scheduled publication job two days for provider ingestion and
    /// a normal approval cycle before it flags a released set for attention.
    public func overduePublicationIDs(
        releaseDates: [String: Date],
        publishedProviderSetIDs: Set<String>,
        discoveryBoundary: Date,
        checkedAt: Date
    ) -> [String] {
        let ignoredIDs = ignoredHistoricalIDs
        let publishedIDs = Set(publishedProviderSetIDs.map { $0.lowercased() })
        let cutoff = checkedAt.addingTimeInterval(-48 * 60 * 60)
        return Set(releaseDates.compactMap { id, date -> String? in
            let key = id.lowercased()
            guard date >= discoveryBoundary, date <= cutoff,
                  !ignoredIDs.contains(key), !publishedIDs.contains(key) else { return nil }
            return key
        }).sorted()
    }
}
