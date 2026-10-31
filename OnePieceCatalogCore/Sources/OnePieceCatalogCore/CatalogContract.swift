import Foundation

public enum OnePieceCatalogContract {
    public static let schemaVersion = 1
    public static let rulesVersion = 2
    public static let catalogKind = "one-piece"
}

/// Publisher-controlled registry. UUID allocation happens in this durable,
/// reviewed input, never in a provider parser or release-builder invocation.
public struct OnePieceRegistryDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let canonicalCards: [OnePieceCanonicalCard]
    public let artworks: [OnePieceArtwork]
    public let printings: [OnePiecePhysicalPrinting]
    public let variants: [OnePieceVariantDescriptor]
    public let products: [OnePieceProduct]
    public let appearances: [OnePieceProductAppearance]
    public let corrections: [OnePieceRegistryCorrection]

    public init(schemaVersion: Int = OnePieceCatalogContract.schemaVersion,
                canonicalCards: [OnePieceCanonicalCard], artworks: [OnePieceArtwork],
                printings: [OnePiecePhysicalPrinting], variants: [OnePieceVariantDescriptor],
                products: [OnePieceProduct] = [], appearances: [OnePieceProductAppearance] = [],
                corrections: [OnePieceRegistryCorrection] = []) {
        self.schemaVersion = schemaVersion; self.canonicalCards = canonicalCards
        self.artworks = artworks; self.printings = printings; self.variants = variants
        self.products = products; self.appearances = appearances; self.corrections = corrections
    }
}

public struct OnePieceCatalogIndexes: Codable, Equatable, Sendable {
    public let canonicalIDsByPrintedNumber: [String: [String]]
    public let printingIDsByCanonicalID: [String: [UUID]]
    public let automaticCandidateIDsByCanonicalID: [String: [UUID]]
    public let supportedPrefixes: [String]

    public init(registry: OnePieceRegistryDocument) {
        var canonical: [String: [String]] = [:]
        for card in registry.canonicalCards { canonical[card.printedNumber, default: []].append(card.id) }
        canonicalIDsByPrintedNumber = canonical.mapValues { $0.sorted() }
        let active = registry.printings.filter { $0.status != .superseded }
        let grouped = Dictionary(grouping: active, by: \.canonicalCardID)
        printingIDsByCanonicalID = grouped.mapValues { $0.map(\.id).sorted { $0.uuidString < $1.uuidString } }
        var automatic: [String: [UUID]] = [:]
        for card in registry.canonicalCards where card.printingCoverageComplete {
            let candidates = grouped[card.id] ?? []
            // A conflicted/provisional row cannot disappear and manufacture a
            // unique match. Automatic indexes require complete verified scope.
            if !candidates.isEmpty && candidates.allSatisfy({ $0.status == .verified }) {
                automatic[card.id] = candidates.map(\.id).sorted { $0.uuidString < $1.uuidString }
            }
        }
        automaticCandidateIDsByCanonicalID = automatic
        supportedPrefixes = Set(registry.canonicalCards.compactMap {
            OnePieceTextNormalization.prefix(of: $0.printedNumber)
        }).sorted()
    }
}

public struct OnePieceCatalogRelease: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let rulesVersion: Int
    public let catalogKind: String
    public let revision: Int
    public let generatedAt: String
    public let registry: OnePieceRegistryDocument
    public let observations: [OnePieceSourceObservation]
    public let inventories: [OnePieceSourceInventory]
    public let indexes: OnePieceCatalogIndexes

    public init(schemaVersion: Int = OnePieceCatalogContract.schemaVersion,
                rulesVersion: Int = OnePieceCatalogContract.rulesVersion,
                catalogKind: String = OnePieceCatalogContract.catalogKind,
                revision: Int, generatedAt: String, registry: OnePieceRegistryDocument,
                observations: [OnePieceSourceObservation], inventories: [OnePieceSourceInventory],
                indexes: OnePieceCatalogIndexes? = nil) {
        self.schemaVersion = schemaVersion; self.rulesVersion = rulesVersion; self.catalogKind = catalogKind
        self.revision = revision; self.generatedAt = generatedAt; self.registry = registry
        self.observations = observations; self.inventories = inventories
        self.indexes = indexes ?? OnePieceCatalogIndexes(registry: registry)
    }

    public func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
