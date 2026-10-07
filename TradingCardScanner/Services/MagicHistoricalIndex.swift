import CryptoKit
import Foundation
import MagicCatalogCore

/// A physical printing owns its finishes; finishes never create extra picker rows.
struct MagicHistoricalPrintingRecord: Codable, Equatable, Sendable {
    let printingID: String
    let oracleID: String?
    let sourceIDs: [String]
    let setCode: String
    let setName: String
    let setID: String?
    let collectorNumber: String
    let name: String
    let aliases: [String]
    let releaseDate: String?
    let language: String
    let layout: String
    let finishes: [String]
    /// MTGJSON finish-specific SKU references, not hydrated marketplace SKU payloads.
    let sourceFinishReferences: [String: [String]]
    let paper: Bool
    let reconciled: Bool
    let visibleCollectorNumber: Bool?
    let route: MagicRecognitionRoute
    let unresolvedDistinctions: [String]
    let frame: String?
    let artworkID: String?
    let thumbnailURL: URL?
    let disposition: String
}

struct MagicHistoricalEvidenceKey: Codable, Hashable, Sendable {
    let title: String
    let collectorNumber: String

    init(title: String, collectorNumber: String) {
        self.title = Self.canonicalTitle(title)
        // Preserve leading zeroes, suffixes and punctuation. No integer projection.
        self.collectorNumber = collectorNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func canonicalTitle(_ raw: String) -> String {
        raw.precomposedStringWithCanonicalMapping.lowercased()
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    var isValid: Bool { !title.isEmpty && !collectorNumber.isEmpty }
}

struct MagicHistoricalIndexArtifact: Codable, Sendable {
    struct Source: Codable, Sendable {
        let kind: String
        let url: URL
        let sha256: String
        let dataDate: String
    }
    struct Coverage: Codable, Sendable {
        struct KeyReceipt: Codable, Sendable {
            let key: MagicHistoricalEvidenceKey
            let sourceSHA256: String
            let printingIDs: [String]
            let pageCount: Int
            let resultCount: Int
            let reconciliationVersion: Int
        }
        let completeKeys: [MagicHistoricalEvidenceKey]
        /// Exact all-era response membership, emitted only by a future complete
        /// provider-key reconciler. A set capture cannot supply this receipt.
        let keyReceipts: [KeyReceipt]
        let unresolvedKeys: [MagicHistoricalEvidenceKey]
        let validUntil: String?
        /// A card-level source reconciliation context, independent of the set directory.
        let sourceContext: String?
        let missingSources: [String]
    }
    let schemaVersion: Int
    let processingVersion: Int
    let profileVersion: Int
    let observedOn: String
    let catalog: MagicCatalogRelease
    let sources: [Source]
    let records: [MagicHistoricalPrintingRecord]
    let coverage: Coverage
}

/// Immutable, dictionary-backed pilot index. It provides candidate evidence only;
/// encounter language, optical strength, finish and save gates remain adapter work.
struct MagicHistoricalIndexSnapshot: Sendable {
    enum ValidationError: Error {
        case unsupportedVersion, invalidSource, invalidRecord, invalidCoverage, incompatibleProfiles
    }
    struct Query: Sendable {
        /// Includes outside-era and unsupported records. Never infer uniqueness from candidates alone.
        let matchingRecords: [MagicHistoricalPrintingRecord]
        let eligiblePhaseOneRecords: [MagicHistoricalPrintingRecord]
        let universeIsCurrent: Bool
        let indexGeneration: String
        let profileGeneration: String
    }

    let generation: String
    let catalogContext: String
    let catalogRevision: Int
    let artifact: MagicHistoricalIndexArtifact
    private let byEvidence: [MagicHistoricalEvidenceKey: [MagicHistoricalPrintingRecord]]
    private let completeKeys: Set<MagicHistoricalEvidenceKey>
    private let unresolvedKeys: Set<MagicHistoricalEvidenceKey>
    private let expiresAt: Date?

    init(data: Data) throws {
        let artifact = try MagicCatalogJSON.decode(MagicHistoricalIndexArtifact.self, from: data)
        guard artifact.schemaVersion == 1, artifact.processingVersion == 1,
              artifact.profileVersion == MagicRecognitionProfileSnapshot.currentVersion,
              artifact.catalog.schemaVersion == 1, artifact.catalog.catalogKind == "magic" else {
            throw ValidationError.unsupportedVersion
        }
        try MagicCatalogReleaseValidator.validate(artifact.catalog)
        guard let observed = MagicCatalogDate.parseDay(artifact.observedOn), !artifact.sources.isEmpty else {
            throw ValidationError.invalidSource
        }
        let allowedHosts = ["mtgjsonAllPrintings": "mtgjson.com", "mtgjsonPilot": "mtgjson.com",
                            "scryfallPilot": "api.scryfall.com", "scryfallCrossEra": "api.scryfall.com"]
        var sourceKinds: Set<String> = []
        for source in artifact.sources {
            guard let host = allowedHosts[source.kind], source.url.scheme == "https",
                  source.url.host == host, source.url.user == nil, source.url.password == nil,
                  Self.isDigest(source.sha256), let day = MagicCatalogDate.parseDay(source.dataDate),
                  day <= observed, sourceKinds.insert(source.kind).inserted else {
                throw ValidationError.invalidSource
            }
        }
        guard Set(["mtgjsonAllPrintings", "mtgjsonPilot", "scryfallPilot"]).isSubset(of: sourceKinds) else {
            throw ValidationError.invalidSource
        }
        let context = try MagicRecognitionProfileSnapshot(descriptors: artifact.catalog.sets,
                                                          catalogRevision: artifact.catalog.revision)
        let sets = Dictionary(uniqueKeysWithValues: artifact.catalog.sets.map { ($0.code.lowercased(), $0) })
        var printingIDs: Set<UUID> = []
        var sourceIDs: Set<UUID> = []
        var finishReferences: Set<UUID> = []
        var lookup: [MagicHistoricalEvidenceKey: [MagicHistoricalPrintingRecord]] = [:]
        for record in artifact.records {
            guard let id = UUID(uuidString: record.printingID), printingIDs.insert(id).inserted,
                  !record.sourceIDs.isEmpty, !record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !record.collectorNumber.isEmpty, record.collectorNumber == record.collectorNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                  !record.setCode.isEmpty, !record.setName.isEmpty,
                  !record.finishes.isEmpty, Set(record.finishes).count == record.finishes.count,
                  record.finishes.allSatisfy({ ["nonfoil", "foil", "etched"].contains($0) }),
                  record.aliases.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  record.releaseDate == nil || MagicCatalogDate.parseDay(record.releaseDate) != nil else {
                throw ValidationError.invalidRecord
            }
            for rawID in record.sourceIDs {
                guard let sourceID = UUID(uuidString: rawID), sourceIDs.insert(sourceID).inserted else {
                    throw ValidationError.invalidRecord
                }
            }
            for (finish, references) in record.sourceFinishReferences {
                guard record.finishes.contains(finish), !references.isEmpty else { throw ValidationError.invalidRecord }
                for rawReference in references {
                    guard let reference = UUID(uuidString: rawReference), finishReferences.insert(reference).inserted else {
                        throw ValidationError.invalidRecord
                    }
                }
            }
            if record.reconciled {
                // Promo/event printing dates may differ from their enclosing
                // product date; exact provider reconciliation establishes that axis.
                guard let set = sets[record.setCode.lowercased()], record.setID == set.scryfallSetID,
                      record.releaseDate != nil else { throw ValidationError.invalidRecord }
            }
            let keys = Set(([record.name] + record.aliases).map {
                MagicHistoricalEvidenceKey(title: $0, collectorNumber: record.collectorNumber)
            })
            for key in keys { lookup[key, default: []].append(record) }
        }
        let coverage = artifact.coverage
        let complete = Set(coverage.completeKeys)
        let unresolved = Set(coverage.unresolvedKeys)
        guard complete.count == coverage.completeKeys.count, unresolved.count == coverage.unresolvedKeys.count,
              complete.isDisjoint(with: unresolved), (complete.union(unresolved)).allSatisfy(\.isValid),
              (complete.union(unresolved)).allSatisfy({
                  $0 == MagicHistoricalEvidenceKey(title: $0.title, collectorNumber: $0.collectorNumber)
              }) else { throw ValidationError.invalidCoverage }
        let expiry = coverage.validUntil.flatMap(MagicCatalogDate.parseTimestamp)
        if !complete.isEmpty {
            // A deliberately short maximum; source timestamps and key reconciliation
            // must renew this stamp. A frozen bundle cannot remain current indefinitely.
            guard let expiry, expiry > observed, expiry <= observed.addingTimeInterval(24 * 60 * 60),
                  let sourceContext = coverage.sourceContext, Self.isDigest(sourceContext),
                  coverage.missingSources.isEmpty,
                  artifact.sources.allSatisfy({ MagicCatalogDate.parseDay($0.dataDate)! >= observed.addingTimeInterval(-24 * 60 * 60) }),
                  coverage.keyReceipts.count == complete.count,
                  Set(coverage.keyReceipts.map(\.key)) == complete else { throw ValidationError.invalidCoverage }
            let crossEraHashes = Set(artifact.sources.filter { $0.kind == "scryfallCrossEra" }.map(\.sha256))
            for receipt in coverage.keyReceipts {
                let records = lookup[receipt.key] ?? []
                guard crossEraHashes.contains(receipt.sourceSHA256), receipt.reconciliationVersion == 1,
                      receipt.pageCount > 0, receipt.resultCount == receipt.printingIDs.count,
                      Set(receipt.printingIDs).count == receipt.printingIDs.count,
                      Set(receipt.printingIDs) == Set(records.map(\.printingID)) else {
                    throw ValidationError.invalidCoverage
                }
            }
        } else if coverage.validUntil != nil || coverage.sourceContext != nil || !coverage.keyReceipts.isEmpty {
            throw ValidationError.invalidCoverage
        }
        self.artifact = artifact
        self.generation = "magic-historical-index-v1-" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        self.catalogContext = context.catalogContext
        self.catalogRevision = artifact.catalog.revision
        self.byEvidence = lookup.mapValues { $0.sorted { $0.printingID < $1.printingID } }
        self.completeKeys = complete
        self.unresolvedKeys = unresolved
        self.expiresAt = expiry
    }

    func query(title: String, collectorNumber: String, profiles: MagicRecognitionProfileSnapshot,
               currentSourceContext: String?, now: Date = Date()) throws -> Query {
        guard profiles.indexGeneration == generation, profiles.catalogContext == catalogContext,
              profiles.catalogRevision == catalogRevision else { throw ValidationError.incompatibleProfiles }
        let key = MagicHistoricalEvidenceKey(title: title, collectorNumber: collectorNumber)
        let records = key.isValid ? byEvidence[key] ?? [] : []
        let eligible = records.filter { record in
            guard record.reconciled, record.paper, record.language == "en",
                  record.visibleCollectorNumber == true, record.unresolvedDistinctions.isEmpty,
                  MagicRecognitionProfileSnapshot.supportedLegacyLayouts.contains(record.layout),
                  record.route == .legacyCollectorNumber,
                  profiles.profile(setCode: record.setCode, printingID: record.printingID).route == .legacyCollectorNumber,
                  let day = record.releaseDate, let released = MagicCatalogDate.parseDay(day) else { return false }
            return day >= MagicRecognitionProfileSnapshot.collectorNumberStart
                && day < MagicCatalogPolicy.modernFooterStart && released <= now
        }
        let observed = MagicCatalogDate.parseDay(artifact.observedOn)!
        let current = key.isValid && completeKeys.contains(key) && !unresolvedKeys.contains(key)
            && artifact.coverage.missingSources.isEmpty
            && currentSourceContext != nil && currentSourceContext == artifact.coverage.sourceContext
            && now >= observed && expiresAt.map({ now < $0 }) == true
            && records.allSatisfy(\.reconciled)
        return Query(matchingRecords: records, eligiblePhaseOneRecords: eligible, universeIsCurrent: current,
                     indexGeneration: generation, profileGeneration: profiles.generation)
    }

    private static func isDigest(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func loadBundled() throws -> Self {
        let bundles = [Bundle.main, Bundle(for: MagicHistoricalIndexResourceLocator.self)]
        for bundle in bundles {
            if let url = bundle.url(forResource: "pilot-index", withExtension: "json", subdirectory: "MagicHistoricalPilot") {
                return try Self(data: Data(contentsOf: url))
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }
}

/// Profiles and their compatible read-only index publish as one value. No recognizer
/// or acquisition adapter is installed by this store.
struct MagicHistoricalLocalSnapshot: Sendable {
    let profiles: MagicRecognitionProfileSnapshot
    let index: MagicHistoricalIndexSnapshot
    var generation: String { profiles.generation }

    init(profiles: MagicRecognitionProfileSnapshot, index: MagicHistoricalIndexSnapshot) throws {
        guard profiles.indexGeneration == index.generation, profiles.catalogContext == index.catalogContext,
              profiles.catalogRevision == index.catalogRevision else {
            throw MagicHistoricalIndexSnapshot.ValidationError.incompatibleProfiles
        }
        self.profiles = profiles
        self.index = index
    }
}

actor MagicHistoricalLocalStore {
    private(set) var snapshot: MagicHistoricalLocalSnapshot
    init(snapshot: MagicHistoricalLocalSnapshot) { self.snapshot = snapshot }
    func isCurrent(_ generation: String) -> Bool { snapshot.generation == generation }
    @discardableResult
    func activate(_ next: MagicHistoricalLocalSnapshot, expectedGeneration: String) throws -> Bool {
        guard isCurrent(expectedGeneration) else { throw MagicRecognitionProfileSnapshot.ValidationError.staleActivation }
        guard next.generation != snapshot.generation else { return false }
        snapshot = next
        return true
    }
}

private final class MagicHistoricalIndexResourceLocator: NSObject {}
