import Foundation
import OnePieceCatalogCore

/// Immutable verified generation, indexed once at activation. Camera-frame
/// parsing and canonical lookup never scan the physical-printing corpus.
struct OnePieceCatalogRegistry: Sendable {
    let verifiedRelease: OnePieceVerifiedCatalogRelease
    let canonicalByPrintedNumber: [String: OnePieceCanonicalCard]
    let canonicalByID: [String: OnePieceCanonicalCard]
    let recognitionPrefixes: [String]
    let printingByID: [UUID: OnePiecePhysicalPrinting]
    let printingsByCanonicalID: [String: [OnePiecePhysicalPrinting]]
    let artworkURLByID: [UUID: URL]
    let productsByID: [String: OnePieceProduct]
    let variantsByID: [String: OnePieceVariantDescriptor]
    /// Provisional printings whose existence is documented but which TCGplayer has
    /// never priced, so their finish is unconfirmed. They are known, not unresolved.
    let knownUnpricedPrintingIDs: Set<UUID>
    /// Provisional printings TCGplayer lists without a photo, so their art is unconfirmed.
    let knownNoPhotoPrintingIDs: Set<UUID>
    static let unpricedEvidenceField = "marketplaceFinishLanes"
    static let noPhotoEvidenceField = "marketplacePhoto"
    /// Known printings held only for a marketplace gap; they do not make a set partial.
    var knownGapPrintingIDs: Set<UUID> { knownUnpricedPrintingIDs.union(knownNoPhotoPrintingIDs) }
    var generation: String { verifiedRelease.payloadFingerprint }
    var retrievedAt: Date { verifiedRelease.verifiedAt }
    var supportedNumbers: Set<String> { Set(canonicalByPrintedNumber.keys) }

    init(verifiedRelease: OnePieceVerifiedCatalogRelease, includeRecordedArtwork: Bool = false) {
        self.verifiedRelease = verifiedRelease
        let release = verifiedRelease.release
        // The first scanner/catalog adapter exposes the reviewed English scope.
        // Number recognition alone still leaves physical language unconfirmed.
        canonicalByPrintedNumber = Dictionary(uniqueKeysWithValues: release.registry.canonicalCards
            .filter { $0.language == "en" }.map { ($0.printedNumber, $0) })
        canonicalByID = Dictionary(uniqueKeysWithValues: release.registry.canonicalCards.map { ($0.id, $0) })
        recognitionPrefixes = Set(canonicalByPrintedNumber.keys.compactMap(OnePieceTextNormalization.prefix)).sorted()
        let printingIndex = Dictionary(uniqueKeysWithValues: release.registry.printings.map { ($0.id, $0) })
        printingByID = printingIndex
        printingsByCanonicalID = release.indexes.printingIDsByCanonicalID.mapValues { ids in
            ids.compactMap { printingIndex[$0] }
        }
        let observations = includeRecordedArtwork
            ? Dictionary(uniqueKeysWithValues: release.observations.map { ($0.id, $0) }) : [:]
        artworkURLByID = Dictionary(uniqueKeysWithValues: release.registry.artworks.compactMap { artwork in
            guard let url = artwork.referenceImageURL
                ?? Self.recordedArtworkURL(for: artwork, observations: observations) else { return nil }
            return (artwork.id, url)
        })
        productsByID = Dictionary(uniqueKeysWithValues: release.registry.products.map { ($0.id, $0) })
        variantsByID = Dictionary(uniqueKeysWithValues: release.registry.variants.map { ($0.id, $0) })
        func gap(_ field: String) -> Set<UUID> {
            let evidence = Set(release.observations.lazy.filter { $0.printedEvidence[field] == "none" }.map(\.id))
            return evidence.isEmpty ? [] : Set(release.registry.printings.lazy.filter {
                $0.status == .provisional && $0.supportedVariantIDs.isEmpty
                    && ($0.review?.evidence.contains { evidence.contains($0.observationID) } ?? false)
            }.map(\.id))
        }
        knownUnpricedPrintingIDs = gap(Self.unpricedEvidenceField)
        knownNoPhotoPrintingIDs = gap(Self.noPhotoEvidenceField).subtracting(knownUnpricedPrintingIDs)
    }

    /// Exact Bandai artwork from a hash-matched render observation. No guessed
    /// number or parallel URLs.
    static func recordedArtworkURL(for artwork: OnePieceArtwork,
                                   observations: [String: OnePieceSourceObservation]) -> URL? {
        guard let hash = artwork.imageSHA256 else { return nil }
        return artwork.observationIDs.sorted().compactMap { observations[$0] }.first(where: {
            $0.alias.provider == "bandai" && $0.kind == .catalog
                && $0.imageSHA256 == hash && $0.sourceURL.scheme == "https"
                && $0.sourceURL.host == "en.onepiece-cardgame.com"
                && $0.sourceURL.path.hasPrefix("/images/")
                && $0.sourceURL.pathExtension.lowercased() == "png"
        })?.sourceURL
    }
}
