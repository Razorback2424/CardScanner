import Foundation

public struct PokemonCatalogBuildConfiguration: Sendable {
    public let supportedRulesVersion: Int
    public let maxSetCount: Int
    public let maxCardsPerSet: Int
    public let maxTotalCards: Int
    public let approvedArtworkHosts: Set<String>

    public init(
        supportedRulesVersion: Int = PokemonCatalogCoreContract.rulesVersion,
        maxSetCount: Int = 500,
        maxCardsPerSet: Int = 10_000,
        maxTotalCards: Int = 250_000,
        approvedArtworkHosts: Set<String> = [
            "assets.tcgdex.net",
            "images.pokemon.com",
            "catalog.scan-stash.com",
            "catalog-staging.scan-stash.com"
        ]
    ) {
        self.supportedRulesVersion = supportedRulesVersion
        self.maxSetCount = maxSetCount
        self.maxCardsPerSet = maxCardsPerSet
        self.maxTotalCards = maxTotalCards
        self.approvedArtworkHosts = Set(approvedArtworkHosts.map { $0.lowercased() })
    }
}

public struct PokemonCatalogBuildRequest: Sendable {
    public let fixture: PokemonCatalogProviderFixture
    public let activeRelease: PokemonCatalogRelease?
    public let humanInputs: [PokemonCatalogHumanInput]
    public let revision: Int
    public let generatedAt: Date

    public init(
        fixture: PokemonCatalogProviderFixture,
        activeRelease: PokemonCatalogRelease? = nil,
        humanInputs: [PokemonCatalogHumanInput],
        revision: Int,
        generatedAt: Date
    ) {
        self.fixture = fixture
        self.activeRelease = activeRelease
        self.humanInputs = humanInputs
        self.revision = revision
        self.generatedAt = generatedAt
    }
}

public struct PokemonCatalogSetReview: Codable, Equatable, Sendable {
    public let providerSetID: String
    public let displayName: String
    public let recognitionKind: PokemonCatalogSetDescriptor.RecognitionKind
    public let printedCode: String?
    public let officialCount: Int?
    public let providerCardCount: Int
    public let providerFingerprint: String
    public let status: String

    public init(
        providerSetID: String,
        displayName: String,
        recognitionKind: PokemonCatalogSetDescriptor.RecognitionKind,
        printedCode: String?,
        officialCount: Int?,
        providerCardCount: Int,
        providerFingerprint: String,
        status: String
    ) {
        self.providerSetID = providerSetID
        self.displayName = displayName
        self.recognitionKind = recognitionKind
        self.printedCode = printedCode
        self.officialCount = officialCount
        self.providerCardCount = providerCardCount
        self.providerFingerprint = providerFingerprint
        self.status = status
    }
}

public struct PokemonCatalogReviewReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let revision: Int
    public let generatedAt: Date
    public let addedProviderSetIDs: [String]
    public let changedProviderSetIDs: [String]
    public let excludedProviderSetIDs: [String]
    public let sets: [PokemonCatalogSetReview]

    public init(
        schemaVersion: Int = PokemonCatalogCoreContract.releaseSchemaVersion,
        revision: Int,
        generatedAt: Date,
        addedProviderSetIDs: [String],
        changedProviderSetIDs: [String],
        excludedProviderSetIDs: [String],
        sets: [PokemonCatalogSetReview]
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.generatedAt = generatedAt
        self.addedProviderSetIDs = addedProviderSetIDs
        self.changedProviderSetIDs = changedProviderSetIDs
        self.excludedProviderSetIDs = excludedProviderSetIDs
        self.sets = sets
    }
}

public struct PokemonCatalogBuildResult: Sendable {
    public let release: PokemonCatalogRelease
    public let snapshot: PokemonCatalogSnapshot
    public let report: PokemonCatalogReviewReport

    public init(
        release: PokemonCatalogRelease,
        snapshot: PokemonCatalogSnapshot,
        report: PokemonCatalogReviewReport
    ) {
        self.release = release
        self.snapshot = snapshot
        self.report = report
    }
}

