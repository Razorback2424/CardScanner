import Foundation

/// One exact Scryfall printing in the compact runtime treatment catalog.
///
/// The Scryfall id is the primary key. Set code and collector number are kept as
/// integrity checks so a damaged or accidentally regenerated resource cannot
/// enrich a different printing with the same local lookup context.
struct MagicTreatmentCatalogEntry: Codable, Equatable, Hashable, Sendable {
    let id: String
    let setCode: String
    let collectorNumber: String
    /// Stable `MagicTreatment.id` values. Strings keep the resource forward
    /// compatible: a newer artifact can carry a treatment an older build does
    /// not yet model, and that build preserves it as unclassified evidence.
    let treatments: [String]
    /// Qualifiers are keyed by treatment id. Scryfall identifies Neon Ink but
    /// does not identify its color, so the audited catalog stores it as
    /// ["neonink": "red"] rather than adding a treatment-specific field.
    let qualifiers: [String: String]

    init(
        id: String,
        setCode: String,
        collectorNumber: String,
        treatments: [String],
        qualifiers: [String: String] = [:]
    ) {
        self.id = id
        self.setCode = setCode
        self.collectorNumber = collectorNumber
        self.treatments = treatments
        self.qualifiers = qualifiers
    }

    enum CodingKeys: String, CodingKey {
        case id
        case setCode
        case collectorNumber
        case treatments
        case qualifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        setCode = try container.decode(String.self, forKey: .setCode)
        collectorNumber = try container.decode(String.self, forKey: .collectorNumber)
        treatments = try container.decode([String].self, forKey: .treatments)
        qualifiers = try container.decodeIfPresent(
            [String: String].self,
            forKey: .qualifiers
        ) ?? [:]
    }

    /// Classified and unclassified treatments, in resource order. Unknown ids
    /// remain visible without being guessed into a known current treatment.
    var decodedTreatments: [MagicTreatment] {
        var result: [MagicTreatment] = []
        for treatmentID in treatments {
            let treatment: MagicTreatment?
            if treatmentID.caseInsensitiveCompare("neonink") == .orderedSame {
                treatment = .neonInk
            } else {
                treatment = MagicTreatment(id: treatmentID)
            }
            guard let treatment, !result.contains(treatment) else { continue }
            result.append(treatment)
        }
        return result
    }
}

/// The app-sized projection of `MagicTreatmentSnapshot`.
///
/// The full audit remains test-only. This resource contains only exact cards
/// whose reviewed provider signals are one of the treatments this build models,
/// plus the manual Neon Ink color enrichment. It is small enough for the app
/// bundle and carries source fingerprints so regeneration is traceable.
struct MagicTreatmentCatalogArtifact: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let sourceAuditSchemaVersion: Int
    let sourceAuditRulesVersion: Int
    let sourceBulkDataID: String
    let sourceBulkDataType: String
    let sourceContentSHA256: String
    let generatedAt: String
    let entries: [MagicTreatmentCatalogEntry]
}

enum MagicTreatmentCatalogError: LocalizedError, Equatable, Sendable {
    case missingBundleResource
    case malformedArtifact
    case unsupportedArtifact
    case duplicateCardID(String)
    case invalidEntry(String)

    var errorDescription: String? {
        switch self {
        case .missingBundleResource:
            return "The bundled Magic treatment catalog is unavailable."
        case .malformedArtifact:
            return "The bundled Magic treatment catalog is malformed."
        case .unsupportedArtifact:
            return "The bundled Magic treatment catalog uses an unsupported schema."
        case let .duplicateCardID(id):
            return "The bundled Magic treatment catalog repeats card \(id)."
        case let .invalidEntry(id):
            return "The bundled Magic treatment catalog entry \(id) is invalid."
        }
    }
}

/// Validated exact-printing lookup used by the live Scryfall response model.
struct MagicTreatmentCatalog: Equatable, Sendable {
    static let schemaVersion = 2

    let artifact: MagicTreatmentCatalogArtifact
    private let entriesByCardID: [String: MagicTreatmentCatalogEntry]

    static let empty = MagicTreatmentCatalog(
        artifact: MagicTreatmentCatalogArtifact(
            schemaVersion: schemaVersion,
            sourceAuditSchemaVersion: 0,
            sourceAuditRulesVersion: 0,
            sourceBulkDataID: "",
            sourceBulkDataType: "",
            sourceContentSHA256: "",
            generatedAt: "",
            entries: []
        ),
        entriesByCardID: [:]
    )

