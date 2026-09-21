import Foundation

public struct MagicCatalogBuildRequest: Sendable {
    public let fixture: MagicCatalogProviderFixture
    public let activeRelease: MagicCatalogRelease?
    public let revision: Int
    public let generatedAt: String
    public let authorizedRemovalCodes: Set<String>

    public init(
        fixture: MagicCatalogProviderFixture,
        activeRelease: MagicCatalogRelease? = nil,
        revision: Int,
        generatedAt: String,
        authorizedRemovalCodes: Set<String> = []
    ) {
        self.fixture = fixture
        self.activeRelease = activeRelease
        self.revision = revision
        self.generatedAt = generatedAt
        self.authorizedRemovalCodes = Set(
            authorizedRemovalCodes.map(MagicCatalogPolicy.normalizedCode)
        )
    }
}

public struct MagicCatalogBuildResult: Codable, Equatable, Sendable {
    public let release: MagicCatalogRelease
    public let report: MagicCatalogReviewReport

    public init(release: MagicCatalogRelease, report: MagicCatalogReviewReport) {
        self.release = release
        self.report = report
    }
}

public struct MagicCatalogReviewReport: Codable, Equatable, Sendable {
    public let revision: Int
    public let generatedAt: String
    public let descriptorCount: Int
    public let changeClass: MagicCatalogChangeClass
    public let addedCodes: [String]
    public let changedCodes: [String]
    public let contentChangedCodes: [String]
    public let authorityChangedCodes: [String]
    public let removedCodes: [String]
    public let scannerProjectionChangedCodes: [String]
    public let browseProjectionChangedCodes: [String]
    public let routingProjectionChangedCodes: [String]
    public let warnings: [String]

    public init(
        revision: Int,
        generatedAt: String,
        descriptorCount: Int,
        changeClass: MagicCatalogChangeClass,
        addedCodes: [String],
        changedCodes: [String],
        contentChangedCodes: [String],
        authorityChangedCodes: [String],
        removedCodes: [String],
        scannerProjectionChangedCodes: [String],
        browseProjectionChangedCodes: [String],
        routingProjectionChangedCodes: [String],
        warnings: [String]
    ) {
        self.revision = revision
        self.generatedAt = generatedAt
        self.descriptorCount = descriptorCount
        self.changeClass = changeClass
        self.addedCodes = addedCodes
        self.changedCodes = changedCodes
        self.contentChangedCodes = contentChangedCodes
        self.authorityChangedCodes = authorityChangedCodes
        self.removedCodes = removedCodes
        self.scannerProjectionChangedCodes = scannerProjectionChangedCodes
        self.browseProjectionChangedCodes = browseProjectionChangedCodes
        self.routingProjectionChangedCodes = routingProjectionChangedCodes
        self.warnings = warnings
    }

    public var hasMeaningfulChanges: Bool {
        changeClass != .none
    }
}

public enum MagicCatalogBuilderError: Error, CustomStringConvertible, Equatable, Sendable {
    case invalidRevision
    case invalidGeneratedAt
    case duplicateProviderCode(String)
    case duplicateProviderUUID(String)
    case providerUUIDMapsToMultipleCodes(uuid: String, first: String, second: String)
    case providerCodeMapsToMultipleUUIDs(code: String, first: String, second: String)
    case printedSizeDrift(code: String, active: Int?, candidate: Int?)
    case routingAuthorityDrift(code: String)
    case unauthorizedRemoval(String)
    case authorizedRemovalNotActive(String)

    public var description: String {
        switch self {
        case .invalidRevision: return "Magic catalog revision must be positive"
        case .invalidGeneratedAt: return "Magic catalog generatedAt must be ISO-8601"
        case .duplicateProviderCode(let code): return "Provider response repeats set code \(code)"
        case .duplicateProviderUUID(let uuid): return "Provider response repeats Scryfall UUID \(uuid)"
        case let .providerUUIDMapsToMultipleCodes(uuid, first, second):
            return "Scryfall UUID \(uuid) changed code from \(first) to \(second)"
        case let .providerCodeMapsToMultipleUUIDs(code, first, second):
            return "Scryfall code \(code) changed UUID from \(first) to \(second)"
        case let .printedSizeDrift(code, active, candidate):
            let activeDescription = active.map(String.init) ?? "nil"
            let candidateDescription = candidate.map(String.init) ?? "nil"
            return "Released Magic set \(code) printedSize drifted from \(activeDescription) to \(candidateDescription)"
        case .routingAuthorityDrift(let code):
            return "Routing authority changed for released Magic child set \(code)"
        case .unauthorizedRemoval(let code):
            return "Active Magic set \(code) was removed without explicit authorization"
        case .authorizedRemovalNotActive(let code):
            return "Magic removal authorization names non-active set \(code)"
        }
    }
}

public struct MagicCatalogBuilder: Sendable {
    public init() {}