public enum PokemonCatalogBuildError: Error, CustomStringConvertible, Sendable {
    case invalidRevision(Int)
    case duplicateHumanInput(String)
    case humanPrintedCodeRequired(String)
    case humanInputForMissingSet(String)
    case providerPrintedCodeDrift(setID: String, active: String, provider: String)
    case providerPrintedCodeConflict(setID: String, human: String, provider: String)
    case invalidProviderPrintedCode(setID: String, value: String?)
    case missingProviderOfficialCount(String)
    case missingProviderReleaseDate(String)
    case duplicateProviderSet(String)
    case missingProviderSet(String)
    case missingActiveExpansion(String)
    case providerSetIDMismatch(expected: String, received: String)
    case duplicateProviderCard(setID: String, cardID: String)
    case missingCardDetail(setID: String, cardID: String)
    case cardIDMismatch(setID: String, expected: String, received: String)
    case cardSetMismatch(setID: String, cardID: String, received: String)
    case invalidCard(setID: String, cardID: String, reason: String)
    case officialCountMismatch(setID: String, expected: Int, received: Int?)
    case tooManySets(Int)
    case tooManyCards(setID: String, count: Int)
    case tooManyTotalCards(Int)
    case invalidDescriptor(String)
    case unsupportedArtworkURL(String)
    case invalidProviderFingerprint(String)

    public var description: String {
        switch self {
        case .invalidRevision(let revision): return "Invalid release revision: \(revision)"
        case .duplicateHumanInput(let id): return "Duplicate human input for \(id)"
        case .humanPrintedCodeRequired(let id):
            return "A valid provider or operator printed code is required for new set \(id)"
        case .humanInputForMissingSet(let id): return "Human input names missing set \(id)"
        case let .providerPrintedCodeDrift(setID, active, provider):
            return "Provider printed-code drift for \(setID): active \(active), provider \(provider)"
        case let .providerPrintedCodeConflict(setID, human, provider):
            return "Conflicting printed codes for \(setID): operator \(human), provider \(provider)"
        case let .invalidProviderPrintedCode(setID, value):
            return "Provider printed code for \(setID) is invalid: \(value ?? "missing")"
        case .missingProviderOfficialCount(let id):
            return "Provider official count is required for new set \(id)"
        case .missingProviderReleaseDate(let id):
            return "Provider release date is required for new set \(id)"
        case .duplicateProviderSet(let id): return "Duplicate provider set \(id)"
        case .missingProviderSet(let id): return "Provider set details are missing for \(id)"
        case .missingActiveExpansion(let id):
            return "Active expansion \(id) disappeared from the provider directory"
        case let .providerSetIDMismatch(expected, received):
            return "Provider set ID mismatch: expected \(expected), received \(received)"
        case let .duplicateProviderCard(setID, cardID):
            return "Duplicate provider card \(cardID) in set \(setID)"
        case let .missingCardDetail(setID, cardID):
            return "Missing card detail \(cardID) in set \(setID)"
        case let .cardIDMismatch(setID, expected, received):
            return "Card ID mismatch in \(setID): expected \(expected), received \(received)"
        case let .cardSetMismatch(setID, cardID, received):
            return "Card \(cardID) in \(setID) reports set \(received)"
        case let .invalidCard(setID, cardID, reason):
            return "Invalid card \(cardID) in \(setID): \(reason)"
        case let .officialCountMismatch(setID, expected, received):
            let receivedText = received.map { String($0) } ?? "none"
            return "Official count mismatch for \(setID): human claimed \(expected), provider reported \(receivedText)"
        case .tooManySets(let count): return "Provider fixture contains too many sets: \(count)"
        case let .tooManyCards(setID, count):
            return "Provider set \(setID) contains too many cards: \(count)"
        case .tooManyTotalCards(let count): return "Provider fixture contains too many cards: \(count)"
        case .invalidDescriptor(let reason): return "Invalid descriptor: \(reason)"
        case .unsupportedArtworkURL(let url): return "Unsupported artwork URL: \(url)"
        case .invalidProviderFingerprint(let id): return "Could not fingerprint provider set \(id)"
        }
    }
}

public struct PokemonCatalogBuilder: Sendable {
    public let configuration: PokemonCatalogBuildConfiguration

    public init(configuration: PokemonCatalogBuildConfiguration = .init()) {
        self.configuration = configuration
    }

