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
    public let contentChangedProviderSetIDs: [String]
    public let authorityChangedProviderSetIDs: [String]
    public let baselineFingerprintProviderSetIDs: [String]
    public let changeClass: PokemonCatalogChangeClass
    public let excludedProviderSetIDs: [String]
    public let sets: [PokemonCatalogSetReview]

    public init(
        schemaVersion: Int = PokemonCatalogCoreContract.releaseSchemaVersion,
        revision: Int,
        generatedAt: Date,
        addedProviderSetIDs: [String],
        changedProviderSetIDs: [String],
        contentChangedProviderSetIDs: [String] = [],
        authorityChangedProviderSetIDs: [String] = [],
        baselineFingerprintProviderSetIDs: [String] = [],
        changeClass: PokemonCatalogChangeClass = .none,
        excludedProviderSetIDs: [String],
        sets: [PokemonCatalogSetReview]
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.generatedAt = generatedAt
        self.addedProviderSetIDs = addedProviderSetIDs
        self.changedProviderSetIDs = changedProviderSetIDs
        self.contentChangedProviderSetIDs = contentChangedProviderSetIDs
        self.authorityChangedProviderSetIDs = authorityChangedProviderSetIDs
        self.baselineFingerprintProviderSetIDs = baselineFingerprintProviderSetIDs
        self.changeClass = changeClass
        self.excludedProviderSetIDs = excludedProviderSetIDs
        self.sets = sets
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, revision, generatedAt
        case addedProviderSetIDs, changedProviderSetIDs
        case contentChangedProviderSetIDs, authorityChangedProviderSetIDs
        case baselineFingerprintProviderSetIDs, changeClass
        case excludedProviderSetIDs, sets
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        revision = try values.decode(Int.self, forKey: .revision)
        generatedAt = try values.decode(Date.self, forKey: .generatedAt)
        addedProviderSetIDs = try values.decode([String].self, forKey: .addedProviderSetIDs)
        changedProviderSetIDs = try values.decode([String].self, forKey: .changedProviderSetIDs)
        contentChangedProviderSetIDs = try values.decodeIfPresent(
            [String].self,
            forKey: .contentChangedProviderSetIDs
        ) ?? []
        authorityChangedProviderSetIDs = try values.decodeIfPresent(
            [String].self,
            forKey: .authorityChangedProviderSetIDs
        ) ?? []
        baselineFingerprintProviderSetIDs = try values.decodeIfPresent(
            [String].self,
            forKey: .baselineFingerprintProviderSetIDs
        ) ?? []
        changeClass = try values.decodeIfPresent(
            PokemonCatalogChangeClass.self,
            forKey: .changeClass
        ) ?? .unknown
        excludedProviderSetIDs = try values.decode([String].self, forKey: .excludedProviderSetIDs)
        sets = try values.decode([PokemonCatalogSetReview].self, forKey: .sets)
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
    case invalidParentProviderSetID(child: String, parent: String)
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
    case membershipCoverageMismatch(setID: String, expected: Int, received: Int)
    case membershipProviderCardMissing(setID: String, cardID: String)
    case membershipProviderCardNameMismatch(setID: String, cardID: String, expected: String, received: String)
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
        case let .invalidParentProviderSetID(child, parent):
            return "Invalid parent artwork relationship for \(child): \(parent)"
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
        case let .membershipCoverageMismatch(setID, expected, received):
            return "Membership coverage mismatch for \(setID): expected \(expected) rows, received \(received)"
        case let .membershipProviderCardMissing(setID, cardID):
            return "Membership row \(cardID) is not present in provider checklist \(setID)"
        case let .membershipProviderCardNameMismatch(setID, cardID, expected, received):
            return "Membership name mismatch for \(cardID) in \(setID): expected \(expected), received \(received)"
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
            let descriptorWithoutFingerprint = try makeDescriptor(
                row: row,
                providerSet: providerSet,
                existing: existing,
                humanInput: inputByID[providerID],
                assignedReleaseOrder: automaticReleaseOrders[providerID],
                providerSets: providerSets,
                activeByID: activeByID
            )
            try validateArtwork(descriptorWithoutFingerprint)

            let (fingerprint, summaries) = try buildChecklist(
                row: row,
                providerSet: providerSet,
                providerCards: providerCards,
                descriptor: descriptorWithoutFingerprint
            )
            let descriptor = descriptorWithoutFingerprint.withProviderFingerprint(fingerprint)
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
        }

        let knownIDs = Set(directory.map { $0.id.lowercased() })
        for input in request.humanInputs where !knownIDs.contains(input.providerSetID.lowercased()) {
            throw PokemonCatalogBuildError.humanInputForMissingSet(input.providerSetID)
        }

        let release = PokemonCatalogRelease(
            catalogKind: PokemonCatalogRelease.currentCatalogKind,
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
        let classification = PokemonCatalogChangeClassifier.classify(
            previousRelease: request.activeRelease,
            currentRelease: release
        )
        let report = PokemonCatalogReviewReport(
            revision: request.revision,
            generatedAt: request.generatedAt,
            addedProviderSetIDs: classification.addedProviderSetIDs,
            changedProviderSetIDs: classification.changedProviderSetIDs,
            contentChangedProviderSetIDs: classification.contentChangedProviderSetIDs,
            authorityChangedProviderSetIDs: classification.authorityChangedProviderSetIDs,
            baselineFingerprintProviderSetIDs: classification.baselineFingerprintProviderSetIDs,
            changeClass: classification.changeClass,
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
        assignedReleaseOrder: Int?,
        providerSets: [String: PokemonCatalogProviderSet],
        activeByID: [String: PokemonCatalogSetDescriptor]
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
        let providerLogo = nonEmpty(providerSet.resolvedLogo)
            ?? nonEmpty(providerSet.logo)
            ?? nonEmpty(row.logo)
        let providerSymbol = nonEmpty(providerSet.resolvedSymbol)
            ?? nonEmpty(providerSet.symbol)
            ?? nonEmpty(row.symbol)
        let configuredParentID = normalizedParentProviderSetID(
            humanInput?.parentProviderSetID
        )
        let parentProviderSetID = configuredParentID
            ?? existing.flatMap { normalizedParentProviderSetID($0.parentProviderSetID) }
        if let parentProviderSetID,
           parentProviderSetID == row.id.lowercased() {
            throw PokemonCatalogBuildError.invalidParentProviderSetID(
                child: row.id,
                parent: parentProviderSetID
            )
        }
        let parentArtwork = parentArtwork(
            parentProviderSetID: parentProviderSetID,
            providerSets: providerSets,
            activeByID: activeByID
        )
        let bundledArtworkSourceID = nonEmpty(
            humanInput?.bundledArtworkSourceID ?? existing?.bundledArtworkSourceID
        )

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
                logoURL: humanInput?.logoURL
                    ?? providerLogo
                    ?? parentArtwork.logo
                    ?? existing.logoURL,
                symbolURL: humanInput?.symbolURL
                    ?? providerSymbol
                    ?? parentArtwork.symbol
                    ?? existing.symbolURL,
                providerFingerprint: existing.providerFingerprint,
                parentProviderSetID: parentProviderSetID,
                bundledArtworkSourceID: bundledArtworkSourceID,
                rulesVersion: existing.rulesVersion,
                membershipRecognition: existing.membershipRecognition
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
                    logoURL: humanInput.logoURL ?? providerLogo ?? parentArtwork.logo,
                    symbolURL: humanInput.symbolURL ?? providerSymbol ?? parentArtwork.symbol,
                    parentProviderSetID: parentProviderSetID,
                    bundledArtworkSourceID: bundledArtworkSourceID,
                    rulesVersion: humanInput.rulesVersion,
                    membershipRecognition: humanInput.membershipRecognition
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
                    logoURL: humanInput.logoURL ?? providerLogo ?? parentArtwork.logo,
                    symbolURL: humanInput.symbolURL ?? providerSymbol ?? parentArtwork.symbol,
                    parentProviderSetID: parentProviderSetID,
                    bundledArtworkSourceID: bundledArtworkSourceID,
                    rulesVersion: humanInput.rulesVersion,
                    membershipRecognition: humanInput.membershipRecognition
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
            logoURL: providerLogo ?? parentArtwork.logo,
            symbolURL: providerSymbol ?? parentArtwork.symbol,
            parentProviderSetID: parentProviderSetID,
            bundledArtworkSourceID: bundledArtworkSourceID,
            rulesVersion: PokemonCatalogCoreContract.rulesVersion
        )
    }

    private func normalizedParentProviderSetID(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func parentArtwork(
        parentProviderSetID: String?,
        providerSets: [String: PokemonCatalogProviderSet],
        activeByID: [String: PokemonCatalogSetDescriptor]
    ) -> (logo: String?, symbol: String?) {
        guard let parentProviderSetID else { return (nil, nil) }
        if let provider = providerSets[parentProviderSetID] {
            return (
                nonEmpty(provider.resolvedLogo) ?? nonEmpty(provider.logo),
                nonEmpty(provider.resolvedSymbol) ?? nonEmpty(provider.symbol)
            )
        }
        if let descriptor = activeByID[parentProviderSetID] {
            return (nonEmpty(descriptor.logoURL), nonEmpty(descriptor.symbolURL))
        }
        return (nil, nil)
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
        try validateMembershipRecognition(
            descriptor.membershipRecognition,
            providerSet: providerSet,
            providerCards: providerCards,
            setID: row.id
        )

        var briefIDs = Set<String>()
        var summaries: [PokemonCatalogCardSummary] = []
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
            guard !brief.localID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !brief.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PokemonCatalogBuildError.invalidCard(
                    setID: row.id,
                    cardID: card.id,
                    reason: "stable local ID and name are required"
                )
            }
            if let image = brief.image { try validateURL(image) }
            summaries.append(
                PokemonCatalogCardSummary(
                    providerCardID: brief.id,
                    localID: brief.localID,
                    name: brief.name,
                    imageURL: brief.image
                )
            )
        }
        summaries.sort {
            ($0.localID, $0.providerCardID) < ($1.localID, $1.providerCardID)
        }
        guard let providerFingerprint = PokemonCatalogProviderFingerprint.v1(
            providerSet: providerSet,
            cardDetails: providerCards
        ) else {
            throw PokemonCatalogBuildError.invalidProviderFingerprint(row.id)
        }
        return (
            providerFingerprint,
            summaries
        )
    }

    private func validateMembershipRecognition(
        _ recognition: PokemonCatalogMembershipRecognition?,
        providerSet: PokemonCatalogProviderSet,
        providerCards: [String: PokemonCatalogProviderCard],
        setID: String
    ) throws {
        guard let recognition else { return }

        let expectedIDs = Set(providerSet.cards.map { $0.id.lowercased() })
        guard recognition.members.count == expectedIDs.count else {
            throw PokemonCatalogBuildError.membershipCoverageMismatch(
                setID: setID,
                expected: expectedIDs.count,
                received: recognition.members.count
            )
        }

        var seenIDs = Set<String>()
        for member in recognition.members {
            let providerID = member.providerCardID.lowercased()
            guard expectedIDs.contains(providerID),
                  let providerCard = providerCards[providerID] else {
                throw PokemonCatalogBuildError.membershipProviderCardMissing(
                    setID: setID,
                    cardID: member.providerCardID
                )
            }
            guard seenIDs.insert(providerID).inserted else {
                throw PokemonCatalogBuildError.invalidDescriptor(
                    "membership rows must have unique provider card IDs"
                )
            }
            guard canonicalMembershipName(member.canonicalName)
                    == canonicalMembershipName(providerCard.name) else {
                throw PokemonCatalogBuildError.membershipProviderCardNameMismatch(
                    setID: setID,
                    cardID: member.providerCardID,
                    expected: providerCard.name,
                    received: member.canonicalName
                )
            }
        }

        guard seenIDs == expectedIDs else {
            throw PokemonCatalogBuildError.membershipCoverageMismatch(
                setID: setID,
                expected: expectedIDs.count,
                received: seenIDs.count
            )
        }
    }

    private func canonicalMembershipName(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).replacingOccurrences(of: "&", with: " and ")
        return folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : " "
        }
        .joined()
        .split(whereSeparator: { $0 == " " })
        .joined(separator: " ")
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