    init(artifact: MagicTreatmentCatalogArtifact) throws {
        guard artifact.schemaVersion == Self.schemaVersion,
              artifact.sourceAuditSchemaVersion > 0,
              artifact.sourceAuditRulesVersion > 0,
              !artifact.sourceBulkDataID.isEmpty,
              !artifact.sourceBulkDataType.isEmpty,
              !artifact.sourceContentSHA256.isEmpty else {
            throw MagicTreatmentCatalogError.unsupportedArtifact
        }

        var entriesByCardID: [String: MagicTreatmentCatalogEntry] = [:]
        for entry in artifact.entries {
            let cardID = entry.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let setCode = entry.setCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let collectorNumber = entry.collectorNumber
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let treatmentIDs = entry.treatments
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let normalizedTreatmentIDs = treatmentIDs.map { $0.lowercased() }
            guard !cardID.isEmpty,
                  !setCode.isEmpty,
                  !collectorNumber.isEmpty,
                  !treatmentIDs.isEmpty,
                  normalizedTreatmentIDs.count == Set(normalizedTreatmentIDs).count else {
                throw MagicTreatmentCatalogError.invalidEntry(entry.id)
            }
            var qualifiers: [String: String] = [:]
            for (key, value) in entry.qualifiers {
                let normalizedKey = key
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedKey.isEmpty,
                      !normalizedValue.isEmpty,
                      normalizedTreatmentIDs.contains(normalizedKey),
                      qualifiers[normalizedKey] == nil else {
                    throw MagicTreatmentCatalogError.invalidEntry(entry.id)
                }
                qualifiers[normalizedKey] = normalizedValue
            }
            guard entriesByCardID[cardID.lowercased()] == nil else {
                throw MagicTreatmentCatalogError.duplicateCardID(entry.id)
            }

            let normalized = MagicTreatmentCatalogEntry(
                id: cardID,
                setCode: setCode,
                collectorNumber: collectorNumber,
                treatments: treatmentIDs,
                qualifiers: qualifiers
            )
            entriesByCardID[cardID.lowercased()] = normalized
        }

        self.init(artifact: artifact, entriesByCardID: entriesByCardID)
    }

    /// Returns the treatment(s) for an exact response. The compact catalog can
    /// restore reviewed historical classifications even when a future Scryfall
    /// response omits an optional signal, while the response signals continue to
    /// make newly published known treatments visible before the next artifact.
    func treatments(for card: ScryfallCard) -> [MagicTreatment] {
        let exactEntry = exactEntry(for: card)
        var result = exactEntry?.decodedTreatments ?? []

        let signals = Set(
            ((card.promoTypes ?? []) + (card.frameEffects ?? []))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        if signals.contains("surgefoil") {
            appendUnique(.surgeFoil, to: &result)
        }
        if signals.contains("neonink") {
            appendUnique(.neonInk, to: &result)
        }
        return result
    }

    func evidence(for card: ScryfallCard) -> MagicTreatmentEvidence {
        let exactEntry = exactEntry(for: card)
        let treatments = treatments(for: card)
        return MagicTreatmentEvidence(
            treatments: treatments,
            qualifiers: exactEntry?.qualifiers ?? [:]
        )
    }

    func entry(forCardID cardID: String) -> MagicTreatmentCatalogEntry? {
        entriesByCardID[cardID.lowercased()]
    }

    private func exactEntry(for card: ScryfallCard) -> MagicTreatmentCatalogEntry? {
        guard let entry = entry(forCardID: card.id),
              entry.setCode.caseInsensitiveCompare(card.setCode) == .orderedSame,
              entry.collectorNumber.caseInsensitiveCompare(card.collectorNumber)
                == .orderedSame else {
            return nil
        }
        return entry
    }

    private init(
        artifact: MagicTreatmentCatalogArtifact,
        entriesByCardID: [String: MagicTreatmentCatalogEntry]
    ) {
        self.artifact = artifact
        self.entriesByCardID = entriesByCardID
    }

    private func appendUnique(_ treatment: MagicTreatment, to result: inout [MagicTreatment]) {
        guard !result.contains(treatment) else { return }
        result.append(treatment)
    }
}

enum MagicTreatmentCatalogStore {
    /// Production code remains resilient to a missing or damaged optional
    /// enrichment resource. Treatment signals from the live card still work,
    /// while the compact catalog's manual qualifiers simply become unavailable.
    static let bundledDefault: MagicTreatmentCatalog = {
        (try? bundled()) ?? .empty
    }()

    static func bundled(bundle: Bundle = .main) throws -> MagicTreatmentCatalog {
        guard let root = bundle.url(
            forResource: "MagicTreatmentCatalog",
            withExtension: nil
        ) else {
            throw MagicTreatmentCatalogError.missingBundleResource
        }
        let manifestURL = root.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let artifact = try? JSONDecoder().decode(
                  MagicTreatmentCatalogArtifact.self,
                  from: data
              ) else {
            throw MagicTreatmentCatalogError.malformedArtifact
        }
        return try MagicTreatmentCatalog(artifact: artifact)
    }
}
