import Foundation

/// Persists scanner failures locally so leaving the Scan tab or relaunching the
/// app does not discard work the collector still needs to resolve.
actor UnresolvedScanStore {
    static let shared = UnresolvedScanStore()

    let fileURL: URL
    private var preservedReadOnlyRecords: [UUID: UnresolvedScanRecord] = [:]
    private var originalRecordBytes: [UUID: Data] = [:]
    private var undecodableRecordBytes: [Data] = []
    private enum WriteState { case unloaded, awaitingMerge(UUID), writable, blocked }
    private var writeState: WriteState = .unloaded
    private let readData: @Sendable (URL) throws -> Data

    enum LoadResult {
        case missing
        case loaded([UnresolvedScan], loadID: UUID)
        case failed
    }

    init(fileURL: URL? = nil, readData: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }) {
        self.readData = readData
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
        magicDefinitions: [MagicSetDefinition] = MagicSetSnapshot.definitions,
        gameCatalogAdapters: GameCatalogAdapterRegistry = try! .init(adapters: [])
    ) -> [UnresolvedScan] {
        if case let .loaded(scans, _) = loadResult(registry: registry, magicDefinitions: magicDefinitions,
                                                 gameCatalogAdapters: gameCatalogAdapters) {
            // Compatibility for callers that directly own the returned list.
            // The view model uses loadResult and saves its merged snapshot.
            writeState = .writable
            return scans
        }
        return []
    }

    func loadResult(
        registry: PokemonCatalogRegistry = .bundledSeed,
        magicDefinitions: [MagicSetDefinition] = MagicSetSnapshot.definitions,
        gameCatalogAdapters: GameCatalogAdapterRegistry = try! .init(adapters: [])
    ) -> LoadResult {
        let records: [UnresolvedScanRecord]
        do {
            let data = try readData(fileURL)
            guard let items = try JSONSerialization.jsonObject(with: data) as? [Any] else {
                throw CocoaError(.coderReadCorrupt)
            }
            var decoded: [UnresolvedScanRecord] = []
            var originals: [UUID: Data] = [:]
            var opaque: [Data] = []
            for item in items {
                let bytes = try JSONSerialization.data(withJSONObject: item, options: [.fragmentsAllowed])
                if let record = try? JSONDecoder().decode(UnresolvedScanRecord.self, from: bytes) {
                    decoded.append(record)
                    originals[record.id] = bytes
                } else {
                    // A future or malformed entry cannot hide the other entries
                    // or be silently deleted by their next successful save.
                    opaque.append(bytes)
                }
            }
            records = decoded
            originalRecordBytes = originals
            undecodableRecordBytes = opaque
        } catch {
            if Self.isMissingFile(error) {
                writeState = .writable
                preservedReadOnlyRecords.removeAll()
                originalRecordBytes.removeAll()
                undecodableRecordBytes.removeAll()
                return .missing
            }
            writeState = .blocked
            return .failed
        }

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
        let scans = uniqueRecords.map { record in
            let scan = record.rehydrate(registry: registry, magicByCode: magicByCode,
                                        gameCatalogAdapters: gameCatalogAdapters)
            if scan.isReadOnly {
                preservedReadOnlyRecords[scan.id] = record
            }
            return scan
        }
        let loadID = UUID()
        writeState = .awaitingMerge(loadID)
        return .loaded(scans, loadID: loadID)
    }

    @discardableResult
    func save(_ scans: [UnresolvedScan], completingLoadID: UUID? = nil) -> Bool {
        switch writeState {
        case .blocked:
            return false
        case let .awaitingMerge(loadID):
            guard completingLoadID == loadID else { return false }
        case .unloaded:
            // Early runtime changes must not overwrite recovery work before
            // the view model has loaded and merged it. A new file is safe.
            do {
                _ = try readData(fileURL)
                return false
            } catch {
                guard Self.isMissingFile(error) else {
                    writeState = .blocked
                    return false
                }
                writeState = .writable
            }
        case .writable:
            break
        }
        let retainedScans = scans
            .sorted { $0.createdAt < $1.createdAt }
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
            let encoder = JSONEncoder()
            let objects: [Any] = try records.map { record in
                let bytes: Data
                if retainedReadOnlyIDs.contains(record.id),
                   let original = originalRecordBytes[record.id] {
                    bytes = original
                } else {
                    bytes = try encoder.encode(record)
                }
                return try JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed])
            } + undecodableRecordBytes.map {
                try JSONSerialization.jsonObject(with: $0, options: [.fragmentsAllowed])
            }
            let data = try JSONSerialization.data(withJSONObject: objects)
            try data.write(to: fileURL, options: .atomic)
            writeState = .writable
            Self.excludeFromBackup(fileURL)
            return true
        } catch {
            // Persistence is best effort at this boundary. The in-memory list
            // stays actionable for the current session if storage is full or
            // temporarily unavailable.
            return false
        }
    }

    private static func excludeFromBackup(_ url: URL) {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutableURL.setResourceValues(values)
    }

    private static func isMissingFile(_ error: Swift.Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain
            && (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError)
    }
}

