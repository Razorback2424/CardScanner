import Foundation

public struct OnePieceArtwork: Codable, Hashable, Sendable {
    public let id: UUID
    public let referenceImageURL: URL?
    public let imageSHA256: String?
    public let observationIDs: [String]
    public init(id: UUID, referenceImageURL: URL? = nil, imageSHA256: String? = nil,
                observationIDs: [String]) {
        self.id = id; self.referenceImageURL = referenceImageURL
        self.imageSHA256 = imageSHA256; self.observationIDs = observationIDs
    }
}
