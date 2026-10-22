import Foundation

extension YuGiOhEdition {
    var variant: PhysicalVariant {
        switch self { case .first: .yugiohFirstEdition; case .unlimited: .yugiohUnlimited; case .limited: .yugiohLimited }
    }
}

extension YuGiOhCatalog {
    var runtime: CardGameRuntime { YuGiOhGameRuntime(catalog: self).runtime }
}

struct YuGiOhCatalogAdapter: GameCatalogAdapter {
    let catalog: YuGiOhCatalog
    var game: CardGame { .yuGiOh }
    var generation: String { catalog.generation }
    private func code(for identifier: ScanIdentifier) throws -> String {
        guard identifier.game == game, identifier.namespace == "printed-set-code", identifier.fields.count == 1,
              identifier.fields[0].key == "code", YuGiOhCatalog.validCode(identifier.fields[0].value),
              identifier.displayIdentifier == identifier.fields[0].value,
              identifier.suppressionIdentity == "code:" + identifier.fields[0].value else { throw CatalogLookupError.invalidAdapterOutcome }
        return identifier.fields[0].value
    }
    func identifierForRetry(_ identifier: ScanIdentifier) throws -> ScanIdentifier {
        try YuGiOhRecognitionAdapter.identifier(code: code(for: identifier), generation: generation)
    }
    func identifierForCatalogSelection(printingID: String, original: ScanIdentifier) throws -> ScanIdentifier {
        guard original.game == game, let id = UUID(uuidString: printingID), id.uuidString.lowercased() == printingID,
              let p = catalog.printingByID[id] else { throw CatalogLookupError.invalidPrintingChoice }
        _ = try resolution(forPrintingID: id)
        return try YuGiOhRecognitionAdapter.identifier(code: p.code, generation: generation)
    }
    func prepareLookupIdentifier(_ identifier: ScanIdentifier) throws -> ScanIdentifier {
        guard identifier.catalogGeneration == generation else { throw CatalogLookupError.staleCatalog }
        _ = try code(for: identifier)
        return identifier
    }
    func validateLookupContext(_ identifier: ScanIdentifier) async throws { _ = try prepareLookupIdentifier(identifier) }
    func lookup(_ identifier: ScanIdentifier) async throws -> CatalogLookupOutcome {
        let code = try code(for: prepareLookupIdentifier(identifier))
        guard let family = catalog.printingsByCode[code], let first = family.first else { return .catalogIncomplete(nil) }
        let summary = CanonicalCardSummary(id: first.card.id.uuidString.lowercased(), game: game,
            name: first.card.name, printedIdentifier: code, language: "en")
        let candidates = family.map(candidate)
        guard family.contains(where: { $0.explicitSelectionSupported && candidate($0).selectionEvidence(among: candidates) != .insufficient }) else { return .catalogIncomplete(summary) }
        if family.count == 1 && catalog.autoEligibleCodes.contains(code) { return .resolved(try resolution(forPrintingID: first.id)) }
        return .needsPrintingChoice(canonical: summary, candidates: candidates)
    }
    func resolve(_ candidate: PhysicalPrintingCandidate, for identifier: ScanIdentifier) async throws -> CardCatalog.CatalogResolution {
        let code = try code(for: prepareLookupIdentifier(identifier))
        guard let family = catalog.printingsByCode[code], let p = family.first(where: { $0.idString == candidate.id }),
              candidate == self.candidate(p) else { throw CatalogLookupError.invalidPrintingChoice }
        return try resolution(forPrintingID: p.id)
    }
    func validateAcquisition(_ identifier: ScanIdentifier, printingID: String, automatic: Bool) async throws {
        let code = try code(for: prepareLookupIdentifier(identifier))
        guard let p = catalog.printingsByCode[code]?.first(where: { $0.idString == printingID }),
              !automatic || catalog.autoEligibleCodes.contains(code) else { throw CatalogLookupError.invalidPrintingChoice }
        _ = try resolution(forPrintingID: p.id)
    }
    func validateVariantCorrection(printingID: String, variantID: String?) throws {
        guard let id = UUID(uuidString: printingID), id.uuidString.lowercased() == printingID,
              let variantID, let card = try? resolutionForExistingHolding(id).card,
              card.variantEvidence.catalogVariants.contains(where: { $0.id == variantID }) else { throw CatalogLookupError.invalidPrintingChoice }
    }
    func validateCollectionMutation(printingID: String, catalogProviderID: String?, variantID: String?, itemKindRaw: String, collectionKey: String) throws {
        guard itemKindRaw == CollectionItemKind.rawCard.rawValue, catalogProviderID == nil || catalogProviderID == printingID,
              let id = UUID(uuidString: printingID), id.uuidString.lowercased() == printingID,
              let edition = variantID.flatMap(YuGiOhEdition.init(rawValue:)) else { throw CatalogLookupError.invalidPrintingChoice }
        let card = try resolution(forPrintingID: id).card
        guard card.variantEvidence.catalogVariants.contains(edition.variant), card.collectionKey(variant: edition.variant) == collectionKey else { throw CatalogLookupError.invalidPrintingChoice }
    }
    func candidate(_ p: YuGiOhCatalog.Printing) -> PhysicalPrintingCandidate {
        .init(id: p.idString, game: game, canonicalCardID: p.card.id.uuidString.lowercased(), language: "en",
            catalogGeneration: generation, name: p.card.name, printedIdentifier: p.code, releaseLabel: p.set.name,
            treatmentLabel: p.rarity, distributionLabel: p.artLabel, releaseDate: p.set.releaseDate,
            thumbnailURL: p.thumbnailURL, artworkID: nil, distinctionLabels: [p.productName],
            acquisitionUnavailableReason: p.explicitSelectionSupported ? nil
                : "Discovery only. This product has no supported edition or needs identity review.")
    }
    func resolution(forPrintingID id: UUID) throws -> CardCatalog.CatalogResolution {
        return try resolutionForExistingHolding(id)
    }

