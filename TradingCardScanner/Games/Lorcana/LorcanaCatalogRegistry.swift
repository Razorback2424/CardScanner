import CryptoKit
import Foundation

/// Printed evidence identifies a print family, never an exact owned printing.
/// The denominator and printed marker are independent from a provider's set code.
struct LorcanaPrintedIdentity: Hashable, Codable, Sendable {
    let collectorNumber: String
    let denominator: String
    let language: String
    let printedSetMarker: String

    enum ValidationError: Error { case invalidFooter }

    init(collectorNumber: String, denominator: String, language: String, printedSetMarker: String) throws {
        guard Self.matches(collectorNumber, "[0-9]{1,4}"), let number = Int(collectorNumber), number > 0,
              Self.matches(denominator, "[A-Z0-9][A-Z0-9-]{0,11}"),
              Int(denominator) != 0,
              Self.matches(language, "[a-z]{2}"),
              Self.matches(printedSetMarker, "[A-Z0-9][A-Z0-9-]{0,11}") else {
            throw ValidationError.invalidFooter
        }
        self.collectorNumber = String(number)
        self.denominator = denominator
        self.language = language
        self.printedSetMarker = printedSetMarker
    }

    private enum CodingKeys: String, CodingKey {
        case collectorNumber, denominator, language, printedSetMarker
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(collectorNumber: values.decode(String.self, forKey: .collectorNumber),
                      denominator: values.decode(String.self, forKey: .denominator),
                      language: values.decode(String.self, forKey: .language),
                      printedSetMarker: values.decode(String.self, forKey: .printedSetMarker))
    }

    var displayIdentifier: String { "\(collectorNumber)/\(denominator) \(language.uppercased()) \(printedSetMarker)" }
    var evidenceKey: String { "\(language):\(printedSetMarker):\(collectorNumber):\(denominator)" }
    var familyID: String { "lorcana-family:\(evidenceKey)" }

    static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: "\\A(?:\(pattern))\\z", options: .regularExpression) != nil
    }
}

struct LorcanaSourceAlias: Hashable, Codable, Sendable {
    let provider: String
    let id: String
}

/// A reviewed footer-to-source mapping remains provisional physical evidence.
/// No finish, market SKU, artwork ownership, or gameplay equivalence is inferred.
struct LorcanaPrintFamily: Codable, Sendable {
    let footer: LorcanaPrintedIdentity
    let providerSetCode: String
    let name: String
    let version: String?
    let rarity: String
    let layout: String
    let sourceAliases: [LorcanaSourceAlias]
    let footerEvidenceReference: String

    var displayName: String {
        if let version, !version.isEmpty { return "\(name) — \(version)" }
        return name
    }
}

struct LorcanaCatalogManifest: Codable, Sendable {
    let schemaVersion: Int
    let printFamilies: [LorcanaPrintFamily]
}

/// Local research snapshot. Construction validates mappings but does not confer
/// signed-release authority or prove the completeness of any physical universe.
struct LorcanaCatalogRegistry: Sendable {
    enum ValidationError: Error, Equatable {
        case unsupportedSchema
        case invalidFamily
        case duplicateFooter
        case duplicateSourceAlias
        case oversizedManifest
    }

    let generation: String
    let familiesByFooter: [LorcanaPrintedIdentity: LorcanaPrintFamily]
    let customWords: [String]
    let denominatorsByScope: [String: Set<String>]

    init(data: Data) throws {
        guard data.count <= 8 * 1_024 * 1_024 else { throw ValidationError.oversizedManifest }
        try self.init(manifest: JSONDecoder().decode(LorcanaCatalogManifest.self, from: data))
    }

    init(manifest: LorcanaCatalogManifest) throws {
        guard manifest.schemaVersion == 1 else { throw ValidationError.unsupportedSchema }
        guard manifest.printFamilies.count <= 20_000 else { throw ValidationError.oversizedManifest }
        var families: [LorcanaPrintedIdentity: LorcanaPrintFamily] = [:]
        var aliases: Set<LorcanaSourceAlias> = []
        for family in manifest.printFamilies {
            guard [family.providerSetCode, family.name, family.rarity, family.layout, family.footerEvidenceReference]
                .allSatisfy({ !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) && $0.count <= 512 }),
                  family.version == nil || (family.version!.count <= 512 && family.version! == family.version!.trimmingCharacters(in: .whitespacesAndNewlines)),
                  !family.sourceAliases.isEmpty,
                  family.sourceAliases.allSatisfy({
                      LorcanaPrintedIdentity.matches($0.provider, "[a-z][a-z0-9-]{0,31}")
                          && !$0.id.isEmpty && $0.id.count <= 256
                          && $0.id == $0.id.trimmingCharacters(in: .whitespacesAndNewlines)
                  }) else { throw ValidationError.invalidFamily }
            guard families.updateValue(family, forKey: family.footer) == nil else {
                throw ValidationError.duplicateFooter
            }
            for alias in family.sourceAliases {
                guard aliases.insert(alias).inserted else { throw ValidationError.duplicateSourceAlias }
            }
        }
        familiesByFooter = families
        denominatorsByScope = Dictionary(grouping: families.keys, by: { "\($0.language):\($0.printedSetMarker)" })
            .mapValues { Set($0.map(\.denominator)) }
        customWords = Array(Set(families.keys.flatMap { [$0.printedSetMarker, $0.denominator, $0.language.uppercased()] })).sorted()
        // Stable content generation protects choices/retries when metadata changes.
        let normalized = LorcanaCatalogManifest(schemaVersion: 1, printFamilies: manifest.printFamilies
            .sorted { $0.footer.evidenceKey < $1.footer.evidenceKey }.map { family in
                .init(footer: family.footer, providerSetCode: family.providerSetCode, name: family.name,
                      version: family.version, rarity: family.rarity, layout: family.layout,
                      sourceAliases: family.sourceAliases.sorted {
                          $0.provider == $1.provider ? $0.id < $1.id : $0.provider < $1.provider
                      }, footerEvidenceReference: family.footerEvidenceReference)
            })
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        generation = "lorcana:s1:" + SHA256.hash(data: try encoder.encode(normalized)).map { String(format: "%02x", $0) }.joined()
    }
}
