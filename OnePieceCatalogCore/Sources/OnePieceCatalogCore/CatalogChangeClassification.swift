import Foundation

public enum OnePieceCatalogChangeClass: String, Codable, Sendable {
    case none, contentOnly, protectedReview
}

public struct OnePieceCatalogChangeClassification: Codable, Equatable, Sendable {
    public let changeClass: OnePieceCatalogChangeClass
    /// Cached quotes for these UUIDs must be invalidated even if ownership is unchanged.
    public let marketMappingInvalidations: [UUID]
}

public enum OnePieceCatalogChangeClassifier {
    public static func classify(previous: OnePieceCatalogRelease?, current: OnePieceCatalogRelease)
        -> OnePieceCatalogChangeClassification {
        guard let previous else { return .init(changeClass: .protectedReview, marketMappingInvalidations: []) }
        let oldPrintings = Dictionary(previous.registry.printings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let currentIDs = Set(current.registry.printings.map(\.id))
        let invalidations = Set(current.registry.printings.compactMap { printing -> UUID? in
            guard let old = oldPrintings[printing.id], old.marketMappings != printing.marketMappings else { return nil }
            return printing.id
        }).union(Set(oldPrintings.keys).subtracting(currentIDs)).sorted { $0.uuidString < $1.uuidString }
        if previous.registry == current.registry && previous.observations == current.observations &&
            previous.inventories == current.inventories && previous.indexes == current.indexes &&
            previous.rulesVersion == current.rulesVersion && previous.schemaVersion == current.schemaVersion &&
            previous.catalogKind == current.catalogKind {
            return .init(changeClass: .none, marketMappingInvalidations: invalidations)
        }
        let names = Dictionary(current.registry.canonicalCards.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let labels = Dictionary(current.registry.products.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
        let allowedContent = OnePieceRegistryDocument(schemaVersion: previous.registry.schemaVersion,
            canonicalCards: previous.registry.canonicalCards.map {
                .init(printedNumber: $0.printedNumber, language: $0.language, name: names[$0.id] ?? $0.name,
                      printingCoverageComplete: $0.printingCoverageComplete, coverageReviewReference: $0.coverageReviewReference)
            }, artworks: previous.registry.artworks, printings: previous.registry.printings,
            variants: previous.registry.variants, products: previous.registry.products.map {
                .init(id: $0.id, label: labels[$0.id] ?? $0.label, releaseDate: $0.releaseDate)
            }, appearances: previous.registry.appearances, corrections: previous.registry.corrections)
        let contentOnly = allowedContent == current.registry && previous.observations == current.observations &&
            previous.inventories == current.inventories && previous.indexes == current.indexes &&
            previous.rulesVersion == current.rulesVersion && previous.schemaVersion == current.schemaVersion &&
            previous.catalogKind == current.catalogKind
        return .init(changeClass: contentOnly ? .contentOnly : .protectedReview,
                     marketMappingInvalidations: invalidations)
    }
}
