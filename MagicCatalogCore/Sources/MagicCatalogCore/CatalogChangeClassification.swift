import Foundation

public enum MagicCatalogChangeClass: String, Codable, Equatable, Sendable {
    case none
    case contentOnly
    case authority
    case newSet
    case unknown
}

public struct MagicCatalogSurfaceDiff: Equatable, Sendable {
    public let addedCodes: [String]
    public let changedCodes: [String]
    public let removedCodes: [String]
    public let scannerProjectionChangedCodes: [String]
    public let browseProjectionChangedCodes: [String]
    public let routingProjectionChangedCodes: [String]

    public init(
        addedCodes: [String],
        changedCodes: [String],
        removedCodes: [String],
        scannerProjectionChangedCodes: [String],
        browseProjectionChangedCodes: [String],
        routingProjectionChangedCodes: [String]
    ) {
        self.addedCodes = addedCodes
        self.changedCodes = changedCodes
        self.removedCodes = removedCodes
        self.scannerProjectionChangedCodes = scannerProjectionChangedCodes
        self.browseProjectionChangedCodes = browseProjectionChangedCodes
        self.routingProjectionChangedCodes = routingProjectionChangedCodes
    }
}

public struct MagicCatalogChangeClassification: Codable, Equatable, Sendable {
    public let changeClass: MagicCatalogChangeClass
    public let changedCodes: [String]
    public let contentChangedCodes: [String]
    public let authorityChangedCodes: [String]
    public let addedCodes: [String]
    public let removedCodes: [String]

    public init(
        changeClass: MagicCatalogChangeClass,
        changedCodes: [String],
        contentChangedCodes: [String],
        authorityChangedCodes: [String],
        addedCodes: [String],
        removedCodes: [String]
    ) {
        self.changeClass = changeClass
        self.changedCodes = changedCodes
        self.contentChangedCodes = contentChangedCodes
        self.authorityChangedCodes = authorityChangedCodes
        self.addedCodes = addedCodes
        self.removedCodes = removedCodes
    }
}

/// Shared, fail-closed semantic analysis for the Magic publication lanes.
public enum MagicCatalogChangeClassifier {
    /// This is intentionally an allow-list. Every descriptor field not named
    /// here, including a field added in a future release, is protected by
    /// default. Magic `cardCount` is Browse metadata only. Magic `printedSize`
    /// is the scanner denominator; do not treat `cardCount` like Pokémon
    /// `officialCount`.
    private static let automaticFieldNames: Set<String> = [
        "displayName",
        "releaseDate",
        "cardCount",
        "iconSVGURL"
    ]

