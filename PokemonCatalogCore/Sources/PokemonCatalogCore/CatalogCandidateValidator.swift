import Foundation

public enum PokemonCatalogCandidateValidationError: Error, CustomStringConvertible, Sendable {
    case revisionNotMonotonic(received: Int, current: Int)
    case releaseValidationFailed(String)
    case unsupportedReleaseSchema(Int)
    case mismatchedRevision(component: String, expected: Int, received: Int)
    case mismatchedGeneratedAt(component: String)
    case unsupportedSnapshotSchema(Int)
    case unsupportedSnapshotRulesVersion(Int)
    case snapshotEntriesDoNotMatchRelease
    case snapshotChecklistsDoNotMatchEntries
    case snapshotFingerprintMismatch
    case reportSetsDoNotMatchSnapshot
    case reportSetMismatch(String)
    case duplicateReportSet(String)
    case reportReferencesUnknownSet(String)

    public var description: String {
        switch self {
        case let .revisionNotMonotonic(received, current):
            return "Candidate revision \(received) is not greater than active revision \(current)"
        case let .releaseValidationFailed(message):
            return "Candidate release validation failed: \(message)"
        case .unsupportedReleaseSchema(let version):
            return "Unsupported candidate release schema: \(version)"
        case let .mismatchedRevision(component, expected, received):
            return "Candidate \(component) revision \(received) does not match release revision \(expected)"
        case .mismatchedGeneratedAt(let component):
            return "Candidate \(component) timestamp does not match the release timestamp"
        case .unsupportedSnapshotSchema(let version):
            return "Unsupported candidate snapshot schema: \(version)"
        case .unsupportedSnapshotRulesVersion(let version):
            return "Unsupported candidate snapshot rules version: \(version)"
        case .snapshotEntriesDoNotMatchRelease:
            return "Candidate snapshot entries do not match release descriptors"
        case .snapshotChecklistsDoNotMatchEntries:
            return "Candidate snapshot checklists do not match snapshot entries"
        case .snapshotFingerprintMismatch:
            return "Candidate snapshot directory fingerprint is incorrect"
        case .reportSetsDoNotMatchSnapshot:
            return "Candidate review report sets do not match snapshot entries"
        case let .reportSetMismatch(id):
            return "Candidate review report does not match set \(id)"
        case let .duplicateReportSet(id):
            return "Candidate review report contains duplicate set \(id)"
        case let .reportReferencesUnknownSet(id):
            return "Candidate review report references unknown set \(id)"
        }
    }
}

