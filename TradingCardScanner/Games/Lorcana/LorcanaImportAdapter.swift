import Foundation

struct LorcanaImportAdapter: GameImportAdapter {
    let registry: LorcanaCatalogRegistry
    var game: CardGame { .lorcana }
    var generation: String? { registry.generation }

    func validate(_ entry: CollectionCSVEntry) throws {
        guard !entry.conflictingSourceIdentity else { throw GameImportValidationError.contradictoryIdentity }
        guard entry.game == game, entry.itemKind == .rawCard,
              entry.sourceItemKindRaw == nil || entry.sourceItemKindRaw == CollectionItemKind.rawCard.rawValue else {
            throw GameImportValidationError.unsupportedItemKind
        }
        guard let id = exactUUID(entry.providerID),
              let card = try? LorcanaCatalogAdapter(registry: registry).resolution(forPrintingID: id).card else {
            throw GameImportValidationError.invalidPrinting
        }
        guard entry.catalogProviderID == nil || entry.catalogProviderID == entry.providerID,
              matchesNumber(entry.cardNumber, card: card),
              entry.sourceLanguage == nil || normalizedLanguage(entry.sourceLanguage!) == card.language,
              entry.pokemonPrintRun == nil, entry.magicTreatmentIDsRaw.isEmpty, entry.magicTreatmentQualifiers.isEmpty,
              entry.magicContentKindRaw == MagicContentKind.regular.rawValue,
              entry.justTCGCardID == nil, entry.justTCGVariantID == nil, entry.justTCGAPIVersion == nil,
              entry.gradingCompany == nil, entry.grade == nil, entry.certificationNumber == nil else {
            throw GameImportValidationError.contradictoryIdentity
        }
        guard let finish = entry.variant else { throw GameImportValidationError.missingFinish }
        guard card.variantEvidence.catalogVariants.contains(where: { $0.id == finish.id }) else {
            throw GameImportValidationError.unsupportedFinish
        }
        guard entry.collectionKey == card.collectionKey(variant: finish) else { throw GameImportValidationError.invalidOwnershipKey }
    }

    func metadata(for requests: [GameImportRequest]) async -> [String: ImportedCatalogMetadata] {
        var matches: [String: ImportedCatalogMetadata] = [:]
        for request in requests where request.game == game && request.itemKind == .rawCard {
            guard let id = exactUUID(request.catalogProviderID ?? request.sourceProviderID),
                  let printing = registry.physicalCatalog?.printingByID[id],
                  let card = try? LorcanaCatalogAdapter(registry: registry).resolution(forPrintingID: id).card,
                  matchesNumber(request.cardNumber, card: card) else { continue }
            // A shared provider alias is provenance, not a candidate picker.
            // It is usable only alongside the explicit reviewed physical UUID.
            guard request.sourceProviderID == card.physicalPrintingID
                || (request.catalogProviderID != nil && printing.sourceAliases.contains {
                    request.sourceProviderID == "\($0.provider):\($0.id)"
                }) else { continue }
            matches[request.identityKey] = .init(providerID: card.physicalPrintingID, setCode: card.setCode,
                rarity: card.rarity, imageURL: card.storedImageURL, thumbnailURL: card.thumbnailImageURL?.absoluteString,
                tcgplayerURL: nil, setReleaseOrder: card.setReleaseOrder, updatesProviderPurchaseURL: false)
        }
        return matches
    }

    private func exactUUID(_ value: String) -> UUID? {
        guard let id = UUID(uuidString: value), id.uuidString.lowercased() == value else { return nil }
        return id
    }
    private func matchesNumber(_ number: String, card: ResolvedCatalogCard) -> Bool {
        number.isEmpty || number == card.cardNumber || number == card.identifier
    }
    private func normalizedLanguage(_ value: String) -> String {
        let lower = value.lowercased()
        return ["english", "eng"].contains(lower) ? "en" : lower
    }
}