    public func build(_ request: PokemonCatalogBuildRequest) throws -> PokemonCatalogBuildResult {
        guard request.revision > 0 else {
            throw PokemonCatalogBuildError.invalidRevision(request.revision)
        }
        if let active = request.activeRelease, request.revision <= active.revision {
            throw PokemonCatalogBuildError.invalidRevision(request.revision)
        }

        let inputByID = try makeHumanInputIndex(request.humanInputs)
        let activeByID = Dictionary(
            uniqueKeysWithValues: (request.activeRelease?.sets ?? []).map {
                ($0.providerSetID.lowercased(), $0)
            }
        )
        let directory = try normalizedDirectory(request.fixture.directory)
        guard directory.count <= configuration.maxSetCount else {
            throw PokemonCatalogBuildError.tooManySets(directory.count)
        }

        let providerSets = try makeProviderSetIndex(request.fixture.sets)
        let providerCards = try makeProviderCardIndex(request.fixture.cards)
        let automaticReleaseOrders = makeAutomaticReleaseOrders(
            directory: directory,
            providerSets: providerSets,
            activeByID: activeByID,
            inputByID: inputByID,
            activeRelease: request.activeRelease
        )
        var descriptors: [PokemonCatalogSetDescriptor] = []
        var entries: [PokemonCatalogSnapshotEntry] = []
        var checklists: [String: [PokemonCatalogCardSummary]] = [:]
        var setReviews: [PokemonCatalogSetReview] = []
        var added: [String] = []
        var changed: [String] = []
        var totalCards = 0
        let directoryIDs = Set(directory.map { $0.id.lowercased() })

        for row in directory {
            let providerID = row.id.lowercased()
            guard let providerSet = providerSets[providerID] else {
                throw PokemonCatalogBuildError.missingProviderSet(row.id)
            }
            guard providerSet.id.caseInsensitiveCompare(row.id) == .orderedSame else {
                throw PokemonCatalogBuildError.providerSetIDMismatch(
                    expected: row.id,
                    received: providerSet.id
                )
            }

            let existing = activeByID[providerID]
            let descriptor = try makeDescriptor(
                row: row,
                providerSet: providerSet,
                existing: existing,
                humanInput: inputByID[providerID],
                assignedReleaseOrder: automaticReleaseOrders[providerID]
            )
            try validateArtwork(descriptor)

            let (fingerprint, summaries) = try buildChecklist(
                row: row,
                providerSet: providerSet,
                providerCards: providerCards,
                descriptor: descriptor
            )
            totalCards += summaries.count
            guard totalCards <= configuration.maxTotalCards else {
                throw PokemonCatalogBuildError.tooManyTotalCards(totalCards)
            }

            descriptors.append(descriptor)
            let resource = "sets/\(providerID)-\(fingerprint).json"
            entries.append(
                PokemonCatalogSnapshotEntry(
                    providerSetID: providerID,
                    displayName: descriptor.displayName ?? providerSet.name,
                    printedCode: descriptor.printedCode ?? descriptor.printedPrefix,
                    officialCount: descriptor.officialCount,
                    releaseOrder: descriptor.releaseOrder,
                    providerFingerprint: fingerprint,
                    cardCount: summaries.count,
                    resource: resource,
                    artworkFallbackURLs: uniqueArtworkURLs(from: summaries)
                )
            )
            checklists[providerID] = summaries
            setReviews.append(
                PokemonCatalogSetReview(
                    providerSetID: providerID,
                    displayName: descriptor.displayName ?? providerSet.name,
                    recognitionKind: descriptor.recognitionKind,
                    printedCode: descriptor.printedCode ?? descriptor.printedPrefix,
                    officialCount: descriptor.officialCount,
                    providerCardCount: summaries.count,
                    providerFingerprint: fingerprint,
                    status: existing == nil ? "added" : "verified"
                )
            )
            if existing == nil {
                added.append(providerID)
            } else if existing != descriptor {
                changed.append(providerID)
            }
        }

        // Promo and explicitly non-scannable entries may not appear in the
        // ordinary expansion directory. Preserve them from the prior release,
        // but never silently preserve an expansion whose provider disappeared.
        for existing in request.activeRelease?.sets ?? [] {
            let id = existing.providerSetID.lowercased()
            guard !directoryIDs.contains(id) else { continue }
            guard existing.recognitionKind != .expansion else {
                throw PokemonCatalogBuildError.missingActiveExpansion(existing.providerSetID)
            }
            descriptors.append(existing)
            changed.removeAll { $0 == id }
        }

        let knownIDs = Set(directory.map { $0.id.lowercased() })
        for input in request.humanInputs where !knownIDs.contains(input.providerSetID.lowercased()) {
            throw PokemonCatalogBuildError.humanInputForMissingSet(input.providerSetID)
        }

        let release = PokemonCatalogRelease(
            revision: request.revision,
            generatedAt: request.generatedAt,
            sets: descriptors.sorted(by: descriptorSort)
        )
        try PokemonCatalogReleaseValidator.validate(
            release,
            configuration: .init(supportedRulesVersion: configuration.supportedRulesVersion)
        )

        let sortedEntries = entries.sorted { $0.providerSetID < $1.providerSetID }
        let snapshot = PokemonCatalogSnapshot(
            generatedAt: request.generatedAt,
            directoryFingerprint: PokemonCatalogFingerprint.string(
                sortedEntries.map { "\($0.providerSetID)=\($0.providerFingerprint)" }
                    .joined(separator: "\u{1F}")
            ),
            entries: sortedEntries,
            checklists: checklists
        )
        let report = PokemonCatalogReviewReport(
            revision: request.revision,
            generatedAt: request.generatedAt,
            addedProviderSetIDs: added.sorted(),
            changedProviderSetIDs: changed.sorted(),
            excludedProviderSetIDs: request.fixture.directory
                .filter(\.isUnsupportedProduct)
                .map { $0.id.lowercased() }
                .sorted(),
            sets: setReviews.sorted { $0.providerSetID < $1.providerSetID }
        )
        return PokemonCatalogBuildResult(release: release, snapshot: snapshot, report: report)
    }

