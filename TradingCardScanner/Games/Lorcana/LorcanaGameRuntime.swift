import Foundation

struct LorcanaCatalogAdapter: GameCatalogAdapter {
    let registry: LorcanaCatalogRegistry
    var game: CardGame { .lorcana }
    var generation: String { registry.generation }

    private func footer(for identifier: ScanIdentifier) throws -> LorcanaPrintedIdentity {
        let fields = Dictionary(uniqueKeysWithValues: identifier.fields.map { ($0.key, $0.value) })
        guard identifier.game == game, identifier.namespace == "printed-footer",
              Set(fields.keys) == ["collectorNumber", "denominator", "language", "printedSetMarker"],
              let number = fields["collectorNumber"], let denominator = fields["denominator"],
              let language = fields["language"], let marker = fields["printedSetMarker"],
              let footer = try? LorcanaPrintedIdentity(collectorNumber: number, denominator: denominator,
                                                      language: language, printedSetMarker: marker),
              footer.collectorNumber == number,
              identifier.displayIdentifier == footer.displayIdentifier,
              identifier.suppressionIdentity == "footer:\(footer.evidenceKey)" else {
            throw CatalogLookupError.invalidAdapterOutcome
        }
        return footer
    }

    func identifierForRetry(_ identifier: ScanIdentifier) throws -> ScanIdentifier {
        try LorcanaRecognitionAdapter.identifier(footer(for: identifier), generation: generation)
    }

    func prepareLookupIdentifier(_ identifier: ScanIdentifier) throws -> ScanIdentifier {
        guard identifier.catalogGeneration == generation else { throw CatalogLookupError.staleCatalog }
        _ = try footer(for: identifier)
        return identifier
    }

    func validateLookupContext(_ identifier: ScanIdentifier) async throws {
        _ = try prepareLookupIdentifier(identifier)
    }

    func lookup(_ identifier: ScanIdentifier) async throws -> CatalogLookupOutcome {
        guard identifier.catalogGeneration == generation else { throw CatalogLookupError.staleCatalog }
        let key = try footer(for: identifier)
        guard let family = registry.familiesByFooter[key] else { return .catalogIncomplete(nil) }
        let familySummary = CanonicalCardSummary(id: key.familyID, game: game, name: family.displayName,
            printedIdentifier: key.displayIdentifier, language: key.language)
        guard let physical = registry.physicalCatalog,
              let printings = physical.reviewedPrintings(for: key), let first = printings.first,
              let canonical = physical.canonicalByID[first.identity.canonicalCardID] else {
            return .catalogIncomplete(familySummary)
        }
        let summary = CanonicalCardSummary(id: canonical.id.uuidString.lowercased(), game: game,
            name: canonical.displayName, printedIdentifier: key.displayIdentifier, language: key.language)
        if printings.count == 1, first.identity.size == .standard {
            return .resolved(try resolution(first, canonical: canonical))
        }
        // Even a lone oversized record needs an explicit size distinction: OCR
        // contains no size evidence. Ambiguous labels cannot create a usable
        // choice merely because two hidden UUIDs differ.
        let candidates = printings.map { candidate($0, canonical: canonical) }
        guard candidates.allSatisfy({ $0.selectionEvidence(among: candidates) != .insufficient }) else {
            return .catalogIncomplete(summary)
        }
        return .needsPrintingChoice(canonical: summary, candidates: candidates)
    }

    func resolve(_ candidate: PhysicalPrintingCandidate, for identifier: ScanIdentifier) async throws -> CardCatalog.CatalogResolution {
        let footer = try self.footer(for: prepareLookupIdentifier(identifier))
        guard candidate.game == game, candidate.catalogGeneration == generation,
              let physical = registry.physicalCatalog, let printings = physical.reviewedPrintings(for: footer),
              let printing = printings.first(where: { $0.id.uuidString.lowercased() == candidate.id }),
              let canonical = physical.canonicalByID[printing.identity.canonicalCardID],
              candidate == self.candidate(printing, canonical: canonical) else {
            throw CatalogLookupError.invalidPrintingChoice
        }
        let candidates = printings.map { self.candidate($0, canonical: canonical) }
        guard candidate.selectionEvidence(among: candidates) != .insufficient else { throw CatalogLookupError.invalidPrintingChoice }
        return try resolution(printing, canonical: canonical)
    }

