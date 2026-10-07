import Foundation

/// Existing Scryfall card resolution, including signed token/art child routing.
/// The provider generation retains the legacy coordinator's routing behavior;
/// signed activation snapshots are added with the remaining legacy migration.
struct MagicCatalogAdapter: GameCatalogAdapter {
    let game = CardGame.magic
    static let providerGeneration = "magic-provider-v1"
    let generation = providerGeneration
    var source = ScryfallService()
    var coordinator: MagicCatalogCoordinator? = nil
    var historicalSnapshot: MagicHistoricalLocalSnapshot? = nil
    var historicalStore: MagicHistoricalLocalStore? = nil
    var historicalSourceContext: String? = nil
    /// Explicit local pilot injection; the production default remains off.
    var historicalEnabled = false
    var historicalNow: @Sendable () -> Date = { .now }

    func prepareLookupIdentifier(_ identifier: ScanIdentifier) throws -> ScanIdentifier {
        guard identifier.game == game,
              identifier.catalogGeneration == nil || identifier.catalogGeneration == generation else { throw CatalogLookupError.staleCatalog }
        switch identifier.namespace {
        case "historical-live":
            _ = try MagicHistoricalLiveEvidence.decode(identifier)
        case "card":
            guard Set(identifier.fields.map(\.key)) == ["setCode", "collectorNumber", "language", "contentKind"],
                  case .magic = identifier.legacyIdentity else { throw CatalogLookupError.invalidAdapterOutcome }
        case "historical":
            let evidence = try MagicHistoricalScanEvidence.decode(identifier)
            guard let snapshot = historicalSnapshot,
                  evidence.profileGeneration == snapshot.generation,
                  evidence.indexGeneration == snapshot.index.generation else { throw CatalogLookupError.staleCatalog }
        default: throw CatalogLookupError.invalidAdapterOutcome
        }
        return try .init(game: identifier.game, namespace: identifier.namespace, fields: identifier.fields,
            displayIdentifier: identifier.displayIdentifier, suppressionIdentity: identifier.suppressionIdentity,
            catalogGeneration: generation)
    }

    func identifierForRetry(_ identifier: ScanIdentifier) throws -> ScanIdentifier {
        try prepareLookupIdentifier(identifier)
    }

    func lookup(_ identifier: ScanIdentifier) async throws -> CatalogLookupOutcome {
        let prepared = try prepareLookupIdentifier(identifier)
        if prepared.namespace == "historical-live" { return try await liveHistoricalLookup(prepared) }
        if prepared.namespace == "historical" { return try await historicalLookup(prepared) }
        guard case let .magic(setCode, collectorNumber, language, contentKind) = prepared.legacyIdentity else {
            throw CatalogLookupError.invalidAdapterOutcome
        }
        return .resolved(try await resolution(setCode: setCode, collectorNumber: collectorNumber,
            language: language, contentKind: contentKind))
    }