    private func makeHumanInputIndex(
        _ inputs: [PokemonCatalogHumanInput]
    ) throws -> [String: PokemonCatalogHumanInput] {
        var result: [String: PokemonCatalogHumanInput] = [:]
        for input in inputs {
            let key = input.providerSetID.lowercased()
            guard result[key] == nil else {
                throw PokemonCatalogBuildError.duplicateHumanInput(input.providerSetID)
            }
            result[key] = input
        }
        return result
    }

    private func makeAutomaticReleaseOrders(
        directory: [PokemonCatalogProviderDirectoryRow],
        providerSets: [String: PokemonCatalogProviderSet],
        activeByID: [String: PokemonCatalogSetDescriptor],
        inputByID: [String: PokemonCatalogHumanInput],
        activeRelease: PokemonCatalogRelease?
    ) -> [String: Int] {
        let existingOrders = (activeRelease?.sets.compactMap(\.releaseOrder) ?? [])
            + inputByID.values.compactMap(\.releaseOrder)
        let base = (existingOrders.max() ?? -1) + 1
        let candidates = directory
            .filter { activeByID[$0.id.lowercased()] == nil }
            .filter { inputByID[$0.id.lowercased()]?.releaseOrder == nil }
            .sorted { lhs, rhs in
                let leftDate = inputByID[lhs.id.lowercased()]?.releaseDate
                    ?? providerSets[lhs.id.lowercased()]?.releaseDate
                    ?? lhs.releaseDate
                    ?? ""
                let rightDate = inputByID[rhs.id.lowercased()]?.releaseDate
                    ?? providerSets[rhs.id.lowercased()]?.releaseDate
                    ?? rhs.releaseDate
                    ?? ""
                return (leftDate, lhs.id.lowercased()) < (rightDate, rhs.id.lowercased())
            }
        return Dictionary(
            uniqueKeysWithValues: candidates.enumerated().map { index, row in
                (row.id.lowercased(), base + index)
            }
        )
    }

    private func normalizedDirectory(
        _ rows: [PokemonCatalogProviderDirectoryRow]
    ) throws -> [PokemonCatalogProviderDirectoryRow] {
        var seen = Set<String>()
        var result: [PokemonCatalogProviderDirectoryRow] = []
        for row in rows.filter({ !$0.isUnsupportedProduct }).sorted(by: {
            $0.id.lowercased() < $1.id.lowercased()
        }) {
            guard seen.insert(row.id.lowercased()).inserted else {
                throw PokemonCatalogBuildError.duplicateProviderSet(row.id)
            }
            result.append(row)
        }
        return result
    }

    private func makeProviderSetIndex(
        _ sets: [PokemonCatalogProviderSet]
    ) throws -> [String: PokemonCatalogProviderSet] {
        var result: [String: PokemonCatalogProviderSet] = [:]
        for set in sets {
            let key = set.id.lowercased()
            guard result[key] == nil else {
                throw PokemonCatalogBuildError.duplicateProviderSet(set.id)
            }
            result[key] = set
        }
        return result
    }

