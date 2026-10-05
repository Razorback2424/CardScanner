import Foundation

struct OnePieceImportAdapter: GameImportAdapter {
    let registry: OnePieceCatalogRegistry
    var game: CardGame { .onePiece }
    var generation: String? { registry.generation }

    func validate(_ entry: CollectionCSVEntry) throws {
        guard entry.game == game, entry.itemKind == .rawCard else {
            throw GameImportValidationError.unsupportedItemKind
        }
        guard
              let id = UUID(uuidString: entry.providerID),
              entry.providerID == id.uuidString.lowercased(),
              let card = try? OnePieceCatalogAdapter(registry: registry).resolution(forPrintingID: id).card else {
            throw GameImportValidationError.invalidPrinting
        }
        guard entry.catalogProviderID == nil || entry.catalogProviderID == entry.providerID,
              entry.cardNumber.isEmpty || entry.cardNumber == card.cardNumber,
              entry.pokemonPrintRun == nil, entry.magicTreatmentIDsRaw.isEmpty,
              entry.justTCGCardID == nil, entry.justTCGVariantID == nil else {
            throw GameImportValidationError.contradictoryIdentity
        }
        guard entry.variant == nil || card.variantEvidence.catalogVariants.contains(where: { $0.id == entry.variant?.id }) else {
            throw GameImportValidationError.unsupportedFinish
        }
        guard entry.collectionKey == card.collectionKey(variant: entry.variant) else {
            throw GameImportValidationError.invalidOwnershipKey
        }
    }

    func metadata(for requests: [GameImportRequest]) async -> [String: ImportedCatalogMetadata] {
        var matches: [String: ImportedCatalogMetadata] = [:]
        for request in requests where request.game == game && request.itemKind == .rawCard {
            // A number/name is never sufficient to allocate an ownership UUID.
            guard let id = UUID(uuidString: request.catalogProviderID ?? request.sourceProviderID),
                  let card = try? OnePieceCatalogAdapter(registry: registry).resolution(forPrintingID: id).card,
                  request.cardNumber.isEmpty || request.cardNumber == card.cardNumber else { continue }
            if let sourceID = UUID(uuidString: request.sourceProviderID), sourceID != id { continue }
            matches[request.identityKey] = .init(providerID: card.physicalPrintingID,
                setCode: card.setCode, rarity: card.rarity, imageURL: card.storedImageURL,
                thumbnailURL: card.thumbnailImageURL?.absoluteString,
                tcgplayerURL: nil, setReleaseOrder: card.setReleaseOrder, updatesProviderPurchaseURL: false)
        }
        return matches
    }
}