    func resolve(_ candidate: PhysicalPrintingCandidate, for identifier: ScanIdentifier) async throws -> CardCatalog.CatalogResolution {
        if identifier.namespace == "historical-live" {
            let prepared = try prepareLookupIdentifier(identifier)
            let evidence = try MagicHistoricalLiveEvidence.decode(prepared)
            guard evidence.englishConfirmed else { throw CatalogLookupError.invalidPrintingChoice }
            let family = try await liveHistoricalFamily(evidence)
            guard let member = family.first(where: { $0.id == candidate.id }),
                  candidate == liveHistoricalCandidate(member, evidence: evidence) else { throw CatalogLookupError.invalidPrintingChoice }
            let card = try await source.fetchCard(id: member.id, ignoringCache: true)
            guard Self.validHistoricalCard(card, evidence: evidence, now: historicalNow()),
                  card.id == member.id, card.oracleID == member.oracleID, card.setID == member.setID,
                  card.setCode == member.setCode, card.collectorNumber == member.collectorNumber,
                  card.name == member.name, card.layout == member.layout, card.releasedAt == member.releasedAt,
                  Set(card.finishes ?? []) == Set(member.finishes ?? []) else { throw ScryfallError.identityMismatch }
            try Task.checkCancellation()
            return .init(.init(legacy: .magic(card), canonicalCardID: card.oracleID))
        }
        guard identifier.namespace == "historical" else { throw CatalogLookupError.invalidPrintingChoice }
        let prepared = try prepareLookupIdentifier(identifier)
        let evidence = try MagicHistoricalScanEvidence.decode(prepared)
        let query = try await historicalQuery(prepared)
        guard evidence.permitsEnglishAcquisition,
              let record = query.eligiblePhaseOneRecords.first(where: { $0.printingID == candidate.id }),
              candidate == historicalCandidate(record, evidence: evidence),
              candidate.catalogGeneration == generation else { throw CatalogLookupError.invalidPrintingChoice }
        return try await hydrateHistorical(record, identifier: prepared, automatic: false)
    }

    func lookupPrintingChoices(_ identifier: ScanIdentifier) async throws -> CatalogLookupOutcome? {
        if identifier.namespace == "historical-live" { return try await liveHistoricalLookup(prepareLookupIdentifier(identifier)) }
        guard identifier.namespace == "historical" else { return nil }
        return try await historicalLookup(prepareLookupIdentifier(identifier), allowsAutomatic: false)
    }

    func acceptsCompletion(for identifier: ScanIdentifier, fromGeneration: String) -> Bool {
        guard fromGeneration == generation, (try? prepareLookupIdentifier(identifier)) != nil else { return false }
        return true
    }

    func validateLookupContext(_ identifier: ScanIdentifier) async throws {
        if identifier.namespace == "historical-live" { _ = try prepareLookupIdentifier(identifier); return }
        guard identifier.namespace == "historical" else { return }
        _ = try await historicalQuery(identifier)
    }

    func validateAcquisition(_ identifier: ScanIdentifier, printingID: String, automatic: Bool) async throws {
        if identifier.namespace == "historical-live" {
            let evidence = try MagicHistoricalLiveEvidence.decode(prepareLookupIdentifier(identifier))
            // Title/number retrieval cannot automatically select an old printing.
            guard !automatic, evidence.englishConfirmed,
                  try await liveHistoricalFamily(evidence).contains(where: { $0.id == printingID }) else {
                throw CatalogLookupError.invalidPrintingChoice
            }
            return
        }
        guard identifier.namespace == "historical" else { return }
        let evidence = try MagicHistoricalScanEvidence.decode(identifier)
        let query = try await historicalQuery(identifier)
        guard evidence.permitsEnglishAcquisition,
              query.eligiblePhaseOneRecords.contains(where: { $0.printingID == printingID }) else {
            throw CatalogLookupError.invalidPrintingChoice
        }
        if automatic {
            guard query.universeIsCurrent, query.matchingRecords.count == 1 else { throw CatalogLookupError.catalogIncomplete(nil) }
            guard try await source.hasCurrentHistoricalUniverse(title: evidence.title,
                collectorNumber: evidence.collectorNumber, expectedIDs: Set(query.matchingRecords.map(\.printingID))) else {
                throw CatalogLookupError.catalogIncomplete(nil)
            }
            // The bounded provider request may overlap expiry or activation.
            let rechecked = try await historicalQuery(identifier)
            guard rechecked.universeIsCurrent else { throw CatalogLookupError.catalogIncomplete(nil) }
        }
    }

