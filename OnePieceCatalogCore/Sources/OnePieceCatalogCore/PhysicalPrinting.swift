import Foundation

public struct OnePiecePhysicalPrinting: Codable, Hashable, Sendable {
    public let id: UUID
    public let canonicalCardID: String
    public let artworkID: UUID
    public let language: String
    public let region: String?
    public let releaseID: String?
    public let distributionLabel: String?
    public let treatment: String?
    public let stamp: String?
    public let blockText: String?
    public let copyrightText: String?
    /// Empty means unresolved finish evidence on an unverified review record.
    /// Verified printings require at least one registered physical variant.
    public let supportedVariantIDs: [String]
    public let status: OnePieceReconciliationStatus
    public let review: OnePieceReview?
    public let sourceAliases: [OnePieceSourceAlias]
    public let marketMappings: [OnePieceMarketMapping]
    public let supersedes: [UUID]

    public init(id: UUID, canonicalCardID: String, artworkID: UUID, language: String,
                region: String? = nil, releaseID: String? = nil, distributionLabel: String? = nil,
                treatment: String? = nil, stamp: String? = nil, blockText: String? = nil,
                copyrightText: String? = nil, supportedVariantIDs: [String],
                status: OnePieceReconciliationStatus = .provisional, review: OnePieceReview? = nil,
                sourceAliases: [OnePieceSourceAlias] = [], marketMappings: [OnePieceMarketMapping] = [],
                supersedes: [UUID] = []) {
        self.id = id; self.canonicalCardID = canonicalCardID; self.artworkID = artworkID
        self.language = language; self.region = region; self.releaseID = releaseID
        self.distributionLabel = distributionLabel; self.treatment = treatment; self.stamp = stamp
        self.blockText = blockText; self.copyrightText = copyrightText
        self.supportedVariantIDs = supportedVariantIDs; self.status = status; self.review = review
        self.sourceAliases = sourceAliases; self.marketMappings = marketMappings; self.supersedes = supersedes
    }

    public var requiredEvidenceKinds: Set<OnePieceEvidenceKind> {
        var kinds: Set<OnePieceEvidenceKind> = [.printedIdentity, .language, .artwork, .finish]
        if releaseID != nil { kinds.insert(.release) }
        if distributionLabel != nil { kinds.insert(.distribution) }
        if treatment != nil { kinds.insert(.treatment) }
        if stamp != nil { kinds.insert(.stamp) }
        if blockText != nil || copyrightText != nil { kinds.insert(.footer) }
        return kinds
    }
}

public enum OnePieceCorrectionKind: String, Codable, Hashable, Sendable {
    case aliasReassignment, supersession, merge, split
}

public struct OnePieceRegistryCorrection: Codable, Hashable, Sendable {
    public let id: String
    public let kind: OnePieceCorrectionKind
    public let fromPrintingIDs: [UUID]
    public let toPrintingIDs: [UUID]
    public let movedAliases: [OnePieceSourceAlias]
    public let review: OnePieceReview
    public init(id: String, kind: OnePieceCorrectionKind, fromPrintingIDs: [UUID], toPrintingIDs: [UUID],
                movedAliases: [OnePieceSourceAlias] = [], review: OnePieceReview) {
        self.id = id; self.kind = kind; self.fromPrintingIDs = fromPrintingIDs
        self.toPrintingIDs = toPrintingIDs; self.movedAliases = movedAliases; self.review = review
    }
}
