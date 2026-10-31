import Foundation

public struct OnePieceCanonicalCard: Codable, Hashable, Sendable {
    public let id: String
    public let printedNumber: String
    public let language: String
    public let name: String
    /// Explicit, reviewed coverage; never inferred from a vendor row count.
    public let printingCoverageComplete: Bool
    public let coverageReviewReference: String?

    public init(printedNumber: String, language: String, name: String,
                printingCoverageComplete: Bool = false, coverageReviewReference: String? = nil) {
        self.printedNumber = printedNumber; self.language = language; self.name = name
        self.id = "one-piece:\(language):\(printedNumber)"
        self.printingCoverageComplete = printingCoverageComplete
        self.coverageReviewReference = coverageReviewReference
    }
}

public struct OnePieceVariantDescriptor: Codable, Hashable, Sendable {
    public let id: String
    public let label: String
    public init(id: String, label: String) { self.id = id; self.label = label }
}

public struct OnePieceProduct: Codable, Hashable, Sendable {
    public let id: String
    public let label: String
    /// Calendar day, independent of publisher/device time zone.
    public let releaseDate: String?
    public init(id: String, label: String, releaseDate: String? = nil) {
        self.id = id; self.label = label; self.releaseDate = releaseDate
    }
}

public struct OnePieceProductAppearance: Codable, Hashable, Sendable {
    public let printingID: UUID
    public let productID: String
    public let observationIDs: [String]
    public init(printingID: UUID, productID: String, observationIDs: [String]) {
        self.printingID = printingID; self.productID = productID; self.observationIDs = observationIDs
    }
}
