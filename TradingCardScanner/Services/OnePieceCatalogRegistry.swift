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
    let artworkByID: [UUID: OnePieceArtwork]
    let productsByID: [String: OnePieceProduct]
    let variantsByID: [String: OnePieceVariantDescriptor]
    var generation: String { verifiedRelease.payloadFingerprint }
    var retrievedAt: Date { verifiedRelease.verifiedAt }
    var supportedNumbers: Set<String> { Set(canonicalByPrintedNumber.keys) }

    init(verifiedRelease: OnePieceVerifiedCatalogRelease) {
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
        artworkByID = Dictionary(uniqueKeysWithValues: release.registry.artworks.map { ($0.id, $0) })
        productsByID = Dictionary(uniqueKeysWithValues: release.registry.products.map { ($0.id, $0) })
        variantsByID = Dictionary(uniqueKeysWithValues: release.registry.variants.map { ($0.id, $0) })
    }
}
