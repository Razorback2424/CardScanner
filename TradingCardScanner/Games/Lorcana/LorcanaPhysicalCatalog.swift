import Foundation

enum LorcanaPhysicalReviewStatus: String, Codable, Hashable, Sendable {
    case provisional, verified, conflicted, superseded
}

enum LorcanaPhysicalSize: String, Codable, Hashable, Sendable {
    case standard, oversized
    var label: String { self == .standard ? "Standard" : "Oversized" }
}

/// Only the finishes reviewed by this contract are supported. Unknown future
/// finishes fail decoding instead of disappearing from a printing's universe.
enum LorcanaPhysicalFinish: String, Codable, Hashable, CaseIterable, Sendable {
    case normal, foil
    var variant: PhysicalVariant { self == .normal ? .normal : .foil }
}

enum LorcanaPhysicalEvidenceKind: String, Codable, Hashable, CaseIterable, Sendable {
    case printedFooter, artwork, distribution, stamp, size
}

struct LorcanaPhysicalEvidence: Codable, Hashable, Sendable {
    let kind: LorcanaPhysicalEvidenceKind
    let reference: String
}

struct LorcanaCanonicalCard: Codable, Sendable {
    let id: UUID
    let name: String
    let version: String?
    let relationshipEvidenceReferences: [String]
    var displayName: String { version.flatMap { $0.isEmpty ? nil : $0 }.map { "\(name) — \($0)" } ?? name }
}

/// Protected physical identity. Provider aliases, image URLs, names and price
/// columns cannot allocate or replace the app-owned UUID.
struct LorcanaPhysicalIdentity: Codable, Hashable, Sendable {
    let canonicalCardID: UUID
    let footer: LorcanaPrintedIdentity
    let artworkID: UUID
    let distributionID: String
    /// nil explicitly denotes an unstamped printing, reviewed by stamp evidence.
    let stamp: String?
    let size: LorcanaPhysicalSize
    let layout: String
}

struct LorcanaPhysicalFinishEvidence: Codable, Sendable {
    let finish: LorcanaPhysicalFinish
    let evidenceReferences: [String]
}

/// Reviewed product/finish join, separate from physical identity and finish evidence.
/// TCGCSV supplies aggregate US/USD observations, never a condition-specific SKU.
struct LorcanaMarketMapping: Codable, Hashable, Sendable {
    let finish: LorcanaPhysicalFinish
    let groupID: Int
    let productID: Int
    let productName: String
    /// Exact marketplace Number field, which may include the printed denominator.
    let productNumber: String
    let providerVariantID: String
    let market: String
    let currency: String
    let condition: String
    let evidenceReferences: [String]

    var hasValidMarketLane: Bool {
        market == "us" && currency == "USD" && condition == "aggregate"
            && (finish == .normal ? providerVariantID == "Normal" : ["Cold Foil", "Holofoil"].contains(providerVariantID))
    }

    var normalized: Self {
        .init(finish: finish, groupID: groupID, productID: productID, productName: productName,
              productNumber: productNumber, providerVariantID: providerVariantID, market: market,
              currency: currency, condition: condition, evidenceReferences: evidenceReferences.sorted())
    }
}

struct LorcanaPhysicalPrinting: Codable, Sendable {
    let id: UUID
    let identity: LorcanaPhysicalIdentity
    let providerSetCode: String
    let setName: String
    let artworkLabel: String
    let distributionLabel: String
    let imageURL: URL?
    let status: LorcanaPhysicalReviewStatus
    let identityEvidence: [LorcanaPhysicalEvidence]
    let finishes: [LorcanaPhysicalFinishEvidence]
    let finishUniverseEvidenceReference: String?
    /// Aliases may be shared by physical records under the same family. Such an
    /// alias is provenance, never authority to pick a printing or ownership key.
    let sourceAliases: [LorcanaSourceAlias]
    /// Absent on older signed catalogs. No family alias grants pricing authority.
    var marketMappings: [LorcanaMarketMapping]? = nil
}

struct LorcanaPhysicalUniverse: Codable, Sendable {
    let footer: LorcanaPrintedIdentity
    let printingIDs: [UUID]
    let isComplete: Bool
    let evidenceReference: String?
}

/// Corrections retain old identities as superseded rows. They never rewrite
/// an existing collection key or automatically migrate owned cards.
struct LorcanaPhysicalCorrection: Codable, Hashable, Sendable {
    let id: UUID
    let fromPrintingIDs: [UUID]
    let toPrintingIDs: [UUID]
    let evidenceReferences: [String]
}