/// Deliberately contains identity evidence only. Collection quantities,
/// treatments, prices, and market data are never written to this file.
struct UnresolvedScanRecord: Codable, Equatable, Sendable {
    enum Reason: String, Codable, Sendable {
        case interrupted
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
    /// Optional so records written before interrupted-copy recovery still decode.
    let isAdditionalCopy: Bool?
    /// Optional to retain compatibility with records written by existing clients.
    let identifierSnapshot: ScanIdentifierSnapshot?
    /// Generation-bound physical choices; absent in legacy records.
    let printingCandidates: [PhysicalPrintingCandidate]?

    init(scan: UnresolvedScan) {
        id = scan.id
        createdAt = scan.createdAt
        game = scan.game
        identifierSnapshot = ScanIdentifierSnapshot(identifier: scan.identifier)
        printingCandidates = scan.printingCandidates
        isAdditionalCopy = scan.isAdditionalCopy
        switch scan.reason {
        case .interrupted: reason = .interrupted; saveCandidateID = nil
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

        switch scan.identifier.legacyIdentity {
        case .opaque:
            pokemonLocalID = nil
            pokemonDenominator = nil
            pokemonSubsetPrefix = nil
            setPrintedCode = nil
            providerSetID = nil
            magicSetCode = nil
            magicCollectorNumber = nil
            magicContentKind = nil
            magicLanguage = nil
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
        magicByCode: [String: MagicSetDefinition],
        gameCatalogAdapters: GameCatalogAdapterRegistry
    ) -> UnresolvedScan {
        let identifier: ScanIdentifier
        var readOnly = false
        if let snapshot = identifierSnapshot,
           snapshot.game == game,
           let restored = try? snapshot.identifier() {
            var current = restored
            readOnly = snapshot.schemaVersion != 1 || snapshot.game != game
                || !CardGameRegistry.standard.supports(restored.game, .scan)
            switch restored.legacyIdentity {
            case let .pokemon(code, number, total, _):
                if let definition = registry.pokemonSetDefinition(forPrintedCode: code) {
                    current = .pokemon(setCode: code, cardNumber: number, printedTotal: total, setDefinition: definition)
                } else { readOnly = true }
            case let .pokemonPromo(prefix, number, _):
                if let definition = registry.pokemonPromoSetDefinition(forPrefix: prefix) {
                    current = .pokemonPromo(prefix: prefix, localID: number, setDefinition: definition)
                } else { readOnly = true }
            case let .magic(code, _, _, _):
                if magicByCode[code.uppercased()] == nil { readOnly = true }
            case .pokemonHistorical: break
            case .opaque:
                readOnly = snapshot.schemaVersion != 1
                    || gameCatalogAdapters.adapter(for: game).flatMap { try? $0.identifierForRetry(restored) } == nil
            }
            identifier = current
        } else {
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
        default:
            identifier = try! ScanIdentifier(
                game: game, namespace: "legacy-unavailable", fields: [],
                displayIdentifier: displayIdentifier, suppressionIdentity: id.uuidString
            )
            readOnly = true
        }
        if identifierSnapshot != nil { readOnly = true }
        }

        let subject = ScanSubject(
            identifier: identifier,
            slab: slabEvidence,
            inferredNameReadings: inferredNameReadings
        )
        let reasonValue: UnresolvedReason
        switch reason {
        case .interrupted: reasonValue = .interrupted
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
            printingCandidates: printingCandidates ?? [],
            requestEvidence: UnresolvedScanRequestEvidence(
                catalogIdentifier: catalogIdentifier,
                titleReadings: titleReadings
            ),
            isAdditionalCopy: isAdditionalCopy ?? false,
            isReadOnly: readOnly,
            storedDisplayIdentifier: readOnly ? displayIdentifier : nil,
            candidateHints: candidateProviderIDsAndNames,
            mergeSessionID: {
                if case .pokemonHistorical = identifier.legacyIdentity {
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