/// Re-validates the three unsigned files that cross the prepare/publish job
/// boundary. The protected job must not sign a candidate merely because its
/// JSON decodes: all public artifacts must still describe the same release.
public enum PokemonCatalogCandidateValidator {
    public static func validate(
        _ build: PokemonCatalogBuildResult,
        activeRevision: Int? = nil
    ) throws {
        if let activeRevision, build.release.revision <= activeRevision {
            throw PokemonCatalogCandidateValidationError.revisionNotMonotonic(
                received: build.release.revision,
                current: activeRevision
            )
        }

        do {
            try PokemonCatalogReleaseValidator.validate(build.release)
        } catch {
            throw PokemonCatalogCandidateValidationError.releaseValidationFailed(
                String(describing: error)
            )
        }

        let releaseRevision = build.release.revision
        guard build.release.schemaVersion == PokemonCatalogRelease.currentSchemaVersion else {
            throw PokemonCatalogCandidateValidationError.unsupportedReleaseSchema(
                build.release.schemaVersion
            )
        }
        guard build.snapshot.schemaVersion == PokemonCatalogSnapshot.currentSchemaVersion else {
            throw PokemonCatalogCandidateValidationError.unsupportedSnapshotSchema(
                build.snapshot.schemaVersion
            )
        }
        guard build.snapshot.rulesVersion == PokemonCatalogCoreContract.rulesVersion else {
            throw PokemonCatalogCandidateValidationError.unsupportedSnapshotRulesVersion(
                build.snapshot.rulesVersion
            )
        }
        guard build.report.schemaVersion == PokemonCatalogCoreContract.releaseSchemaVersion else {
            throw PokemonCatalogCandidateValidationError.mismatchedRevision(
                component: "report schema",
                expected: PokemonCatalogCoreContract.releaseSchemaVersion,
                received: build.report.schemaVersion
            )
        }
        guard build.snapshot.generatedAt == build.release.generatedAt else {
            throw PokemonCatalogCandidateValidationError.mismatchedGeneratedAt(component: "snapshot")
        }
        guard build.report.generatedAt == build.release.generatedAt else {
            throw PokemonCatalogCandidateValidationError.mismatchedGeneratedAt(component: "report")
        }
        guard build.snapshot.entries.allSatisfy({ $0.providerSetID == $0.providerSetID.lowercased() }) else {
            throw PokemonCatalogCandidateValidationError.snapshotEntriesDoNotMatchRelease
        }
        guard build.snapshot.checklists.keys.allSatisfy({ $0 == $0.lowercased() }) else {
            throw PokemonCatalogCandidateValidationError.snapshotChecklistsDoNotMatchEntries
        }

        let releaseByID = Dictionary(
            uniqueKeysWithValues: build.release.sets.map {
                ($0.providerSetID.lowercased(), $0)
            }
        )
        let snapshotByID = Dictionary(
            uniqueKeysWithValues: build.snapshot.entries.map {
                ($0.providerSetID.lowercased(), $0)
            }
        )
        let snapshotIDs = Set(snapshotByID.keys)
        guard snapshotIDs.count == build.snapshot.entries.count,
              snapshotIDs.isSubset(of: Set(releaseByID.keys)) else {
            throw PokemonCatalogCandidateValidationError.snapshotEntriesDoNotMatchRelease
        }
        guard Set(build.snapshot.checklists.keys) == snapshotIDs,
              build.snapshot.entries.allSatisfy({
                  build.snapshot.checklists[$0.providerSetID]?.count == $0.cardCount
              }) else {
            throw PokemonCatalogCandidateValidationError.snapshotChecklistsDoNotMatchEntries
        }

        for entry in build.snapshot.entries {
            let id = entry.providerSetID
            guard let descriptor = releaseByID[id] else {
                throw PokemonCatalogCandidateValidationError.snapshotEntriesDoNotMatchRelease
            }
            guard entry.printedCode == (descriptor.printedCode ?? descriptor.printedPrefix),
                  entry.officialCount == descriptor.officialCount,
                  entry.releaseOrder == descriptor.releaseOrder,
                  entry.resource == "sets/\(id)-\(entry.providerFingerprint).json" else {
                throw PokemonCatalogCandidateValidationError.snapshotEntriesDoNotMatchRelease
            }
        }

        let expectedFingerprint = PokemonCatalogFingerprint.string(
            build.snapshot.entries
                .sorted { $0.providerSetID < $1.providerSetID }
                .map { "\($0.providerSetID)=\($0.providerFingerprint)" }
                .joined(separator: "\u{1F}")
        )
        guard expectedFingerprint == build.snapshot.directoryFingerprint else {
            throw PokemonCatalogCandidateValidationError.snapshotFingerprintMismatch
        }

        let reportIDs = build.report.sets.map { $0.providerSetID }
        guard Set(reportIDs) == snapshotIDs else {
            throw PokemonCatalogCandidateValidationError.reportSetsDoNotMatchSnapshot
        }
        guard reportIDs.count == Set(reportIDs).count else {
            throw PokemonCatalogCandidateValidationError.duplicateReportSet(
                reportIDs.first ?? "unknown"
            )
        }
        guard build.report.addedProviderSetIDs.allSatisfy({
            reportIDs.contains($0)
        }), build.report.changedProviderSetIDs.allSatisfy({
            reportIDs.contains($0)
        }) else {
            throw PokemonCatalogCandidateValidationError.reportReferencesUnknownSet(
                build.report.addedProviderSetIDs.first(where: { !reportIDs.contains($0) })
                    ?? build.report.changedProviderSetIDs.first(where: { !reportIDs.contains($0) })
                    ?? "unknown"
            )
        }

        for review in build.report.sets {
            let id = review.providerSetID
            guard let descriptor = releaseByID[id],
                  let entry = snapshotByID[id] else {
                throw PokemonCatalogCandidateValidationError.reportReferencesUnknownSet(id)
            }
            guard review.displayName == entry.displayName,
                  review.recognitionKind == descriptor.recognitionKind,
                  review.printedCode == entry.printedCode,
                  review.officialCount == entry.officialCount,
                  review.providerCardCount == entry.cardCount,
                  review.providerFingerprint == entry.providerFingerprint,
                  review.status == "added" || review.status == "verified" else {
                throw PokemonCatalogCandidateValidationError.reportSetMismatch(id)
            }
        }

        guard build.report.revision == releaseRevision else {
            throw PokemonCatalogCandidateValidationError.mismatchedRevision(
                component: "report",
                expected: releaseRevision,
                received: build.report.revision
            )
        }
    }
}