struct LorcanaPhysicalCatalogManifest: Codable, Sendable {
    let schemaVersion: Int
    let reviewedAt: Date
    let printFamilies: [LorcanaPrintFamily]
    let canonicalCards: [LorcanaCanonicalCard]
    let physicalPrintings: [LorcanaPhysicalPrinting]
    let universes: [LorcanaPhysicalUniverse]
    let corrections: [LorcanaPhysicalCorrection]
}

/// Immutable, locally injected review contract; no signature or production
/// authority is implied by a record's reviewed status/evidence references.
struct LorcanaPhysicalCatalog: Sendable {
    enum ValidationError: Error, Equatable {
        case invalidManifest, duplicateIdentity, invalidCanonical, invalidPrinting
        case invalidUniverse, invalidCorrection, invalidTransition
    }

    let manifest: LorcanaPhysicalCatalogManifest
    let canonicalByID: [UUID: LorcanaCanonicalCard]
    let printingByID: [UUID: LorcanaPhysicalPrinting]
    let universesByFooter: [LorcanaPrintedIdentity: LorcanaPhysicalUniverse]

    init(manifest: LorcanaPhysicalCatalogManifest, families: [LorcanaPrintedIdentity: LorcanaPrintFamily]) throws {
        guard manifest.schemaVersion == 2, manifest.reviewedAt.timeIntervalSince1970.isFinite,
              manifest.reviewedAt.timeIntervalSince1970 > 0, manifest.canonicalCards.count <= 20_000,
              manifest.physicalPrintings.count <= 40_000, manifest.universes.count <= 20_000,
              manifest.corrections.count <= 20_000 else { throw ValidationError.invalidManifest }
        var canonical: [UUID: LorcanaCanonicalCard] = [:]
        for card in manifest.canonicalCards {
            guard Self.text(card.name), card.version == nil || Self.text(card.version!, allowEmpty: true),
                  Self.references(card.relationshipEvidenceReferences) else { throw ValidationError.invalidCanonical }
            guard canonical.updateValue(card, forKey: card.id) == nil else { throw ValidationError.duplicateIdentity }
        }
        var printings: [UUID: LorcanaPhysicalPrinting] = [:]
        var identities: Set<LorcanaPhysicalIdentity> = []
        var marketLanes: Set<String> = []
        for printing in manifest.physicalPrintings {
            guard let family = families[printing.identity.footer], canonical[printing.identity.canonicalCardID] != nil,
                  printing.providerSetCode == family.providerSetCode,
                  printing.identity.layout == family.layout,
                  Self.text(printing.setName), Self.text(printing.artworkLabel), Self.text(printing.distributionLabel),
                  Self.text(printing.identity.distributionID), Self.text(printing.identity.layout),
                  printing.identity.stamp == nil || Self.text(printing.identity.stamp!),
                  printing.imageURL == nil || Self.imageURL(printing.imageURL!),
                  !printing.sourceAliases.isEmpty, printing.sourceAliases.count <= 64,
                  Set(printing.sourceAliases).count == printing.sourceAliases.count,
                  Set(printing.sourceAliases).isSubset(of: Set(family.sourceAliases)),
                  printing.identityEvidence.count <= 64,
                  Set(printing.identityEvidence).count == printing.identityEvidence.count,
                  printing.identityEvidence.allSatisfy({ Self.text($0.reference) }),
                  printing.finishes.count <= LorcanaPhysicalFinish.allCases.count,
                  Set(printing.finishes.map(\.finish)).count == printing.finishes.count,
                  printing.finishes.allSatisfy({ Self.references($0.evidenceReferences) }),
                  printing.finishUniverseEvidenceReference == nil || Self.text(printing.finishUniverseEvidenceReference!) else {
                throw ValidationError.invalidPrinting
            }
            if printing.status == .verified {
                guard Set(printing.identityEvidence.map(\.kind)) == Set(LorcanaPhysicalEvidenceKind.allCases),
                      !printing.finishes.isEmpty, printing.finishUniverseEvidenceReference != nil else {
                    throw ValidationError.invalidPrinting
                }
            }
            let mappings = printing.marketMappings ?? []
            guard mappings.count <= printing.finishes.count,
                  Set(mappings.map(\.finish)).count == mappings.count else { throw ValidationError.invalidPrinting }
            for mapping in mappings {
                guard printing.identity.footer.language == "en", mapping.groupID > 0, mapping.productID > 0,
                      Self.text(mapping.productName), Self.text(mapping.productNumber),
                      [printing.identity.footer.collectorNumber,
                       printing.identity.footer.collectorNumber + "/" + printing.identity.footer.denominator].contains(mapping.productNumber),
                      mapping.hasValidMarketLane,
                      printing.finishes.contains(where: { $0.finish == mapping.finish }),
                      Self.references(mapping.evidenceReferences) else { throw ValidationError.invalidPrinting }
                // A marketplace lane cannot silently price two distinct active
                // physical objects (e.g. stamped versus ordinary or oversized).
                if printing.status != .superseded,
                   !marketLanes.insert("\(mapping.productID):\(mapping.providerVariantID)").inserted {
                    throw ValidationError.invalidPrinting
                }
            }
            guard printings.updateValue(printing, forKey: printing.id) == nil else { throw ValidationError.duplicateIdentity }
            // Two app IDs cannot describe one physical object. Superseded rows
            // retain history; their replacements may correct that old identity.
            if printing.status != .superseded, !identities.insert(printing.identity).inserted {
                throw ValidationError.duplicateIdentity
            }
        }
        let activeByFooter = Dictionary(grouping: printings.values.filter { $0.status != .superseded }, by: { $0.identity.footer })
        var universes: [LorcanaPrintedIdentity: LorcanaPhysicalUniverse] = [:]
        for universe in manifest.universes {
            guard families[universe.footer] != nil, universe.printingIDs.count <= 128,
                  Set(universe.printingIDs).count == universe.printingIDs.count,
                  Set(universe.printingIDs) == Set((activeByFooter[universe.footer] ?? []).map(\.id)),
                  universe.evidenceReference == nil || Self.text(universe.evidenceReference!),
                  !universe.isComplete || universe.evidenceReference != nil else { throw ValidationError.invalidUniverse }
            guard universes.updateValue(universe, forKey: universe.footer) == nil else { throw ValidationError.invalidUniverse }
        }
        var correctionIDs: Set<UUID> = []
        var successors: [UUID: Set<UUID>] = [:]
        for correction in manifest.corrections {
            let from = Set(correction.fromPrintingIDs), to = Set(correction.toPrintingIDs)
            guard correctionIDs.insert(correction.id).inserted, !from.isEmpty, !to.isEmpty,
                  from.count == correction.fromPrintingIDs.count, to.count == correction.toPrintingIDs.count,
                  from.count <= 128, to.count <= 128, from.isDisjoint(with: to),
                  from.allSatisfy({ printings[$0]?.status == .superseded }),
                  to.allSatisfy({ printings[$0] != nil }), Self.references(correction.evidenceReferences) else {
                throw ValidationError.invalidCorrection
            }
            for id in from { successors[id, default: []].formUnion(to) }
        }
        // Bounded graph traversal rejects cycles in correction history.
        var visited: Set<UUID> = [], visiting: Set<UUID> = []
        func visit(_ id: UUID) throws {
            if visited.contains(id) { return }
            guard visiting.insert(id).inserted, visiting.count <= 128 else { throw ValidationError.invalidCorrection }
            for next in successors[id] ?? [] { try visit(next) }
            visiting.remove(id); visited.insert(id)
        }
        for id in successors.keys { try visit(id) }
        guard printings.values.filter({ $0.status == .superseded }).allSatisfy({ successors[$0.id] != nil }) else {
            throw ValidationError.invalidCorrection
        }
        self.manifest = manifest
        canonicalByID = canonical; printingByID = printings; universesByFooter = universes
    }