    public func build(_ request: MagicCatalogBuildRequest) throws -> MagicCatalogBuildResult {
        guard request.revision > 0 else { throw MagicCatalogBuilderError.invalidRevision }
        guard let generatedAt = MagicCatalogDate.parseTimestamp(request.generatedAt) else {
            throw MagicCatalogBuilderError.invalidGeneratedAt
        }

        try validateProviderDirectory(request.fixture.sets)
        var providerWarnings: [String] = []
        let referencedParentCodes: Set<String> = Set(
            request.fixture.sets.compactMap { set in
                guard MagicCatalogPolicy.routingKind(for: set) != nil,
                      let parent = set.parentSetCode,
                      !parent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return MagicCatalogPolicy.normalizedCode(parent)
            }
        )
        let descriptors = request.fixture.sets.compactMap { set -> MagicCatalogSetDescriptor? in
            if MagicCatalogPolicy.routingKind(for: set) != nil,
               set.parentSetCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                providerWarnings.append(
                    "Excluded unroutable provider child \(set.code): missing parent_set_code."
                )
                return nil
            }
            return makeDescriptor(
                set,
                includeAsRoutingParent: referencedParentCodes.contains(
                    MagicCatalogPolicy.normalizedCode(set.code)
                )
            )
        }
            .sorted(by: MagicCatalogPolicy.releaseSort)
        let release = MagicCatalogRelease(
            revision: request.revision,
            generatedAt: request.generatedAt,
            sets: descriptors
        )

        if let activeRelease = request.activeRelease {
            try validateIdentityContinuity(active: activeRelease, candidate: release)
        }
        try validateRemovalAuthorization(
            active: request.activeRelease,
            candidate: release,
            authorizedCodes: request.authorizedRemovalCodes
        )
        if let activeRelease = request.activeRelease {
            try validateAuthorityDrift(
                active: activeRelease,
                candidate: release,
                generatedAt: generatedAt
            )
        }
        try MagicCatalogReleaseValidator.validate(release)