    private func historicalQuery(_ identifier: ScanIdentifier) async throws -> MagicHistoricalIndexSnapshot.Query {
        _ = try prepareLookupIdentifier(identifier)
        guard historicalEnabled, let snapshot = historicalSnapshot else { throw CatalogLookupError.catalogIncomplete(nil) }
        if let historicalStore, !(await historicalStore.isCurrent(snapshot.generation)) { throw CatalogLookupError.staleCatalog }
        let evidence = try MagicHistoricalScanEvidence.decode(identifier)
        guard evidence.denominator == 143 else { throw CatalogLookupError.invalidAdapterOutcome }
        return try snapshot.index.query(title: evidence.title, collectorNumber: evidence.collectorNumber,
            profiles: snapshot.profiles, currentSourceContext: historicalSourceContext, now: historicalNow())
    }

    static let supportedHistoricalLayouts: Set<String> = ["normal", "split", "flip", "transform", "leveler"]

    static func validHistoricalCard(_ card: ScryfallCard, evidence: MagicHistoricalLiveEvidence, now: Date) -> Bool {
        let names = [card.name] + (card.cardFaces ?? []).compactMap(\.name)
        guard card.object == "card", UUID(uuidString: card.id) != nil,
              card.oracleID.flatMap(UUID.init(uuidString:)) != nil,
              card.setID.flatMap(UUID.init(uuidString:)) != nil, !card.setCode.isEmpty,
              card.language == "en", !card.digital, card.games?.contains("paper") == true, card.oversized == false,
              let layout = card.layout, supportedHistoricalLayouts.contains(layout),
              let day = card.releasedAt, day < "2014-07-18", let date = FlexibleDate.parse(day), date <= now,
              names.contains(where: { MagicHistoricalTitleVocabulary.normalizedTitle($0) == MagicHistoricalTitleVocabulary.normalizedTitle(evidence.title) }),
              let finishes = card.finishes, !finishes.isEmpty, Set(finishes).count == finishes.count,
              finishes.allSatisfy({ ["nonfoil", "foil", "etched"].contains($0) }) else { return false }
        return true
    }

    private func liveHistoricalFamily(_ evidence: MagicHistoricalLiveEvidence) async throws -> [ScryfallCard] {
        let all = try await source.historicalPrintings(title: evidence.title)
        var eligible: [ScryfallCard] = []
        for card in all {
            guard let layout = card.layout, let oversized = card.oversized else { throw CatalogLookupError.catalogIncomplete(nil) }
            // Explicitly unsupported objects can be omitted. Malformed ordinary
            // printings cannot silently disappear from a supposedly complete list.
            guard Self.supportedHistoricalLayouts.contains(layout), !oversized else { continue }
            guard Self.validHistoricalCard(card, evidence: evidence, now: historicalNow()) else {
                throw CatalogLookupError.catalogIncomplete(nil)
            }
            eligible.append(card)
        }
        guard !eligible.isEmpty else { throw CatalogLookupError.catalogIncomplete(nil) }
        return eligible.sorted {
            let a = $0.collectorNumber.lowercased() == evidence.collectorNumber?.lowercased()
            let b = $1.collectorNumber.lowercased() == evidence.collectorNumber?.lowercased()
            if a != b { return a }
            return ($0.releasedAt ?? "", $0.setCode, $0.collectorNumber, $0.id) < ($1.releasedAt ?? "", $1.setCode, $1.collectorNumber, $1.id)
        }
    }

    private func liveHistoricalLookup(_ identifier: ScanIdentifier) async throws -> CatalogLookupOutcome {
        let evidence = try MagicHistoricalLiveEvidence.decode(identifier)
        let family = try await liveHistoricalFamily(evidence)
        let groupID = Set(family.compactMap(\.oracleID)).count == 1 ? family[0].oracleID! : evidence.choiceGroupID
        return .needsPrintingChoice(canonical: .init(id: groupID, game: .magic,
            name: family[0].name, printedIdentifier: identifier.displayIdentifier, language: "en"),
            candidates: family.map { liveHistoricalCandidate($0, evidence: evidence) })
    }