    func validateTransition(from previous: LorcanaCatalogRegistry) throws {
        let currentFamilies = Dictionary(uniqueKeysWithValues: manifest.printFamilies.map { ($0.footer, $0) })
        for (footer, old) in previous.familiesByFooter {
            guard let current = currentFamilies[footer], Set(old.sourceAliases).isSubset(of: Set(current.sourceAliases)) else {
                throw ValidationError.invalidTransition
            }
        }
        guard let oldCatalog = previous.physicalCatalog else { return }
        guard oldCatalog.canonicalByID.allSatisfy({ id, old in
            guard let current = canonicalByID[id] else { return false }
            return Set(old.relationshipEvidenceReferences).isSubset(of: Set(current.relationshipEvidenceReferences))
        }),
              Set(oldCatalog.normalizedManifest.corrections).isSubset(of: Set(normalizedManifest.corrections)) else {
            throw ValidationError.invalidTransition
        }
        for (id, old) in oldCatalog.printingByID {
            guard let current = printingByID[id], current.identity == old.identity,
                  Set(old.sourceAliases).isSubset(of: Set(current.sourceAliases)),
                  old.finishes.allSatisfy({ oldFinish in
                      current.finishes.contains { $0.finish == oldFinish.finish
                          && Set(oldFinish.evidenceReferences).isSubset(of: Set($0.evidenceReferences)) }
                  }),
                  Set(old.identityEvidence).isSubset(of: Set(current.identityEvidence)),
                  old.status != .superseded || current.status == .superseded else {
                throw ValidationError.invalidTransition
            }
        }
    }

