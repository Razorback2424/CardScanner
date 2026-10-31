import Foundation

/// Existing Scryfall card resolution, including signed token/art child routing.
/// The provider generation retains the legacy coordinator's routing behavior;
/// signed activation snapshots are added with the remaining legacy migration.
struct MagicCatalogAdapter: GameCatalogAdapter {
    let game = CardGame.magic
    let generation = "magic-provider-v1"
    var source = ScryfallService()
    var coordinator: MagicCatalogCoordinator? = nil

    func prepareLookupIdentifier(_ identifier: ScanIdentifier) throws -> ScanIdentifier {
        guard identifier.game == game,
              identifier.catalogGeneration == nil || identifier.catalogGeneration == generation,
              case .magic = identifier.legacyIdentity else { throw CatalogLookupError.staleCatalog }
        return try .init(game: identifier.game, namespace: identifier.namespace, fields: identifier.fields,
            displayIdentifier: identifier.displayIdentifier, suppressionIdentity: identifier.suppressionIdentity,
            catalogGeneration: generation)
    }

    func identifierForRetry(_ identifier: ScanIdentifier) throws -> ScanIdentifier {
        try prepareLookupIdentifier(identifier)
    }

    func lookup(_ identifier: ScanIdentifier) async throws -> CatalogLookupOutcome {
        let prepared = try prepareLookupIdentifier(identifier)
        guard case let .magic(setCode, collectorNumber, language, contentKind) = prepared.legacyIdentity else {
            throw CatalogLookupError.invalidAdapterOutcome
        }
        return .resolved(try await resolution(setCode: setCode, collectorNumber: collectorNumber,
            language: language, contentKind: contentKind))
    }

    func resolve(_ candidate: PhysicalPrintingCandidate, for identifier: ScanIdentifier) async throws -> CardCatalog.CatalogResolution {
        throw CatalogLookupError.invalidPrintingChoice
    }

    private func resolution(setCode: String, collectorNumber: String, language: String,
                            contentKind: MagicContentKind) async throws -> CardCatalog.CatalogResolution {
        let scryfall = source
        let magicCatalogCoordinator = coordinator
        guard contentKind != .regular else {
            // Unchanged fast path. An ordinary footer resolves exactly
            // as it always has.
            return CardCatalog.CatalogResolution(
                .magic(
                    try await scryfall.fetchCard(
                        setCode: setCode,
                        collectorNumber: collectorNumber,
                        language: language
                    )
                )
            )
        }

        // A token or art card prints its *parent's* code, so the printed
        // identity has to be mapped to the child set before anything is
        // fetched. In remote-authority mode this lookup never consults
        // Scryfall /sets; the signed registry is the only child-routing
        // authority.
        let childCode: String
        let childLayoutKinds: Set<String>
        if let magicCatalogCoordinator {
            await magicCatalogCoordinator.loadPersistedOrBundled()
        }
        if let magicCatalogCoordinator,
           await magicCatalogCoordinator.currentRolloutMode == .remoteAuthority {
            let registry = await magicCatalogCoordinator.registry
            guard let child = registry.child(for: contentKind, parentCode: setCode) else {
                throw ScryfallError.identityMismatch
            }
            childCode = child.code
            childLayoutKinds = contentKind.acceptedLayouts
        } else {
            let children = try await scryfall.fetchChildSets()
            guard let child = ScryfallService.childSet(
                for: contentKind,
                parentCode: setCode,
                in: children
            ) else {
                // No child set, or more than one with no way to choose.
                // Refusing is the point: reinterpreting an explicit marker
                // as an ordinary card is the bug this exists to prevent.
                throw ScryfallError.identityMismatch
            }
            childCode = child.code
            childLayoutKinds = contentKind.acceptedLayouts
            if let magicCatalogCoordinator,
               await magicCatalogCoordinator.currentRolloutMode == .remoteValidationOnly {
                let registry = await magicCatalogCoordinator.registry
                let mismatches = registry.legacyParityMismatches(
                    scanner: [],
                    browse: [],
                    routing: children
                )
                await magicCatalogCoordinator.recordLegacyParity(
                    mismatches.filter { $0.surface == .routing },
                    replacing: [.routing]
                )
            }
        }

        let card = try await scryfall.fetchCard(
            setCode: childCode,
            collectorNumber: collectorNumber,
            language: language,
            requiresScannableCard: false
        )

        // Both directions are checked. The returned record must be from
        // the child set that was asked for, and its layout must match
        // the kind the marker claimed — otherwise a token could arrive
        // through an ordinary lookup, which is the same bug reversed.
        guard card.setCode.caseInsensitiveCompare(childCode) == .orderedSame,
              let layout = card.layout,
              childLayoutKinds.contains(layout) else {
            throw ScryfallError.identityMismatch
        }
        return CardCatalog.CatalogResolution(.magic(card))
    }
}

extension GameCatalogAdapterRegistry {
    func installingLegacyDefaults(magicCoordinator: MagicCatalogCoordinator?) -> Self {
        guard adapter(for: .magic) == nil else { return self }
        return replacing(MagicCatalogAdapter(coordinator: magicCoordinator))
    }
}
