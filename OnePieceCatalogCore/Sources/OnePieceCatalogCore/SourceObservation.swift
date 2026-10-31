import CryptoKit
import Foundation

public struct OnePieceSourceAlias: Codable, Hashable, Sendable {
    public let provider: String
    public let sourceID: String
    public init(provider: String, sourceID: String) { self.provider = provider; self.sourceID = sourceID }
}

public struct OnePiecePerceptualHash: Codable, Hashable, Sendable {
    public let algorithm: String
    public let version: Int
    public let value: String
    public init(algorithm: String, version: Int, value: String) {
        self.algorithm = algorithm; self.version = version; self.value = value
    }
}

public enum OnePieceObservationKind: String, Codable, Hashable, Sendable { case catalog, market }

public struct OnePieceSourceObservation: Codable, Hashable, Sendable {
    public let id: String
    public let kind: OnePieceObservationKind
    public let alias: OnePieceSourceAlias
    public let sourceURL: URL
    public let observedAt: String
    public let language: String
    public let payloadSHA256: String
    public let imageSHA256: String?
    public let perceptualHash: OnePiecePerceptualHash?
    public let productEvidence: [String]
    public let printedEvidence: [String: String]

    public init(id: String, kind: OnePieceObservationKind = .catalog, alias: OnePieceSourceAlias, sourceURL: URL, observedAt: String,
                language: String, payloadSHA256: String, imageSHA256: String? = nil,
                perceptualHash: OnePiecePerceptualHash? = nil, productEvidence: [String] = [],
                printedEvidence: [String: String] = [:]) {
        self.id = id; self.kind = kind; self.alias = alias; self.sourceURL = sourceURL; self.observedAt = observedAt
        self.language = language; self.payloadSHA256 = payloadSHA256; self.imageSHA256 = imageSHA256
        self.perceptualHash = perceptualHash; self.productEvidence = productEvidence
        self.printedEvidence = printedEvidence
    }

    public static func sha256(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

public struct OnePieceSourceInventory: Codable, Hashable, Sendable {
    public let provider: String
    public let snapshotID: String
    public let paginationComplete: Bool
    public let observationIDs: [String]
    public init(provider: String, snapshotID: String, paginationComplete: Bool, observationIDs: [String]) {
        self.provider = provider; self.snapshotID = snapshotID
        self.paginationComplete = paginationComplete; self.observationIDs = observationIDs
    }
}
