import Foundation

public enum OnePieceObservationProvider: String, Codable, Sendable {
    case bandai, limitless, scrydex
}

/// Input from a permitted provider capture. These are normalized evidence
/// fields, not inferred joins or a claimed vendor API schema.
public struct OnePieceProviderCapture: Sendable {
    public let observationID: String
    public let kind: OnePieceObservationKind
    public let sourceID: String
    public let sourceURL: URL
    public let observedAt: String
    public let language: String
    public let payloadBytes: Data
    public let imageBytes: Data?
    public let perceptualHash: OnePiecePerceptualHash?
    public let productEvidence: [String]
    public let printedEvidence: [String: String]

    public init(observationID: String, kind: OnePieceObservationKind = .catalog, sourceID: String, sourceURL: URL, observedAt: String,
                language: String, payloadBytes: Data, imageBytes: Data? = nil,
                perceptualHash: OnePiecePerceptualHash? = nil, productEvidence: [String] = [],
                printedEvidence: [String: String] = [:]) {
        self.observationID = observationID; self.kind = kind; self.sourceID = sourceID; self.sourceURL = sourceURL
        self.observedAt = observedAt; self.language = language; self.payloadBytes = payloadBytes
        self.imageBytes = imageBytes; self.perceptualHash = perceptualHash
        self.productEvidence = productEvidence; self.printedEvidence = printedEvidence
    }
}

public enum OnePieceProviderNormalizer {
    public static func observation(provider: OnePieceObservationProvider,
                                   capture: OnePieceProviderCapture) -> OnePieceSourceObservation {
        .init(id: capture.observationID, kind: capture.kind,
              alias: .init(provider: provider.rawValue, sourceID: capture.sourceID),
              sourceURL: capture.sourceURL, observedAt: capture.observedAt,
              language: capture.language, payloadSHA256: OnePieceSourceObservation.sha256(capture.payloadBytes),
              imageSHA256: capture.imageBytes.map(OnePieceSourceObservation.sha256),
              perceptualHash: capture.perceptualHash, productEvidence: capture.productEvidence,
              printedEvidence: capture.printedEvidence)
    }
}