    /// A complete footer universe must include every active record, including
    /// unresolved/conflicted entries. Filtering those out cannot prove uniqueness.
    func reviewedPrintings(for footer: LorcanaPrintedIdentity) -> [LorcanaPhysicalPrinting]? {
        guard let universe = universesByFooter[footer], universe.isComplete, !universe.printingIDs.isEmpty else { return nil }
        let records = universe.printingIDs.compactMap { printingByID[$0] }
        guard records.allSatisfy({ $0.status == .verified }),
              Set(records.map { $0.identity.canonicalCardID }).count == 1 else { return nil }
        return records.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Canonical generation ignores array order, never identity or review edits.
    var normalizedManifest: LorcanaPhysicalCatalogManifest {
        .init(schemaVersion: 2, reviewedAt: manifest.reviewedAt, printFamilies: manifest.printFamilies,
              canonicalCards: manifest.canonicalCards.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                  .init(id: $0.id, name: $0.name, version: $0.version, relationshipEvidenceReferences: $0.relationshipEvidenceReferences.sorted())
              }, physicalPrintings: manifest.physicalPrintings.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                  .init(id: $0.id, identity: $0.identity, providerSetCode: $0.providerSetCode, setName: $0.setName,
                        artworkLabel: $0.artworkLabel, distributionLabel: $0.distributionLabel, imageURL: $0.imageURL,
                        status: $0.status, identityEvidence: $0.identityEvidence.sorted {
                            $0.kind.rawValue == $1.kind.rawValue ? $0.reference < $1.reference : $0.kind.rawValue < $1.kind.rawValue
                        }, finishes: $0.finishes.sorted { $0.finish.rawValue < $1.finish.rawValue }.map {
                            .init(finish: $0.finish, evidenceReferences: $0.evidenceReferences.sorted())
                        }, finishUniverseEvidenceReference: $0.finishUniverseEvidenceReference,
                        sourceAliases: $0.sourceAliases.sorted { $0.provider == $1.provider ? $0.id < $1.id : $0.provider < $1.provider },
                        marketMappings: $0.marketMappings.map { $0.map(\.normalized).sorted { $0.finish.rawValue < $1.finish.rawValue } })
              }, universes: manifest.universes.sorted { $0.footer.evidenceKey < $1.footer.evidenceKey }.map {
                  .init(footer: $0.footer, printingIDs: $0.printingIDs.sorted { $0.uuidString < $1.uuidString },
                        isComplete: $0.isComplete, evidenceReference: $0.evidenceReference)
              }, corrections: manifest.corrections.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                  .init(id: $0.id, fromPrintingIDs: $0.fromPrintingIDs.sorted { $0.uuidString < $1.uuidString },
                        toPrintingIDs: $0.toPrintingIDs.sorted { $0.uuidString < $1.uuidString }, evidenceReferences: $0.evidenceReferences.sorted())
              })
    }

    private static func text(_ value: String, allowEmpty: Bool = false) -> Bool {
        (allowEmpty || !value.isEmpty) && value.count <= 512 && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.rangeOfCharacter(from: .controlCharacters) == nil
    }
    private static func references(_ values: [String]) -> Bool {
        !values.isEmpty && values.count <= 64 && Set(values).count == values.count && values.allSatisfy { text($0) }
    }
    private static func imageURL(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return url.absoluteString.count <= 2_048 && parts.scheme == "https" && parts.host?.isEmpty == false
            && parts.user == nil && parts.password == nil && parts.fragment == nil
    }
}
