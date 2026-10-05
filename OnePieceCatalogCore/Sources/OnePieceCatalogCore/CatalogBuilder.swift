import Foundation

public enum OnePieceCatalogBuilder {
    public static func build(registry: OnePieceRegistryDocument,
                             observations: [OnePieceSourceObservation], inventories: [OnePieceSourceInventory],
                             revision: Int, generatedAt: String,
                             previous: OnePieceCatalogRelease? = nil) throws -> OnePieceCatalogRelease {
        // Retain supplied UUIDs and every candidate. No image similarity,
        // provider ordering or vendor counts allocate/merge ownership identity.
        let release = OnePieceCatalogRelease(
            revision: revision, generatedAt: generatedAt, registry: canonicalRegistry(registry),
            observations: observations.map { observation in
                OnePieceSourceObservation(id: observation.id, kind: observation.kind, alias: observation.alias,
                    sourceURL: observation.sourceURL, observedAt: observation.observedAt,
                    language: observation.language, payloadSHA256: observation.payloadSHA256,
                    imageSHA256: observation.imageSHA256, perceptualHash: observation.perceptualHash,
                    productEvidence: observation.productEvidence.sorted(), printedEvidence: observation.printedEvidence)
            }.sorted { $0.id < $1.id },
            inventories: inventories.map { inventory in
                OnePieceSourceInventory(provider: inventory.provider, snapshotID: inventory.snapshotID,
                    paginationComplete: inventory.paginationComplete, observationIDs: inventory.observationIDs.sorted())
            }.sorted { ($0.provider, $0.snapshotID) < ($1.provider, $1.snapshotID) }
        )
        try OnePieceCatalogCandidateValidator.validate(release, previous: previous)
        return release
    }

    private static func aliases(_ values: [OnePieceSourceAlias]) -> [OnePieceSourceAlias] {
        values.sorted { ($0.provider, $0.sourceID) < ($1.provider, $1.sourceID) }
    }

    private static func review(_ value: OnePieceReview?) -> OnePieceReview? {
        value.map { .init(reference: $0.reference, evidence: $0.evidence.sorted {
            ($0.kind.rawValue, $0.observationID, $0.detail) < ($1.kind.rawValue, $1.observationID, $1.detail)
        }) }
    }

    private static func canonicalRegistry(_ value: OnePieceRegistryDocument) -> OnePieceRegistryDocument {
        .init(schemaVersion: value.schemaVersion,
              canonicalCards: value.canonicalCards.sorted { $0.id < $1.id },
              artworks: value.artworks.map {
                  .init(id: $0.id, referenceImageURL: $0.referenceImageURL, imageSHA256: $0.imageSHA256,
                        observationIDs: $0.observationIDs.sorted())
              }.sorted { $0.id.uuidString < $1.id.uuidString },
              printings: value.printings.map { printing in
                  OnePiecePhysicalPrinting(id: printing.id, canonicalCardID: printing.canonicalCardID,
                      artworkID: printing.artworkID, language: printing.language, region: printing.region,
                      releaseID: printing.releaseID, distributionLabel: printing.distributionLabel,
                      treatment: printing.treatment, stamp: printing.stamp, blockText: printing.blockText,
                      copyrightText: printing.copyrightText, supportedVariantIDs: printing.supportedVariantIDs.sorted(),
                      status: printing.status, review: review(printing.review), sourceAliases: aliases(printing.sourceAliases),
                      marketMappings: printing.marketMappings.map { mapping in
                          OnePieceMarketMapping(printingID: mapping.printingID, provider: mapping.provider,
                              productID: mapping.productID, providerVariantID: mapping.providerVariantID,
                              variantID: mapping.variantID, market: mapping.market, currency: mapping.currency,
                              condition: mapping.condition, qualifiers: mapping.qualifiers, status: mapping.status,
                              review: review(mapping.review))
                      }.sorted { lhs, rhs in
                          // JSON is only a deterministic ordering key, never a
                          // quote/printing equivalence decision.
                          let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                          let left = (try? encoder.encode(lhs)) ?? Data()
                          let right = (try? encoder.encode(rhs)) ?? Data()
                          return left.lexicographicallyPrecedes(right)
                      }, supersedes: printing.supersedes.sorted { $0.uuidString < $1.uuidString })
              }.sorted { $0.id.uuidString < $1.id.uuidString },
              variants: value.variants.sorted { $0.id < $1.id },
              products: value.products.sorted { $0.id < $1.id },
              appearances: value.appearances.map {
                  .init(printingID: $0.printingID, productID: $0.productID, observationIDs: $0.observationIDs.sorted())
              }.sorted { ($0.printingID.uuidString, $0.productID) < ($1.printingID.uuidString, $1.productID) },
              corrections: value.corrections.map {
                  .init(id: $0.id, kind: $0.kind,
                        fromPrintingIDs: $0.fromPrintingIDs.sorted { $0.uuidString < $1.uuidString },
                        toPrintingIDs: $0.toPrintingIDs.sorted { $0.uuidString < $1.uuidString },
                        movedAliases: aliases($0.movedAliases), review: review($0.review)!)
              }.sorted { $0.id < $1.id })
    }
}