    private func makeProviderCardIndex(
        _ cards: [PokemonCatalogProviderCard]
    ) throws -> [String: PokemonCatalogProviderCard] {
        var result: [String: PokemonCatalogProviderCard] = [:]
        for card in cards {
            guard result[card.id.lowercased()] == nil else {
                throw PokemonCatalogBuildError.duplicateProviderCard(
                    setID: "fixture",
                    cardID: card.id
                )
            }
            result[card.id.lowercased()] = card
        }
        return result
    }

    private func makeDescriptor(
        row: PokemonCatalogProviderDirectoryRow,
        providerSet: PokemonCatalogProviderSet,
        existing: PokemonCatalogSetDescriptor?,
        humanInput: PokemonCatalogHumanInput?,
        assignedReleaseOrder: Int?
    ) throws -> PokemonCatalogSetDescriptor {
        if let humanInput,
           humanInput.providerSetID.caseInsensitiveCompare(row.id) != .orderedSame {
            throw PokemonCatalogBuildError.providerSetIDMismatch(
                expected: row.id,
                received: humanInput.providerSetID
            )
        }

        let providerCode = normalizedExpansionCode(providerSet.abbreviation?.official)
        let providerCount = providerSet.cardCount?.official ?? row.cardCount?.official
        let providerReleaseDate = providerSet.releaseDate ?? row.releaseDate
        let providerLogo = nonEmpty(providerSet.logo) ?? nonEmpty(row.logo)
        let providerSymbol = nonEmpty(providerSet.symbol) ?? nonEmpty(row.symbol)

        if let existing {
            if existing.recognitionKind == .expansion,
               let rawProviderCode = providerSet.abbreviation?.official,
               !rawProviderCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let providerCode,
                      PokemonCatalogReleaseValidator.isValidExpansionCode(providerCode) else {
                    throw PokemonCatalogBuildError.invalidProviderPrintedCode(
                        setID: row.id,
                        value: rawProviderCode
                    )
                }
                if existing.printedCode?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased() != providerCode {
                    throw PokemonCatalogBuildError.providerPrintedCodeDrift(
                        setID: row.id,
                        active: existing.printedCode ?? "",
                        provider: providerCode
                    )
                }
            }

            // Authority fields deliberately come only from the active signed
            // descriptor. Provider metadata may improve the Browse experience,
            // but cannot silently change scanner semantics.
            return PokemonCatalogSetDescriptor(
                providerSetID: existing.providerSetID,
                displayName: humanInput?.displayName ?? providerSet.name,
                releaseDate: humanInput?.releaseDate ?? providerReleaseDate ?? existing.releaseDate,
                releaseOrder: existing.releaseOrder,
                recognitionKind: existing.recognitionKind,
                printedCode: existing.printedCode,
                officialCount: existing.officialCount,
                printedPrefix: existing.printedPrefix,
                catalogLocalIDPrefix: existing.catalogLocalIDPrefix,
                localIDPadWidth: existing.localIDPadWidth,
                scanEnabled: existing.scanEnabled,
                logoURL: humanInput?.logoURL ?? providerLogo ?? existing.logoURL,
                symbolURL: humanInput?.symbolURL ?? providerSymbol ?? existing.symbolURL,
                rulesVersion: existing.rulesVersion
            )
        }

