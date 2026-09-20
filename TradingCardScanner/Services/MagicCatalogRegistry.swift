import Foundation
import MagicCatalogCore

/// The three runtime projections of one verified Magic release.
///
/// `scannerDefinitions`, `browseSets`, and `childSetsByParentCode` are built
/// together and are never independently refreshed. This is the app-side form
/// of the Magic authority invariant: one signed descriptor set feeds all three
/// consumers, while Scryfall remains a live card-level source.
struct MagicCatalogRegistry: Sendable {
    let revision: Int
    let descriptors: [MagicCatalogSetDescriptor]
    let scannerDefinitions: [MagicSetDefinition]
    let browseSets: [CatalogSet]
    let childSetsByParentCode: [String: [MagicCatalogSetDescriptor]]

    private let byCode: [String: MagicCatalogSetDescriptor]

    init(release: MagicCatalogRelease) {
        self.revision = release.revision
        self.descriptors = release.sets

        var codeMap: [String: MagicCatalogSetDescriptor] = [:]
        var scanner: [MagicSetDefinition] = []
        var children: [String: [MagicCatalogSetDescriptor]] = [:]
        for descriptor in release.sets {
            let code = MagicCatalogCore.MagicCatalogReleaseValidator.normalizedCode(descriptor.code)
            codeMap[code] = descriptor
            if descriptor.scanEnabled {
                scanner.append(
                    MagicSetDefinition(code: descriptor.code.uppercased(), printedSize: descriptor.printedSize)
                )
            }
            if let routingKind = descriptor.routingKind,
               let parent = descriptor.parentSetCode {
                _ = routingKind
                children[MagicCatalogCore.MagicCatalogReleaseValidator.normalizedCode(parent), default: []]
                    .append(descriptor)
            }
        }

        self.byCode = codeMap
        self.scannerDefinitions = scanner.sorted { $0.code < $1.code }
        let visible = release.sets
            .filter(\.browseEnabled)
            .sorted { lhs, rhs in
                if lhs.releaseDate != rhs.releaseDate {
                    switch (lhs.releaseDate, rhs.releaseDate) {
                    case let (left?, right?): return left > right
                    case (.some, nil): return true
                    case (nil, .some): return false
                    default: break
                    }
                }
                return MagicCatalogCore.MagicCatalogReleaseValidator.normalizedCode(lhs.code)
                    < MagicCatalogCore.MagicCatalogReleaseValidator.normalizedCode(rhs.code)
            }
        self.browseSets = visible.enumerated().map { index, descriptor in
            CatalogSet(
                catalogID: CatalogSetID(
                    game: .magic,
                    providerID: descriptor.code.lowercased()
                ),
                name: descriptor.displayName,
                code: descriptor.code.uppercased(),
                logoURL: descriptor.iconSVGURL,
                symbolURL: descriptor.iconSVGURL,
                cardCount: descriptor.cardCount,
                releaseDate: descriptor.releaseDate.flatMap(MagicCatalogDate.parseDay),
                sortRank: visible.count - index
            )
        }
        self.childSetsByParentCode = children.mapValues { values in
            values.sorted { $0.code < $1.code }
        }
    }

    func descriptor(forCode code: String) -> MagicCatalogSetDescriptor? {
        byCode[MagicCatalogCore.MagicCatalogReleaseValidator.normalizedCode(code)]
    }

    func child(
        for kind: MagicContentKind,
        parentCode: String
    ) -> MagicCatalogSetDescriptor? {
        let candidates = (childSetsByParentCode[
            MagicCatalogCore.MagicCatalogReleaseValidator.normalizedCode(parentCode)
        ] ?? []).filter {
            switch (kind, $0.routingKind) {
            case (.token, .token), (.artCard, .artCard): return true
            default: return false
            }
        }
        guard candidates.count > 1 else { return candidates.first }
        return candidates.first {
            $0.code.caseInsensitiveCompare("T" + parentCode.uppercased()) == .orderedSame
        }
    }

    func legacyParityMismatches(
        scanner: [MagicSetDefinition],
        browse: [CatalogSet],
        routing: [String: [MagicChildSet]]
    ) -> [MagicCatalogParityMismatch] {
        var mismatches: [MagicCatalogParityMismatch] = []
        let expectedScanner = Dictionary(
            scannerDefinitions.map { ($0.code.lowercased(), $0.printedSize) },
            uniquingKeysWith: { first, _ in first }
        )
        let actualScanner = Dictionary(
            scanner.map { ($0.code.lowercased(), $0.printedSize) },
            uniquingKeysWith: { first, _ in first }
        )
        if expectedScanner != actualScanner {
            mismatches.append(.init(surface: .scanner, details: "scanner code/printedSize projection differs"))
        }

        let expectedBrowse = Set(self.browseSets)
        let actualBrowse = Set(browse)
        if expectedBrowse != actualBrowse {
            mismatches.append(.init(surface: .browse, details: "Browse set directory differs"))
        }

        let expectedRouting: Set<String> = Set(
            childSetsByParentCode.flatMap { entry -> [String] in
                let (parent, children) = entry
                return children.compactMap { child in
                    guard let kind = child.routingKind else { return nil }
                    return "\(parent)|\(child.code.lowercased())|\(kind.rawValue)"
                }
            }
        )
        let actualRouting = Set(routing.flatMap { parent, children in
            children.map { "\(parent.lowercased())|\($0.code.lowercased())|\($0.contentKind == .artCard ? "artCard" : "token")" }
        })
        if expectedRouting != actualRouting {
            mismatches.append(.init(surface: .routing, details: "token/art child routing differs"))
        }
        return mismatches
    }

    static let bundledSeed: MagicCatalogRegistry = {
        let bundles = [
            Bundle.main,
            Bundle(for: MagicCatalogResourceLocator.self)
        ]
        for bundle in bundles {
            guard let url = bundle.url(
                forResource: "catalog",
                withExtension: "json",
                subdirectory: "MagicCatalogSeed"
            ), let data = try? Data(contentsOf: url),
                  let release = try? MagicCatalogJSON.decode(MagicCatalogRelease.self, from: data),
                  (try? MagicCatalogCore.MagicCatalogReleaseValidator.validate(release)) != nil else {
                continue
            }
            return MagicCatalogRegistry(release: release)
        }
        fatalError("MagicCatalogSeed/catalog.json is missing or invalid")
    }()
}

private final class MagicCatalogResourceLocator: NSObject {}
