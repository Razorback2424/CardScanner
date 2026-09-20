import Foundation

public struct PokemonCatalogSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = PokemonCatalogCoreContract.snapshotSchemaVersion

    public let schemaVersion: Int
    public let rulesVersion: Int
    public let generatedAt: Date
    public let directoryFingerprint: String
    public let entries: [PokemonCatalogSnapshotEntry]
    public let checklists: [String: [PokemonCatalogCardSummary]]

    public init(
        schemaVersion: Int = PokemonCatalogSnapshot.currentSchemaVersion,
        rulesVersion: Int = PokemonCatalogCoreContract.rulesVersion,
        generatedAt: Date,
        directoryFingerprint: String,
        entries: [PokemonCatalogSnapshotEntry],
        checklists: [String: [PokemonCatalogCardSummary]]
    ) {
        self.schemaVersion = schemaVersion
        self.rulesVersion = rulesVersion
        self.generatedAt = generatedAt
        self.directoryFingerprint = directoryFingerprint
        self.entries = entries
        self.checklists = checklists
    }
}

public struct PokemonCatalogSnapshotEntry: Codable, Equatable, Hashable, Sendable {
    public let providerSetID: String
    public let displayName: String
    public let printedCode: String?
    public let officialCount: Int?
    public let releaseOrder: Int?
    public let providerFingerprint: String
    public let cardCount: Int
    public let resource: String
    /// Up to three card image URLs are a last-resort Browse hint. They are
    /// presentation metadata and never authorize scanner recognition.
    public var artworkFallbackURLs: [String]?

    public init(
        providerSetID: String,
        displayName: String,
        printedCode: String?,
        officialCount: Int?,
        releaseOrder: Int?,
        providerFingerprint: String,
        cardCount: Int,
        resource: String,
        artworkFallbackURLs: [String]? = nil
    ) {
        self.providerSetID = providerSetID
        self.displayName = displayName
        self.printedCode = printedCode
        self.officialCount = officialCount
        self.releaseOrder = releaseOrder
        self.providerFingerprint = providerFingerprint
        self.cardCount = cardCount
        self.resource = resource
        self.artworkFallbackURLs = artworkFallbackURLs
    }
}

public struct PokemonCatalogCardSummary: Codable, Equatable, Hashable, Sendable {
    public let providerCardID: String
    public let localID: String
    public let name: String
    public let imageURL: String?

    public init(
        providerCardID: String,
        localID: String,
        name: String,
        imageURL: String?
    ) {
        self.providerCardID = providerCardID
        self.localID = localID
        self.name = name
        self.imageURL = imageURL
    }
}

public enum PokemonCatalogFingerprint {
    /// A stable, dependency-free FNV-1a fingerprint is sufficient for the
    /// refresh decision and keeps the snapshot bytes portable across Apple OSes.
    public static func string(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