        if let humanInput {
            switch humanInput.recognitionKind {
            case .expansion:
                let humanCode = normalizedExpansionCode(humanInput.printedCode)
                let code: String
                if let providerCode,
                   PokemonCatalogReleaseValidator.isValidExpansionCode(providerCode) {
                    if let humanCode, humanCode != providerCode {
                        throw PokemonCatalogBuildError.providerPrintedCodeConflict(
                            setID: row.id,
                            human: humanCode,
                            provider: providerCode
                        )
                    }
                    code = providerCode
                } else if let humanCode,
                          PokemonCatalogReleaseValidator.isValidExpansionCode(humanCode) {
                    code = humanCode
                } else {
                    throw PokemonCatalogBuildError.humanPrintedCodeRequired(row.id)
                }

                let officialCount = humanInput.claimedOfficialCount ?? providerCount
                if humanInput.claimedOfficialCount == nil {
                    guard let officialCount, officialCount > 0 else {
                        throw PokemonCatalogBuildError.missingProviderOfficialCount(row.id)
                    }
                }

                return PokemonCatalogSetDescriptor(
                    providerSetID: row.id.lowercased(),
                    displayName: humanInput.displayName ?? providerSet.name,
                    releaseDate: humanInput.releaseDate ?? providerReleaseDate,
                    releaseOrder: humanInput.releaseOrder ?? assignedReleaseOrder,
                    recognitionKind: .expansion,
                    printedCode: code,
                    officialCount: officialCount,
                    printedPrefix: nil,
                    catalogLocalIDPrefix: nil,
                    localIDPadWidth: nil,
                    scanEnabled: humanInput.scanEnabled,
                    logoURL: humanInput.logoURL ?? providerLogo,
                    symbolURL: humanInput.symbolURL ?? providerSymbol,
                    rulesVersion: humanInput.rulesVersion
                )

            case .promo, .notScannable:
                return PokemonCatalogSetDescriptor(
                    providerSetID: row.id.lowercased(),
                    displayName: humanInput.displayName ?? providerSet.name,
                    releaseDate: humanInput.releaseDate ?? providerReleaseDate,
                    releaseOrder: humanInput.releaseOrder ?? assignedReleaseOrder,
                    recognitionKind: humanInput.recognitionKind,
                    printedCode: normalizedExpansionCode(humanInput.printedCode),
                    officialCount: humanInput.recognitionKind == .notScannable
                        ? nil
                        : humanInput.claimedOfficialCount,
                    printedPrefix: humanInput.printedPrefix?.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).uppercased(),
                    catalogLocalIDPrefix: humanInput.catalogLocalIDPrefix?.uppercased(),
                    localIDPadWidth: humanInput.localIDPadWidth,
                    scanEnabled: humanInput.scanEnabled,
                    logoURL: humanInput.logoURL ?? providerLogo,
                    symbolURL: humanInput.symbolURL ?? providerSymbol,
                    rulesVersion: humanInput.rulesVersion
                )
            }
        }

        guard let providerCode else {
            if providerSet.abbreviation?.official == nil {
                throw PokemonCatalogBuildError.humanPrintedCodeRequired(row.id)
            }
            throw PokemonCatalogBuildError.invalidProviderPrintedCode(
                setID: row.id,
                value: providerSet.abbreviation?.official
            )
        }
        guard PokemonCatalogReleaseValidator.isValidExpansionCode(providerCode) else {
            throw PokemonCatalogBuildError.invalidProviderPrintedCode(
                setID: row.id,
                value: providerSet.abbreviation?.official
            )
        }
        guard let providerCount, providerCount > 0 else {
            throw PokemonCatalogBuildError.missingProviderOfficialCount(row.id)
        }
        guard let providerReleaseDate, isValidReleaseDate(providerReleaseDate) else {
            throw PokemonCatalogBuildError.missingProviderReleaseDate(row.id)
        }
        return PokemonCatalogSetDescriptor(
            providerSetID: row.id.lowercased(),
            displayName: providerSet.name,
            releaseDate: providerReleaseDate,
            releaseOrder: assignedReleaseOrder,
            recognitionKind: .expansion,
            printedCode: providerCode,
            officialCount: providerCount,
            printedPrefix: nil,
            catalogLocalIDPrefix: nil,
            localIDPadWidth: nil,
            scanEnabled: true,
            logoURL: providerLogo,
            symbolURL: providerSymbol,
            rulesVersion: PokemonCatalogCoreContract.rulesVersion
        )
    }

    private func normalizedExpansionCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    private func isValidReleaseDate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let datePrefix = String(trimmed.prefix(10))
        let parts = datePrefix.split(separator: "-")
        if parts.count == 3,
           parts[0].count == 4,
           parts[1].count == 2,
           parts[2].count == 2,
           let year = Int(parts[0]),
           let month = Int(parts[1]),
           let day = Int(parts[2]) {
            var components = DateComponents()
            components.calendar = Calendar(identifier: .gregorian)
            components.year = year
            components.month = month
            components.day = day
            return components.calendar?.date(from: components) != nil
        }
        return ISO8601DateFormatter().date(from: trimmed) != nil
    }

    private func uniqueArtworkURLs(
        from summaries: [PokemonCatalogCardSummary]
    ) -> [String]? {
        var seen = Set<String>()
        let values = summaries.compactMap(\.imageURL).filter { seen.insert($0).inserted }
        let limited = Array(values.prefix(3))
        return limited.isEmpty ? nil : limited
    }

    private func buildChecklist(
        row: PokemonCatalogProviderDirectoryRow,
        providerSet: PokemonCatalogProviderSet,
        providerCards: [String: PokemonCatalogProviderCard],
        descriptor: PokemonCatalogSetDescriptor
    ) throws -> (fingerprint: String, summaries: [PokemonCatalogCardSummary]) {
        guard providerSet.cards.count <= configuration.maxCardsPerSet else {
            throw PokemonCatalogBuildError.tooManyCards(
                setID: row.id,
                count: providerSet.cards.count
            )
        }
        let providerCount = providerSet.cardCount?.official ?? row.cardCount?.official
        if descriptor.recognitionKind == .expansion,
           let expected = descriptor.officialCount,
           expected != providerCount {
            throw PokemonCatalogBuildError.officialCountMismatch(
                setID: row.id,
                expected: expected,
                received: providerCount
            )
        }

        var briefIDs = Set<String>()
        var summaries: [PokemonCatalogCardSummary] = []
        var fingerprintParts: [String] = [
            providerSet.id,
            providerSet.name,
            providerSet.logo ?? "",
            providerSet.symbol ?? "",
            providerSet.releaseDate ?? "",
            String(providerCount ?? -1)
        ]

        for brief in providerSet.cards {
            let cardKey = brief.id.lowercased()
            guard briefIDs.insert(cardKey).inserted else {
                throw PokemonCatalogBuildError.duplicateProviderCard(
                    setID: row.id,
                    cardID: brief.id
                )
            }
            guard let card = providerCards[cardKey] else {
                throw PokemonCatalogBuildError.missingCardDetail(
                    setID: row.id,
                    cardID: brief.id
                )
            }
            guard card.id.caseInsensitiveCompare(brief.id) == .orderedSame else {
                throw PokemonCatalogBuildError.cardIDMismatch(
                    setID: row.id,
                    expected: brief.id,
                    received: card.id
                )
            }
            if let setID = card.setID,
               setID.caseInsensitiveCompare(row.id) != .orderedSame {
                throw PokemonCatalogBuildError.cardSetMismatch(
                    setID: row.id,
                    cardID: card.id,
                    received: setID
                )
            }
            guard !card.localID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !card.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PokemonCatalogBuildError.invalidCard(
                    setID: row.id,
                    cardID: card.id,
                    reason: "stable local ID and name are required"
                )
            }
            if let image = card.image { try validateURL(image) }
            fingerprintParts += [card.id, card.localID, card.name, card.image ?? ""]
            summaries.append(
                PokemonCatalogCardSummary(
                    providerCardID: card.id,
                    localID: card.localID,
                    name: card.name,
                    imageURL: card.image
                )
            )
        }
        summaries.sort {
            ($0.localID, $0.providerCardID) < ($1.localID, $1.providerCardID)
        }
        fingerprintParts = [
            providerSet.id,
            providerSet.name,
            providerSet.logo ?? "",
            providerSet.symbol ?? "",
            providerSet.releaseDate ?? "",
            String(providerCount ?? -1)
        ] + summaries.flatMap {
            [$0.providerCardID, $0.localID, $0.name, $0.imageURL ?? ""]
        }
        return (
            PokemonCatalogFingerprint.string(fingerprintParts.joined(separator: "\u{1F}")),
            summaries
        )
    }

    private func validateArtwork(_ descriptor: PokemonCatalogSetDescriptor) throws {
        for value in [descriptor.logoURL, descriptor.symbolURL].compactMap({ $0 }) {
            try validateURL(value)
        }
    }

    private func validateURL(_ raw: String) throws {
        guard let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              configuration.approvedArtworkHosts.contains(host) else {
            throw PokemonCatalogBuildError.unsupportedArtworkURL(raw)
        }
    }

    private func descriptorSort(
        _ lhs: PokemonCatalogSetDescriptor,
        _ rhs: PokemonCatalogSetDescriptor
    ) -> Bool {
        switch (lhs.releaseOrder, rhs.releaseOrder) {
        case let (left?, right?) where left != right: return left < right
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs.providerSetID < rhs.providerSetID
        }
    }
}
