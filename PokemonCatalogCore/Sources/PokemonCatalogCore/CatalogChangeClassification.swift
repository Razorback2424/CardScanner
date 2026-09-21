import Foundation

public enum PokemonCatalogChangeClass: String, Codable, Equatable, Sendable {
    case none
    case contentOnly
    case baselineMigration
    case authority
    case newSet
    case unknown
}

public struct PokemonCatalogChangeClassification: Codable, Equatable, Sendable {
    public let changeClass: PokemonCatalogChangeClass
    public let changedProviderSetIDs: [String]
    public let contentChangedProviderSetIDs: [String]
    public let authorityChangedProviderSetIDs: [String]
    public let baselineFingerprintProviderSetIDs: [String]
    public let addedProviderSetIDs: [String]

    public init(
        changeClass: PokemonCatalogChangeClass,
        changedProviderSetIDs: [String],
        contentChangedProviderSetIDs: [String],
        authorityChangedProviderSetIDs: [String],
        baselineFingerprintProviderSetIDs: [String],
        addedProviderSetIDs: [String]
    ) {
        self.changeClass = changeClass
        self.changedProviderSetIDs = changedProviderSetIDs
        self.contentChangedProviderSetIDs = contentChangedProviderSetIDs
        self.authorityChangedProviderSetIDs = authorityChangedProviderSetIDs
        self.baselineFingerprintProviderSetIDs = baselineFingerprintProviderSetIDs
        self.addedProviderSetIDs = addedProviderSetIDs
    }
}

/// Fail-closed semantic diffing for the publication lane. The allow-list is
/// intentionally written out instead of treating “not authority” as safe.
public enum PokemonCatalogChangeClassifier {
    /// Only these descriptor fields may use the reviewer-free publication lane.
    /// Every other field, including one added in a future release, is protected
    /// by default.
    private static let automaticFieldNames: Set<String> = [
        "providerFingerprint", "displayName", "releaseDate", "logoURL", "symbolURL",
        "artworkFallbackURLs"
    ]

    public static func classify(
        previous: PokemonCatalogSetDescriptor?,
        current: PokemonCatalogSetDescriptor
    ) -> PokemonCatalogChangeClass {
        guard let previous else { return .newSet }
        guard previous != current else { return .none }
        guard let changedFields = changedFieldNames(previous, current),
              !changedFields.isEmpty else {
            return .authority
        }

        // Removing a signed target is never an automatic content update.
        if previous.providerFingerprint != nil, current.providerFingerprint == nil {
            return .authority
        }

        // An initial fingerprint is a protected baseline migration, even
        // though the field itself is in the normal content allow-list.
        let isBaselineMigration = previous.providerFingerprint == nil
            && current.providerFingerprint != nil

        guard changedFields.isSubset(of: automaticFieldNames) else {
            return .authority
        }
        return isBaselineMigration ? .baselineMigration : .contentOnly
    }

    public static func classify(
        previousRelease: PokemonCatalogRelease?,
        currentRelease: PokemonCatalogRelease
    ) -> PokemonCatalogChangeClassification {
        let previousByID = Dictionary(
            uniqueKeysWithValues: (previousRelease?.sets ?? []).map {
                ($0.providerSetID.lowercased(), $0)
            }
        )
        var changed: [String] = []
        var content: [String] = []
        var authority: [String] = []
        var baseline: [String] = []
        var added: [String] = []
        var classes: [PokemonCatalogChangeClass] = []

        for descriptor in currentRelease.sets {
            let id = descriptor.providerSetID.lowercased()
            let change = classify(previous: previousByID[id], current: descriptor)
            classes.append(change)
            switch change {
            case .none:
                break
            case .newSet:
                added.append(id)
            case .contentOnly:
                changed.append(id)
                content.append(id)
            case .baselineMigration:
                changed.append(id)
                baseline.append(id)
            case .authority:
                changed.append(id)
                authority.append(id)
            case .unknown:
                changed.append(id)
                authority.append(id)
            }
        }

        let overall: PokemonCatalogChangeClass
        if classes.contains(.unknown) {
            overall = .unknown
        } else if !added.isEmpty {
            overall = .newSet
        } else if classes.contains(.authority) {
            overall = .authority
        } else if classes.contains(.baselineMigration) {
            overall = .baselineMigration
        } else if classes.contains(.contentOnly) {
            overall = .contentOnly
        } else {
            overall = .none
        }

        return PokemonCatalogChangeClassification(
            changeClass: overall,
            changedProviderSetIDs: changed.sorted(),
            contentChangedProviderSetIDs: content.sorted(),
            authorityChangedProviderSetIDs: authority.sorted(),
            baselineFingerprintProviderSetIDs: baseline.sorted(),
            addedProviderSetIDs: added.sorted()
        )
    }

    private static func changedFieldNames(
        _ previous: PokemonCatalogSetDescriptor,
        _ current: PokemonCatalogSetDescriptor
    ) -> Set<String>? {
        guard let oldObject = descriptorJSONObject(previous),
              let newObject = descriptorJSONObject(current) else {
            return nil
        }

        var changed = Set<String>()
        let keys = Set(oldObject.keys).union(newObject.keys)
        for key in keys {
            let oldValue = oldObject[key]
            let newValue = newObject[key]
            if oldValue == nil && newValue == nil {
                continue
            }
            if oldValue == nil || newValue == nil {
                changed.insert(key)
                continue
            }
            guard let oldData = canonicalFieldData(oldValue, key: key),
                  let newData = canonicalFieldData(newValue, key: key) else {
                return nil
            }
            if oldData != newData {
                changed.insert(key)
            }
        }
        return changed
    }

    private static func descriptorJSONObject(
        _ descriptor: PokemonCatalogSetDescriptor
    ) -> [String: Any]? {
        guard let encoded = try? PokemonCatalogJSON.encode(descriptor),
              let object = try? JSONSerialization.jsonObject(with: encoded),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private static func canonicalFieldData(_ value: Any?, key: String) -> Data? {
        guard let value else { return nil }
        return try? JSONSerialization.data(
            withJSONObject: [key: value],
            options: [.sortedKeys]
        )
    }
}