    func validateAcquisition(_ identifier: ScanIdentifier, printingID: String, automatic: Bool) async throws {
        let footer = try self.footer(for: prepareLookupIdentifier(identifier))
        guard let printings = registry.physicalCatalog?.reviewedPrintings(for: footer),
              let printing = printings.first(where: { $0.id.uuidString.lowercased() == printingID }) else {
            throw CatalogLookupError.invalidPrintingChoice
        }
        if automatic {
            guard printings.count == 1, printing.identity.size == .standard else { throw CatalogLookupError.invalidPrintingChoice }
        } else {
            guard let canonical = registry.physicalCatalog?.canonicalByID[printing.identity.canonicalCardID] else {
                throw CatalogLookupError.invalidPrintingChoice
            }
            let candidates = printings.map { candidate($0, canonical: canonical) }
            guard candidate(printing, canonical: canonical).selectionEvidence(among: candidates) != .insufficient else {
                throw CatalogLookupError.invalidPrintingChoice
            }
        }
    }

    func validateVariantCorrection(printingID: String, variantID: String?) throws {
        guard let id = UUID(uuidString: printingID), id.uuidString.lowercased() == printingID,
              let physical = registry.physicalCatalog, let printing = physical.printingByID[id],
              printing.status == .verified,
              let variantID, printing.finishes.contains(where: { $0.finish.rawValue == variantID }) else {
            throw CatalogLookupError.invalidPrintingChoice
        }
    }

    /// Browse/import explicitly name a physical UUID. Discovery still needs a
    /// reviewed complete universe and enough visible evidence to distinguish it.
    func resolution(forPrintingID id: UUID) throws -> CardCatalog.CatalogResolution {
        guard let physical = registry.physicalCatalog, let printing = physical.printingByID[id],
              let printings = physical.reviewedPrintings(for: printing.identity.footer),
              printings.contains(where: { $0.id == id }),
              let canonical = physical.canonicalByID[printing.identity.canonicalCardID],
              candidate(printing, canonical: canonical).selectionEvidence(among: printings.map { candidate($0, canonical: canonical) }) != .insufficient else {
            throw CatalogLookupError.invalidPrintingChoice
        }
        return try resolution(printing, canonical: canonical)
    }

    func validateCollectionMutation(printingID: String, catalogProviderID: String?, variantID: String?,
                                    itemKindRaw: String, collectionKey: String) throws {
        guard itemKindRaw == CollectionItemKind.rawCard.rawValue,
              let id = UUID(uuidString: printingID), id.uuidString.lowercased() == printingID,
              catalogProviderID == nil || catalogProviderID == printingID,
              let finish = variantID.flatMap(LorcanaPhysicalFinish.init(rawValue:)) else {
            throw CatalogLookupError.invalidPrintingChoice
        }
        let card = try resolution(forPrintingID: id).card
        guard card.variantEvidence.catalogVariants.contains(where: { $0.id == finish.rawValue }),
              card.collectionKey(variant: finish.variant) == collectionKey else { throw CatalogLookupError.invalidPrintingChoice }
    }

    private func candidate(_ printing: LorcanaPhysicalPrinting, canonical: LorcanaCanonicalCard) -> PhysicalPrintingCandidate {
        .init(id: printing.id.uuidString.lowercased(), game: game, canonicalCardID: canonical.id.uuidString.lowercased(),
              language: printing.identity.footer.language, catalogGeneration: generation, name: canonical.displayName,
              printedIdentifier: printing.identity.footer.displayIdentifier, releaseLabel: printing.setName,
              treatmentLabel: printing.artworkLabel, distributionLabel: printing.distributionLabel,
              thumbnailURL: printing.imageURL, artworkID: printing.identity.artworkID.uuidString.lowercased(),
              distinctionLabels: ["Size: \(printing.identity.size.label)", "Stamp: \(printing.identity.stamp ?? "Unstamped")",
                                  "Layout: \(printing.identity.layout)"])
    }