    private func liveHistoricalCandidate(_ card: ScryfallCard, evidence: MagicHistoricalLiveEvidence) -> PhysicalPrintingCandidate {
        .init(id: card.id, game: .magic, canonicalCardID: card.oracleID!, language: card.language,
            catalogGeneration: generation, name: card.name, printedIdentifier: card.collectorNumber,
            releaseLabel: card.setName, releaseDate: card.releaseDate, thumbnailURL: card.thumbnailImageURL,
            artworkID: nil, distinctionLabels: [card.setCode.uppercased(), card.collectorNumber],
            recognitionGeneration: evidence.recognitionVersion)
    }

    private func historicalLookup(_ identifier: ScanIdentifier, allowsAutomatic: Bool = true) async throws -> CatalogLookupOutcome {
        let evidence = try MagicHistoricalScanEvidence.decode(identifier)
        let query = try await historicalQuery(identifier)
        guard evidence.language != .conflictingOrNonEnglish, query.universeIsCurrent,
              !query.eligiblePhaseOneRecords.isEmpty,
              query.eligiblePhaseOneRecords.count == query.matchingRecords.count,
              let oracleID = query.eligiblePhaseOneRecords.first?.oracleID,
              query.eligiblePhaseOneRecords.allSatisfy({ $0.oracleID == oracleID }) else { return .catalogIncomplete(nil) }
        let candidates = query.eligiblePhaseOneRecords.map { historicalCandidate($0, evidence: evidence) }
        if allowsAutomatic, candidates.count == 1, evidence.permitsEnglishAcquisition {
            return .resolved(try await hydrateHistorical(query.eligiblePhaseOneRecords[0], identifier: identifier, automatic: true))
        }
        return .needsPrintingChoice(canonical: .init(id: oracleID, game: .magic, name: evidence.title,
            printedIdentifier: identifier.displayIdentifier, language: "en"), candidates: candidates)
    }

    private func historicalCandidate(_ record: MagicHistoricalPrintingRecord, evidence: MagicHistoricalScanEvidence) -> PhysicalPrintingCandidate {
        .init(id: record.printingID, game: .magic, canonicalCardID: record.oracleID ?? "",
            language: record.language, catalogGeneration: generation, name: record.name,
            printedIdentifier: record.collectorNumber, releaseLabel: record.setName,
            releaseDate: record.releaseDate.flatMap(FlexibleDate.parse), thumbnailURL: record.thumbnailURL,
            artworkID: record.artworkID, distinctionLabels: [record.setCode.uppercased(), record.collectorNumber],
            recognitionGeneration: evidence.profileGeneration)
    }

    private func hydrateHistorical(_ record: MagicHistoricalPrintingRecord, identifier: ScanIdentifier,
                                   automatic: Bool) async throws -> CardCatalog.CatalogResolution {
        try await validateAcquisition(identifier, printingID: record.printingID, automatic: automatic)
        // Exact ID hydration has its own reviewed legacy contract. The modern
        // date/layout validator and the ordinary set-code path stay unchanged.
        let card = try await source.fetchCard(id: record.printingID)
        guard card.object == "card", card.id == record.printingID, card.oracleID == record.oracleID, card.setID == record.setID,
              card.setCode.lowercased() == record.setCode.lowercased(),
              card.collectorNumber == record.collectorNumber, card.language == "en", !card.digital,
              card.games?.contains("paper") == true, card.oversized == false,
              card.layout == record.layout, card.layout == "normal", card.releasedAt == record.releaseDate,
              Set(card.finishes ?? []) == Set(record.finishes),
              MagicHistoricalEvidenceKey.canonicalTitle(card.name) == MagicHistoricalEvidenceKey.canonicalTitle(record.name) else {
            throw ScryfallError.identityMismatch
        }
        try Task.checkCancellation()
        try await validateAcquisition(identifier, printingID: record.printingID, automatic: automatic)
        return .init(.init(legacy: .magic(card), canonicalCardID: record.oracleID))
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
