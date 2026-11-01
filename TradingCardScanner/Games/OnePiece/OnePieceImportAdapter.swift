import Foundation

struct OnePieceImportAdapter: GameImportAdapter {
    let registry: OnePieceCatalogRegistry
    var game: CardGame { .onePiece }
    var generation: String? { registry.generation }

    func validate(_ entry: CollectionCSVEntry) throws {
        guard !entry.conflictingSourceIdentity else { throw GameImportValidationError.contradictoryIdentity }
        guard entry.game == game, entry.itemKind == .rawCard,
              entry.sourceItemKindRaw == nil || entry.sourceItemKindRaw == CollectionItemKind.rawCard.rawValue else {
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
              entry.sourceLanguage == nil || normalizedLanguage(entry.sourceLanguage!) == card.language,
              entry.pokemonPrintRun == nil, entry.magicTreatmentIDsRaw.isEmpty, entry.magicTreatmentQualifiers.isEmpty,
              entry.magicContentKindRaw == MagicContentKind.regular.rawValue,
              entry.justTCGCardID == nil, entry.justTCGVariantID == nil, entry.justTCGAPIVersion == nil,
              entry.gradingCompany == nil, entry.grade == nil, entry.certificationNumber == nil else {
            throw GameImportValidationError.contradictoryIdentity
        }
        guard let variant = entry.variant else { throw GameImportValidationError.missingFinish }
        guard card.variantEvidence.catalogVariants.contains(where: { $0.id == variant.id }) else {
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

    private func normalizedLanguage(_ value: String) -> String {
        let lower = value.lowercased()
        return ["english", "eng"].contains(lower) ? "en" : lower
    }
}
