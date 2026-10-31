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

    func lookup(_ identifier: ScanIdentifier) async throws -> CatalogLookupOutcome {
        guard identifier.catalogGeneration == generation else { throw CatalogLookupError.staleCatalog }
        let key = try footer(for: identifier)
        guard let family = registry.familiesByFooter[key] else { return .catalogIncomplete(nil) }
        // A source print family cannot stand in for an app-owned physical UUID.
        return .catalogIncomplete(.init(id: key.familyID, game: game, name: family.displayName,
                                        printedIdentifier: key.displayIdentifier, language: key.language))
    }

    func resolve(_ candidate: PhysicalPrintingCandidate, for identifier: ScanIdentifier) async throws -> CardCatalog.CatalogResolution {
        throw CatalogLookupError.invalidPrintingChoice
    }
}

struct LorcanaVariantPolicy: GameVariantPolicy {
    let selectableVariants: [PhysicalVariant] = []
}

/// Explicit research injection only; appDefaults does not register this module.
/// Scan capability means footer evidence can be retained, not collection writes.
struct LorcanaGameRuntime: Sendable {
    let registry: LorcanaCatalogRegistry
    var runtime: CardGameRuntime {
        .init(descriptor: .init(game: .lorcana, displayName: "Disney Lorcana", sortOrder: 3, capabilities: [.scan]),
              variantPolicy: LorcanaVariantPolicy(), recognizer: LorcanaRecognitionAdapter(registry: registry),
              catalog: LorcanaCatalogAdapter(registry: registry))
    }
}
