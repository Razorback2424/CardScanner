import Foundation

public enum OnePieceReconciliationStatus: String, Codable, Hashable, Sendable {
    case provisional, verified, conflicted, quarantined, superseded
}

public enum OnePieceEvidenceKind: String, Codable, Hashable, Sendable {
    case printedIdentity, language, artwork, release, distribution, treatment, stamp, footer, finish, marketIdentity
}

public struct OnePieceEvidence: Codable, Hashable, Sendable {
    public let kind: OnePieceEvidenceKind
    public let observationID: String
    public let detail: String
    public init(kind: OnePieceEvidenceKind, observationID: String, detail: String) {
        self.kind = kind; self.observationID = observationID; self.detail = detail
    }
}

/// A review reference describes evidence for this distinction. Repeated copies
/// of an image on different websites do not count as independent proof.
public struct OnePieceReview: Codable, Hashable, Sendable {
    public let reference: String
    public let evidence: [OnePieceEvidence]
    public init(reference: String, evidence: [OnePieceEvidence]) {
        self.reference = reference; self.evidence = evidence
    }
}