    // Existing-holding identity/edition checks are independent of acquisition.
    // Collection mutation validation still applies; this cannot authorize adds.
    func resolutionForExistingHolding(_ id: UUID) throws -> CardCatalog.CatalogResolution {
        guard let p = catalog.printingByID[id], p.explicitSelectionSupported else { throw CatalogLookupError.invalidPrintingChoice }
        let candidates = (catalog.printingsByCode[p.code] ?? []).map(candidate)
        guard candidate(p).selectionEvidence(among: candidates) != .insufficient else { throw CatalogLookupError.invalidPrintingChoice }
        return try discoveryResolution(id)
    }

    func discoveryResolution(_ id: UUID) throws -> CardCatalog.CatalogResolution {
        guard let p = catalog.printingByID[id] else { throw CatalogLookupError.invalidPrintingChoice }
        let family = catalog.printingsByCode[p.code] ?? []
        let candidates = family.map(candidate)
        let name = p.card.name + (family.count > 1 ? " · " + candidate(p).compactChoiceLabel(among: candidates) : "")
        let order = p.set.releaseDate.map { Int($0.timeIntervalSince1970 / 86_400) }
        let card = try ResolvedCatalogCard(game: game, physicalPrintingID: p.idString, canonicalCardID: p.card.id.uuidString.lowercased(),
            language: "en", name: name, setName: p.set.name, setCode: p.set.abbreviation, cardNumber: p.code,
            printedIdentifier: p.code, rarity: p.rarity, displayImageURL: p.imageURL, thumbnailImageURL: p.thumbnailURL,
            setReleaseOrder: order ?? 0, variantEvidence: .init(game: game, setID: "tcgplayer-group:\(p.set.groupID)",
                cardNumber: p.code, catalogVariants: p.explicitSelectionSupported ? p.editions.map(\.variant) : [],
                physicalCoverageVerified: p.coverageVerified, explicitMembershipSupported: p.explicitSelectionSupported))
        return .init(card, retrievedAt: catalog.capturedAt, path: .cacheHit)
    }
}
