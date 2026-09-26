import Foundation

/// Persists scanner failures locally so leaving the Scan tab or relaunching the
/// app does not discard work the collector still needs to resolve.
actor UnresolvedScanStore {
    static let shared = UnresolvedScanStore()
    static let rowLimit = 50

    let fileURL: URL
    private var preservedReadOnlyRecords: [UUID: UnresolvedScanRecord] = [:]

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.fileURL = support
                .appendingPathComponent("Scanner", isDirectory: true)
                .appendingPathComponent("unresolved-scans.json")
        }
    }

    func load(
        registry: PokemonCatalogRegistry = .bundledSeed,
        magicDefinitions: [MagicSetDefinition] = MagicSetSnapshot.definitions
    ) -> [UnresolvedScan] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder().decode([UnresolvedScanRecord].self, from: data)
        else { return [] }

        var lastIndexByID: [UUID: Int] = [:]
        for (index, record) in records.enumerated() {
            lastIndexByID[record.id] = index
        }
        let uniqueRecords = records.enumerated().compactMap { index, record in
            lastIndexByID[record.id] == index ? record : nil
        }
        let magicByCode = Dictionary(
            magicDefinitions.map { ($0.code.uppercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        preservedReadOnlyRecords.removeAll(keepingCapacity: true)
        return uniqueRecords.suffix(Self.rowLimit).map { record in
            let scan = record.rehydrate(registry: registry, magicByCode: magicByCode)
            if scan.isReadOnly {
                preservedReadOnlyRecords[scan.id] = record
            }
            return scan
        }
    }

    func save(_ scans: [UnresolvedScan]) {
        let retainedScans = scans
            .sorted { $0.createdAt < $1.createdAt }
            .suffix(Self.rowLimit)
        let records = retainedScans.map { scan in
            if scan.isReadOnly, let original = preservedReadOnlyRecords[scan.id] {
                return original
            }
            return UnresolvedScanRecord(scan: scan)
        }
        let retainedReadOnlyIDs = Set(retainedScans.filter(\.isReadOnly).map(\.id))
        preservedReadOnlyRecords = preservedReadOnlyRecords.filter {
            retainedReadOnlyIDs.contains($0.key)
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            Self.excludeFromBackup(fileURL.deletingLastPathComponent())
            let data = try JSONEncoder().encode(Array(records))
            try data.write(to: fileURL, options: .atomic)
            Self.excludeFromBackup(fileURL)
        } catch {
            // Persistence is best effort at this boundary. The in-memory list
            // stays actionable for the current session if storage is full or
            // temporarily unavailable.
        }
    }

    private static func excludeFromBackup(_ url: URL) {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutableURL.setResourceValues(values)
    }
}

/// Deliberately contains identity evidence only. Collection quantities,
/// treatments, prices, and market data are never written to this file.
struct UnresolvedScanRecord: Codable, Equatable, Sendable {
    enum Reason: String, Codable, Sendable {
        case noCatalogEntry
        case noConfirmedMatch
        case lookupFailed
        case providerUnavailable
        case saveFailed
    }

    let id: UUID
    let createdAt: Date
    let game: CardGame
    let reason: Reason
    let saveCandidateID: UUID?
    let displayIdentifier: String
    let pokemonLocalID: String?
    let pokemonDenominator: Int?
    let pokemonSubsetPrefix: String?
    let setPrintedCode: String?
    let providerSetID: String?
    let magicSetCode: String?
    let magicCollectorNumber: String?
    let magicContentKind: MagicContentKind?
    let titleReadings: [String]
    let catalogIdentifier: String
    let inferredNameReadings: [String]?
    let candidateProviderIDsAndNames: [UnresolvedCandidateHint]
    let slabEvidence: GradedSlabEvidence?
    let mergeSessionID: UUID?
    let resolvedProviderID: String?
    let magicLanguage: String?

    init(scan: UnresolvedScan) {
        id = scan.id
        createdAt = scan.createdAt
        game = scan.game
        switch scan.reason {
        case .noCatalogEntry: reason = .noCatalogEntry; saveCandidateID = nil
        case .noConfirmedMatch: reason = .noConfirmedMatch; saveCandidateID = nil
        case .lookupFailed: reason = .lookupFailed; saveCandidateID = nil
        case .providerUnavailable: reason = .providerUnavailable; saveCandidateID = nil
        case let .saveFailed(candidateID): reason = .saveFailed; saveCandidateID = candidateID
        }
        displayIdentifier = scan.displayIdentifier
        catalogIdentifier = scan.requestEvidence.catalogIdentifier
        titleReadings = scan.requestEvidence.titleReadings
        inferredNameReadings = scan.subject.inferredNameReadings
        slabEvidence = scan.subject.slab
        mergeSessionID = scan.mergeSessionID
        resolvedProviderID = scan.resolvedProviderID
        candidateProviderIDsAndNames = UnresolvedScan.mergedHints(
            scan.candidateHints,
            candidates: scan.candidates
        )

        switch scan.identifier {
        case let .pokemon(code, localID, denominator, definition):
            pokemonLocalID = localID
            pokemonDenominator = denominator
            pokemonSubsetPrefix = nil
            setPrintedCode = code
            providerSetID = definition.tcgdexSetID
            magicSetCode = nil
            magicCollectorNumber = nil
            magicContentKind = nil
            magicLanguage = nil
        case let .pokemonPromo(prefix, localID, definition):
            pokemonLocalID = localID
            pokemonDenominator = nil
            pokemonSubsetPrefix = prefix
            setPrintedCode = nil
            providerSetID = definition.tcgdexSetID
            magicSetCode = nil
            magicCollectorNumber = nil
            magicContentKind = nil
            magicLanguage = nil
        case let .pokemonHistorical(evidence):
            pokemonLocalID = evidence.number.localID
            pokemonDenominator = evidence.number.denominator
            if case let .subset(prefix) = evidence.number.scheme {
                pokemonSubsetPrefix = prefix
            } else {
                pokemonSubsetPrefix = nil
            }
            setPrintedCode = nil
            providerSetID = nil
            magicSetCode = nil
            magicCollectorNumber = nil
            magicContentKind = nil
            magicLanguage = nil
        case let .magic(code, collectorNumber, language, contentKind):
            pokemonLocalID = nil
            pokemonDenominator = nil
            pokemonSubsetPrefix = nil
            setPrintedCode = nil
            providerSetID = nil
            magicSetCode = code
            magicCollectorNumber = collectorNumber
            magicContentKind = contentKind
            magicLanguage = language
        }
    }

    fileprivate func rehydrate(
        registry: PokemonCatalogRegistry,
        magicByCode: [String: MagicSetDefinition]
    ) -> UnresolvedScan {
        let identifier: ScanIdentifier
        var readOnly = false
        switch game {
        case .pokemon:
            if let code = setPrintedCode,
               let definition = registry.pokemonSetDefinition(forPrintedCode: code),
               let localID = pokemonLocalID,
               let denominator = pokemonDenominator {
                identifier = .pokemon(
                    setCode: code,
                    cardNumber: localID,
                    printedTotal: denominator,
                    setDefinition: definition
                )
            } else if let prefix = pokemonSubsetPrefix,
                      let definition = registry.pokemonPromoSetDefinition(forPrefix: prefix),
                      let localID = pokemonLocalID {
                identifier = .pokemonPromo(prefix: prefix, localID: localID, setDefinition: definition)
            } else if let localID = pokemonLocalID,
                      let denominator = pokemonDenominator {
                let scheme: PokemonPrintedNumberScheme = pokemonSubsetPrefix.map {
                    .subset(prefix: $0)
                } ?? .officialSet
                identifier = .pokemonHistorical(
                    PokemonHistoricalScanEvidence(
                        number: PokemonPrintedNumberEvidence(
                            localID: localID,
                            denominator: denominator,
                            scheme: scheme
                        ),
                        titleCandidates: titleReadings
                    )
                )
                if setPrintedCode != nil { readOnly = true }
            } else {
                identifier = Self.fallbackPokemonIdentifier(
                    code: setPrintedCode,
                    localID: pokemonLocalID,
                    denominator: pokemonDenominator,
                    prefix: pokemonSubsetPrefix,
                    providerSetID: providerSetID
                )
                readOnly = true
            }
        case .magic:
            guard let code = magicSetCode,
                  magicByCode[code.uppercased()] != nil,
                  let collectorNumber = magicCollectorNumber else {
                identifier = .magic(
                    setCode: magicSetCode ?? "???",
                    collectorNumber: magicCollectorNumber ?? "?",
                    language: magicLanguage ?? "en",
                    contentKind: magicContentKind ?? .regular
                )
                readOnly = true
                break
            }
            identifier = .magic(
                setCode: code,
                collectorNumber: collectorNumber,
                language: magicLanguage ?? "en",
                contentKind: magicContentKind ?? .regular
            )
        }

        let subject = ScanSubject(
            identifier: identifier,
            slab: slabEvidence,
            inferredNameReadings: inferredNameReadings
        )
        let reasonValue: UnresolvedReason
        switch reason {
        case .noCatalogEntry: reasonValue = .noCatalogEntry
        case .noConfirmedMatch: reasonValue = .noConfirmedMatch
        case .lookupFailed: reasonValue = .lookupFailed
        case .providerUnavailable: reasonValue = .providerUnavailable
        case .saveFailed: reasonValue = .saveFailed(inMemoryCandidateID: saveCandidateID)
        }
        return UnresolvedScan(
            id: id,
            subject: subject,
            reason: reasonValue,
            createdAt: createdAt,
            requestEvidence: UnresolvedScanRequestEvidence(
                catalogIdentifier: catalogIdentifier,
                titleReadings: titleReadings
            ),
            isReadOnly: readOnly,
            storedDisplayIdentifier: readOnly ? displayIdentifier : nil,
            candidateHints: candidateProviderIDsAndNames,
            mergeSessionID: {
                if case .pokemonHistorical = identifier {
                    return mergeSessionID ?? id
                }
                return nil
            }(),
            resolvedProviderID: resolvedProviderID
        )
    }

    private static func fallbackPokemonIdentifier(
        code: String?,
        localID: String?,
        denominator: Int?,
        prefix: String?,
        providerSetID: String?
    ) -> ScanIdentifier {
        if let prefix, let localID {
            return .pokemonPromo(
                prefix: prefix,
                localID: localID,
                setDefinition: PokemonPromoSetDefinition(
                    printedPrefix: prefix,
                    tcgdexSetID: providerSetID ?? prefix.lowercased(),
                    catalogLocalIDPrefix: prefix,
                    localIDPadWidth: 3
                )
            )
        }
        if let code, let localID, let denominator {
            return .pokemon(
                setCode: code,
                cardNumber: localID,
                printedTotal: denominator,
                setDefinition: PokemonSetDefinition(
                    printedCode: code,
                    tcgdexSetID: providerSetID ?? code.lowercased(),
                    officialCount: denominator,
                    releaseIndex: Int.max
                )
            )
        }
        return .pokemonHistorical(
            PokemonHistoricalScanEvidence(
                number: PokemonPrintedNumberEvidence(
                    localID: localID ?? "?",
                    denominator: denominator ?? 0,
                    scheme: prefix.map(PokemonPrintedNumberScheme.subset(prefix:)) ?? .officialSet
                ),
                titleCandidates: []
            )
        )
    }
}