    public static func surfaceDiff(
        previousRelease: MagicCatalogRelease?,
        currentRelease: MagicCatalogRelease
    ) -> MagicCatalogSurfaceDiff {
        let previousByCode = Dictionary(
            previousRelease?.sets.map {
                (MagicCatalogPolicy.normalizedCode($0.code), $0)
            } ?? [],
            uniquingKeysWith: { first, _ in first }
        )
        let currentByCode = Dictionary(
            currentRelease.sets.map {
                (MagicCatalogPolicy.normalizedCode($0.code), $0)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let allCodes = Set(previousByCode.keys).union(currentByCode.keys)

        var addedCodes: [String] = []
        var changedCodes: [String] = []
        var removedCodes: [String] = []
        var scannerProjectionChangedCodes: [String] = []
        var browseProjectionChangedCodes: [String] = []
        var routingProjectionChangedCodes: [String] = []

        for code in allCodes.sorted() {
            switch (previousByCode[code], currentByCode[code]) {
            case (nil, let current?):
                let displayCode = canonicalDisplayCode(current)
                addedCodes.append(displayCode)
                if current.scanEnabled {
                    scannerProjectionChangedCodes.append(displayCode)
                }
                if current.browseEnabled {
                    browseProjectionChangedCodes.append(displayCode)
                }
                if current.routingKind != nil {
                    routingProjectionChangedCodes.append(displayCode)
                }
            case (let previous?, nil):
                let displayCode = canonicalDisplayCode(previous)
                removedCodes.append(displayCode)
                if previous.scanEnabled {
                    scannerProjectionChangedCodes.append(displayCode)
                }
                if previous.browseEnabled {
                    browseProjectionChangedCodes.append(displayCode)
                }
                if previous.routingKind != nil {
                    routingProjectionChangedCodes.append(displayCode)
                }
            case (let previous?, let current?):
                let displayCode = canonicalDisplayCode(current)
                if previous != current {
                    changedCodes.append(displayCode)
                }
                if previous.scanEnabled != current.scanEnabled
                    || previous.printedSize != current.printedSize {
                    scannerProjectionChangedCodes.append(displayCode)
                }
                if previous.displayName != current.displayName
                    || previous.releaseDate != current.releaseDate
                    || previous.cardCount != current.cardCount
                    || previous.iconSVGURL != current.iconSVGURL
                    || previous.browseEnabled != current.browseEnabled {
                    browseProjectionChangedCodes.append(displayCode)
                }
                if previous.parentSetCode != current.parentSetCode
                    || previous.routingKind != current.routingKind {
                    routingProjectionChangedCodes.append(displayCode)
                }
            default:
                break
            }
        }

        return MagicCatalogSurfaceDiff(
            addedCodes: sortedUnique(addedCodes),
            changedCodes: sortedUnique(changedCodes),
            removedCodes: sortedUnique(removedCodes),
            scannerProjectionChangedCodes: sortedUnique(scannerProjectionChangedCodes),
            browseProjectionChangedCodes: sortedUnique(browseProjectionChangedCodes),
            routingProjectionChangedCodes: sortedUnique(routingProjectionChangedCodes)
        )
    }

    public static func classify(
        previous: MagicCatalogSetDescriptor?,
        current: MagicCatalogSetDescriptor
    ) -> MagicCatalogChangeClass {
        guard let previous else { return .newSet }
        guard previous != current else { return .none }
        guard let changedFields = changedFieldNames(previous, current),
              !changedFields.isEmpty else {
            return .unknown
        }
        return changedFields.isSubset(of: automaticFieldNames) ? .contentOnly : .authority
    }

    public static func classify(
        previousRelease: MagicCatalogRelease?,
        currentRelease: MagicCatalogRelease
    ) -> MagicCatalogChangeClassification {
        let diff = surfaceDiff(
            previousRelease: previousRelease,
            currentRelease: currentRelease
        )
        return classify(
            previousRelease: previousRelease,
            currentRelease: currentRelease,
            surfaceDiff: diff
        )
    }

    public static func classify(
        previousRelease: MagicCatalogRelease?,
        currentRelease: MagicCatalogRelease,
        surfaceDiff: MagicCatalogSurfaceDiff
    ) -> MagicCatalogChangeClassification {
        let previousByCode = Dictionary(
            previousRelease?.sets.map {
                (MagicCatalogPolicy.normalizedCode($0.code), $0)
            } ?? [],
            uniquingKeysWith: { first, _ in first }
        )
        let currentByCode = Dictionary(
            currentRelease.sets.map {
                (MagicCatalogPolicy.normalizedCode($0.code), $0)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var changedCodes: [String] = []
        var contentChangedCodes: [String] = []
        var authorityChangedCodes: [String] = []
        var classes: [MagicCatalogChangeClass] = []

        for code in Set(previousByCode.keys).union(currentByCode.keys).sorted() {
            switch (previousByCode[code], currentByCode[code]) {
            case (nil, let current?):
                classes.append(.newSet)
                _ = current
            case (let previous?, nil):
                classes.append(.authority)
                _ = previous
            case (let previous?, let current?):
                let descriptorClass = classify(previous: previous, current: current)
                classes.append(descriptorClass)
                switch descriptorClass {
                case .none:
                    break
                case .contentOnly:
                    changedCodes.append(canonicalDisplayCode(current))
                    contentChangedCodes.append(canonicalDisplayCode(current))
                case .authority:
                    changedCodes.append(canonicalDisplayCode(current))
                    authorityChangedCodes.append(canonicalDisplayCode(current))
                case .unknown:
                    changedCodes.append(canonicalDisplayCode(current))
                    // Unknown differences are diagnostic authority changes so
                    // they cannot remain in the automatic content bucket.
                    authorityChangedCodes.append(canonicalDisplayCode(current))
                case .newSet:
                    // A previous descriptor is present, so this is defensive
                    // exhaustivity for a future classifier change.
                    changedCodes.append(canonicalDisplayCode(current))
                    authorityChangedCodes.append(canonicalDisplayCode(current))
                }
            default:
                break
            }
        }

        let provisionalClass: MagicCatalogChangeClass
        if classes.contains(.unknown) {
            provisionalClass = .unknown
        } else if classes.contains(.newSet) {
            provisionalClass = .newSet
        } else if !surfaceDiff.removedCodes.isEmpty {
            provisionalClass = .authority
        } else if classes.contains(.authority) {
            provisionalClass = .authority
        } else if classes.contains(.contentOnly) {
            provisionalClass = .contentOnly
        } else {
            provisionalClass = .none
        }

        var changeClass = provisionalClass
        if provisionalClass == .contentOnly,
           (
               !surfaceDiff.scannerProjectionChangedCodes.isEmpty
                   || !surfaceDiff.routingProjectionChangedCodes.isEmpty
                   || Set(surfaceDiff.browseProjectionChangedCodes)
                       != Set(contentChangedCodes)
           ) {
            let invariantAffectedCodes = changedCodes
                + contentChangedCodes
                + surfaceDiff.scannerProjectionChangedCodes
                + surfaceDiff.browseProjectionChangedCodes
                + surfaceDiff.routingProjectionChangedCodes
            changeClass = .unknown
            contentChangedCodes = []
            authorityChangedCodes = sortedUnique(invariantAffectedCodes)
        }

        return MagicCatalogChangeClassification(
            changeClass: changeClass,
            changedCodes: sortedUnique(changedCodes),
            contentChangedCodes: sortedUnique(contentChangedCodes),
            authorityChangedCodes: sortedUnique(authorityChangedCodes),
            addedCodes: surfaceDiff.addedCodes.sorted(),
            removedCodes: surfaceDiff.removedCodes.sorted()
        )
    }

    private static func changedFieldNames(
        _ previous: MagicCatalogSetDescriptor,
        _ current: MagicCatalogSetDescriptor
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
        _ descriptor: MagicCatalogSetDescriptor
    ) -> [String: Any]? {
        guard let encoded = try? MagicCatalogJSON.encode(descriptor),
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

    private static func canonicalDisplayCode(
        _ descriptor: MagicCatalogSetDescriptor
    ) -> String {
        MagicCatalogPolicy.displayCode(descriptor.code)
    }

    private static func sortedUnique(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }
}