    private func resolution(_ printing: LorcanaPhysicalPrinting, canonical: LorcanaCanonicalCard) throws -> CardCatalog.CatalogResolution {
        let footer = printing.identity.footer
        let variants = printing.finishes.map { $0.finish.variant }.sorted { $0.choicePriority < $1.choicePriority }
        let siblings = registry.physicalCatalog?.reviewedPrintings(for: footer) ?? []
        let name: String
        if siblings.count > 1 {
            let choices = siblings.map { candidate($0, canonical: canonical) }
            name = canonical.displayName + " · " + candidate(printing, canonical: canonical).compactChoiceLabel(among: choices)
        } else if printing.identity.size == .oversized || printing.identity.stamp != nil || printing.identity.layout != "normal" {
            name = canonical.displayName + " · " + [printing.identity.size == .oversized ? "Oversized" : nil,
                printing.identity.stamp, printing.identity.layout == "normal" ? nil : printing.identity.layout].compactMap { $0 }.joined(separator: " · ")
        } else { name = canonical.displayName }
        let card = try ResolvedCatalogCard(game: game, physicalPrintingID: printing.id.uuidString.lowercased(),
            canonicalCardID: canonical.id.uuidString.lowercased(), language: footer.language, name: name,
            setName: printing.setName, setCode: printing.providerSetCode, cardNumber: footer.collectorNumber,
            printedIdentifier: footer.displayIdentifier, rarity: registry.familiesByFooter[footer]?.rarity,
            displayImageURL: printing.imageURL, thumbnailImageURL: printing.imageURL,
            variantEvidence: .init(game: game, setID: footer.setScopeID,
                cardNumber: footer.collectorNumber, catalogVariants: variants))
        return .init(card, retrievedAt: registry.physicalCatalog!.manifest.reviewedAt, path: .cacheHit)
    }
}

struct LorcanaVariantPolicy: GameVariantPolicy {
    let selectableVariants: [PhysicalVariant]
    init(registry: LorcanaCatalogRegistry) {
        guard let physical = registry.physicalCatalog else { selectableVariants = []; return }
        let finishes = Set(physical.printingByID.values.filter { $0.status == .verified }
            .flatMap { $0.finishes.map(\.finish) })
        selectableVariants = finishes.map(\.variant).sorted { $0.choicePriority < $1.choicePriority }
    }
}

/// Explicit research injection only; appDefaults does not register this module.
/// Collection writes are available only through the explicit isolated debug kit.
struct LorcanaGameRuntime: Sendable {
    let registry: LorcanaCatalogRegistry
    var coordinator: LorcanaCatalogCoordinator? = nil
    private var collectionWrites = false
    init(registry: LorcanaCatalogRegistry, coordinator: LorcanaCatalogCoordinator? = nil) {
        self.registry = registry; self.coordinator = coordinator
    }
    #if DEBUG && LOCAL_ONLY_SIGNING
    init(reviewedRegistry registry: LorcanaCatalogRegistry, coordinator: LorcanaCatalogCoordinator,
         collectionWrites: Bool) {
        self.registry = registry; self.coordinator = coordinator; self.collectionWrites = collectionWrites
    }
    #endif
    var runtime: CardGameRuntime {
        .init(descriptor: .init(game: .lorcana, displayName: "Disney Lorcana", sortOrder: 3,
                              capabilities: collectionWrites ? [.scan, .browse, .collectionWrite] : [.scan, .browse]),
              variantPolicy: LorcanaVariantPolicy(registry: registry), recognizer: LorcanaRecognitionAdapter(registry: registry),
              catalog: LorcanaCatalogAdapter(registry: registry), browse: LorcanaBrowseAdapter(registry: registry),
              importer: LorcanaImportAdapter(registry: registry), activationSource: coordinator,
              requiresLaunchActivation: false)
    }
}