        let surfaceDiff = MagicCatalogChangeClassifier.surfaceDiff(
            previousRelease: request.activeRelease,
            currentRelease: release
        )
        let classification = MagicCatalogChangeClassifier.classify(
            previousRelease: request.activeRelease,
            currentRelease: release,
            surfaceDiff: surfaceDiff
        )
        let report = makeReport(
            active: request.activeRelease,
            candidate: release,
            providerWarnings: providerWarnings,
            surfaceDiff: surfaceDiff,
            classification: classification
        )
        return MagicCatalogBuildResult(release: release, report: report)
    }

    private func makeDescriptor(
        _ set: MagicCatalogProviderSet,
        includeAsRoutingParent: Bool = false
    ) -> MagicCatalogSetDescriptor? {
        let browseEnabled = MagicCatalogPolicy.isBrowseEligible(set)
        let scanEnabled = MagicCatalogPolicy.isScannerEligible(set)
        let routingKind = MagicCatalogPolicy.routingKind(for: set)
        guard browseEnabled || scanEnabled || routingKind != nil || includeAsRoutingParent else {
            return nil
        }

        return MagicCatalogSetDescriptor(
            scryfallSetID: set.id.trimmingCharacters(in: .whitespacesAndNewlines),
            code: MagicCatalogPolicy.displayCode(set.code),
            displayName: set.name.trimmingCharacters(in: .whitespacesAndNewlines),
            releaseDate: set.releasedAt,
            setType: set.setType.lowercased(),
            printedSize: set.printedSize,
            cardCount: set.cardCount,
            iconSVGURL: set.iconSVGURL,
            parentSetCode: routingKind == nil
                ? nil
                : set.parentSetCode.map(MagicCatalogPolicy.displayCode),
            routingKind: routingKind,
            scanEnabled: routingKind == nil && scanEnabled,
            browseEnabled: routingKind == nil && browseEnabled
        )
    }

    private func validateProviderDirectory(
        _ rows: [MagicCatalogProviderSet]
    ) throws {
        var ids: [String: String] = [:]
        var codes: [String: String] = [:]
        for row in rows {
            let uuid = row.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let code = MagicCatalogPolicy.normalizedCode(row.code)
            if let first = ids[uuid] {
                if first != row.code {
                    throw MagicCatalogBuilderError.providerUUIDMapsToMultipleCodes(
                        uuid: uuid,
                        first: first,
                        second: row.code
                    )
                }
                throw MagicCatalogBuilderError.duplicateProviderUUID(uuid)
            }
            if let first = codes[code] {
                if first != uuid {
                    throw MagicCatalogBuilderError.providerCodeMapsToMultipleUUIDs(
                        code: row.code,
                        first: first,
                        second: uuid
                    )
                }
                throw MagicCatalogBuilderError.duplicateProviderCode(row.code)
            }
            ids[uuid] = row.code
            codes[code] = uuid
        }
    }

    private func validateIdentityContinuity(
        active: MagicCatalogRelease,
        candidate: MagicCatalogRelease
    ) throws {
        let activeByID = Dictionary(
            active.sets.map { ($0.scryfallSetID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let activeByCode = Dictionary(
            active.sets.map { (MagicCatalogPolicy.normalizedCode($0.code), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for descriptor in candidate.sets {
            if let previous = activeByID[descriptor.scryfallSetID],
               MagicCatalogPolicy.normalizedCode(previous.code)
                    != MagicCatalogPolicy.normalizedCode(descriptor.code) {
                throw MagicCatalogBuilderError.providerUUIDMapsToMultipleCodes(
                    uuid: descriptor.scryfallSetID,
                    first: previous.code,
                    second: descriptor.code
                )
            }
            if let previous = activeByCode[MagicCatalogPolicy.normalizedCode(descriptor.code)],
               previous.scryfallSetID != descriptor.scryfallSetID {
                throw MagicCatalogBuilderError.providerCodeMapsToMultipleUUIDs(
                    code: descriptor.code,
                    first: previous.scryfallSetID,
                    second: descriptor.scryfallSetID
                )
            }
        }
    }

    private func validateAuthorityDrift(
        active: MagicCatalogRelease,
        candidate: MagicCatalogRelease,
        generatedAt: Date
    ) throws {
        let activeByCode = Dictionary(
            active.sets.map { (MagicCatalogPolicy.normalizedCode($0.code), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for descriptor in candidate.sets {
            guard let previous = activeByCode[MagicCatalogPolicy.normalizedCode(descriptor.code)] else {
                continue
            }
            if previous.routingKind != nil || descriptor.routingKind != nil,
               previous.parentSetCode?.lowercased() != descriptor.parentSetCode?.lowercased()
                    || previous.routingKind != descriptor.routingKind {
                throw MagicCatalogBuilderError.routingAuthorityDrift(code: descriptor.code)
            }

            let isPreviouslyReleased = previous.releaseDate
                .flatMap(MagicCatalogDate.parseDay)
                .map { $0 <= generatedAt } ?? false
            if isPreviouslyReleased, previous.printedSize != descriptor.printedSize {
                throw MagicCatalogBuilderError.printedSizeDrift(
                    code: descriptor.code,
                    active: previous.printedSize,
                    candidate: descriptor.printedSize
                )
            }
        }
    }

    private func validateRemovalAuthorization(
        active: MagicCatalogRelease?,
        candidate: MagicCatalogRelease,
        authorizedCodes: Set<String>
    ) throws {
        let activeCodes = Set(
            active?.sets.map { MagicCatalogPolicy.normalizedCode($0.code) } ?? []
        )
        let candidateCodes = Set(
            candidate.sets.map { MagicCatalogPolicy.normalizedCode($0.code) }
        )
        let removedCodes = activeCodes.subtracting(candidateCodes).sorted()
        for code in removedCodes where !authorizedCodes.contains(code) {
            throw MagicCatalogBuilderError.unauthorizedRemoval(code)
        }
        for code in authorizedCodes.sorted() where !activeCodes.contains(code) {
            throw MagicCatalogBuilderError.authorizedRemovalNotActive(code)
        }
    }

    private func makeReport(
        active: MagicCatalogRelease?,
        candidate: MagicCatalogRelease,
        providerWarnings: [String],
        surfaceDiff: MagicCatalogSurfaceDiff,
        classification: MagicCatalogChangeClassification
    ) -> MagicCatalogReviewReport {
        let oldByCode = Dictionary(
            active?.sets.map { (MagicCatalogPolicy.normalizedCode($0.code), $0) } ?? [],
            uniquingKeysWith: { first, _ in first }
        )
        let newByCode = Dictionary(
            candidate.sets.map { (MagicCatalogPolicy.normalizedCode($0.code), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var warnings = providerWarnings
        for code in Set(oldByCode.keys).union(newByCode.keys).sorted() {
            guard let previous = oldByCode[code],
                  let next = newByCode[code],
                  previous.printedSize != next.printedSize,
                  let releaseDate = previous.releaseDate.flatMap(MagicCatalogDate.parseDay),
                  let generatedAt = MagicCatalogDate.parseTimestamp(candidate.generatedAt),
                  releaseDate > generatedAt else {
                continue
            }
            let oldSize = previous.printedSize.map(String.init) ?? "nil"
            let newSize = next.printedSize.map(String.init) ?? "nil"
            warnings.append(
                "Future Magic set \(next.code) printedSize changed from \(oldSize) to \(newSize) before release; review prominently."
            )
        }
        warnings.append(contentsOf: candidate.sets.compactMap { descriptor -> String? in
            guard descriptor.scanEnabled, descriptor.printedSize == nil else { return nil }
            return "Scanner set \(descriptor.code) has no printedSize; denominator evidence remains optional."
        })
        return MagicCatalogReviewReport(
            revision: candidate.revision,
            generatedAt: candidate.generatedAt,
            descriptorCount: candidate.sets.count,
            changeClass: classification.changeClass,
            addedCodes: surfaceDiff.addedCodes,
            changedCodes: surfaceDiff.changedCodes,
            contentChangedCodes: classification.contentChangedCodes,
            authorityChangedCodes: classification.authorityChangedCodes,
            removedCodes: surfaceDiff.removedCodes,
            scannerProjectionChangedCodes: surfaceDiff.scannerProjectionChangedCodes,
            browseProjectionChangedCodes: surfaceDiff.browseProjectionChangedCodes,
            routingProjectionChangedCodes: surfaceDiff.routingProjectionChangedCodes,
            warnings: warnings
        )
    }
}
