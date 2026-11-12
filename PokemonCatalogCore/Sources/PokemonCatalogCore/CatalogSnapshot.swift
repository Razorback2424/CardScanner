import CryptoKit
import Foundation

public struct PokemonCatalogSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = PokemonCatalogCoreContract.snapshotSchemaVersion
    public static let maximumPublishedBytes = 24 * 1024 * 1024

    public let schemaVersion: Int
    public let rulesVersion: Int
    public let generatedAt: Date
    public let directoryFingerprint: String
    public let entries: [PokemonCatalogSnapshotEntry]
    public let checklists: [String: [PokemonCatalogCardSummary]]
    public let checklistInputs: [String: PokemonCatalogChecklistInput]?

    public init(
        schemaVersion: Int = PokemonCatalogSnapshot.currentSchemaVersion,
        rulesVersion: Int = PokemonCatalogCoreContract.rulesVersion,
        generatedAt: Date,
        directoryFingerprint: String,
        entries: [PokemonCatalogSnapshotEntry],
        checklists: [String: [PokemonCatalogCardSummary]],
        checklistInputs: [String: PokemonCatalogChecklistInput]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.rulesVersion = rulesVersion
        self.generatedAt = generatedAt
        self.directoryFingerprint = directoryFingerprint
        self.entries = entries
        self.checklists = checklists
        self.checklistInputs = checklistInputs
    }

    public func verifiedChecklistInputs(for release: PokemonCatalogRelease) throws -> [String: PokemonCatalogChecklistInput] {
        guard let checklistInputs, !checklistInputs.isEmpty,
              let expected = release.checklistInputSHA256,
              try PokemonCatalogChecklistInput.digest(checklistInputs) == expected else {
            throw PokemonCatalogCandidateValidationError.checklistInputsMismatch
        }
        let descriptors = Dictionary(release.sets.map { ($0.providerSetID.lowercased(), $0) },
                                     uniquingKeysWith: { first, _ in first })
        guard Set(checklistInputs.keys) == Set(entries.map(\.providerSetID)) else {
            throw PokemonCatalogCandidateValidationError.checklistInputsMismatch
        }
        for (id, input) in checklistInputs {
            let details = Dictionary(input.cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            guard let descriptor = descriptors[id], id == input.providerSet.id.lowercased(),
                  details.count == input.cards.count, details.count == input.providerSet.cards.count,
                  Set(input.providerSet.cards.map(\.id)) == Set(details.keys),
                  let fingerprint = PokemonCatalogProviderFingerprint.v1(providerSet: input.providerSet, cardDetails: details),
                  fingerprint == descriptor.providerFingerprint else {
                throw PokemonCatalogCandidateValidationError.checklistInputsMismatch
            }
            if let acquisitionFingerprint = descriptor.providerAcquisitionFingerprint,
               acquisitionFingerprint != PokemonCatalogProviderFingerprint.acquisitionV1(providerSet: input.providerSet, cardDetails: details) {
                throw PokemonCatalogCandidateValidationError.checklistInputsMismatch
            }
        }
        return checklistInputs
    }
}

public struct PokemonCatalogChecklistInput: Codable, Equatable, Sendable {
    public let providerSet: PokemonCatalogProviderSet
    public let cards: [PokemonCatalogProviderCard]

    public init(providerSet: PokemonCatalogProviderSet, cards: [PokemonCatalogProviderCard]) {
        self.providerSet = providerSet
        self.cards = cards
    }

    public static func digest(_ inputs: [String: Self]) throws -> String {
        try SHA256.hash(data: PokemonCatalogJSON.encode(inputs)).map { String(format: "%02x", $0) }.joined()
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
