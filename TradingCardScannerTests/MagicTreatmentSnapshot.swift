import Foundation

/// The committed Scryfall audit snapshot used to answer questions about Magic
/// collector-number suffixes and treatment metadata without putting a bulk-data
/// download on the scan path or on ordinary test runs.
enum MagicTreatmentSnapshotVersion {
    static let schema = 2
    static let auditRules = 1
    static let sourceBulkDataType = "default_cards"
}

struct MagicTreatmentSnapshotSource: Codable, Sendable, Equatable {
    let bulkDataID: String
    let bulkDataType: String
    let downloadURI: String
    let updatedAt: String?
    let contentSHA256: String

    init(
        bulkDataID: String,
        bulkDataType: String,
        downloadURI: String,
        updatedAt: String?,
        contentSHA256: String
    ) {
        self.bulkDataID = bulkDataID
        self.bulkDataType = bulkDataType
        self.downloadURI = downloadURI
        self.updatedAt = updatedAt
        self.contentSHA256 = contentSHA256
    }
}

/// A manually verified classification for a treatment whose provider metadata
/// does not contain the user-facing distinction needed by the catalog.
struct MagicTreatmentSnapshotManualCardMapping: Codable, Sendable, Equatable {
    let cardID: String
    let collectorNumber: String
    let value: String
}

struct MagicTreatmentSnapshotManualMapping: Codable, Sendable, Equatable {
    let id: String
    let setCode: String
    let treatment: String
    let cards: [MagicTreatmentSnapshotManualCardMapping]
    let provenanceURLs: [String]
}

/// The source-backed exceptions are kept beside the schema so regeneration
/// cannot silently discard a hand-verified distinction. Scryfall identifies
/// these four printings as `neonink`, but does not encode their ink color.
#if DEBUG
enum MagicTreatmentSnapshotManualEvidence {
    static let mappings: [MagicTreatmentSnapshotManualMapping] = [
        MagicTreatmentSnapshotManualMapping(
            id: "neo-neonink-color",
            setCode: "neo",
            treatment: "neonink",
            cards: [
                MagicTreatmentSnapshotManualCardMapping(
                    cardID: "4826991d-c3c3-45ff-9dfc-4246a84b40e0",
                    collectorNumber: "429",
                    value: "red"
                ),
                MagicTreatmentSnapshotManualCardMapping(
                    cardID: "c046b0b3-05f0-4468-817f-355e87552faf",
                    collectorNumber: "430",
                    value: "green"
                ),
                MagicTreatmentSnapshotManualCardMapping(
                    cardID: "92da2c98-afe0-4e7a-9510-5a74cc2cdde4",
                    collectorNumber: "431",
                    value: "blue"
                ),
                MagicTreatmentSnapshotManualCardMapping(
                    cardID: "78c0b64b-cade-414d-b893-ac1b633c66d0",
                    collectorNumber: "432",
                    value: "yellow"
                )
            ],
            provenanceURLs: [
                "https://media.wizards.com/2022/downloads/card-sets/NEO_Cardlist_02092022.pdf",
                "https://magic.wizards.com/en/news/feature/collecting-kamigawa-neon-dynasty-2022-01-27"
            ]
        )
    ]
}
#endif

struct MagicTreatmentSnapshotManifest: Codable, Sendable, Equatable {
    let schemaVersion: Int
    let rulesVersion: Int
    let generatedAt: String
    let source: MagicTreatmentSnapshotSource
    let totalCardCount: Int
    let auditedCardCount: Int
    let manualMappings: [MagicTreatmentSnapshotManualMapping]
    let entries: [MagicTreatmentSnapshotSetEntry]

    var isSupported: Bool {
        schemaVersion == MagicTreatmentSnapshotVersion.schema
            && rulesVersion == MagicTreatmentSnapshotVersion.auditRules
            && source.bulkDataType == MagicTreatmentSnapshotVersion.sourceBulkDataType
    }
}

struct MagicTreatmentSnapshotSetEntry: Codable, Sendable, Equatable {
    let code: String
    let name: String
    let releaseDate: String?
    let setType: String?
    let totalCardCount: Int
    let auditedCardCount: Int
    let collectorNumberSuffixCounts: [String: Int]
    let promoTypeCounts: [String: Int]
    let frameEffectCounts: [String: Int]
    let variationCount: Int
    let variationOfCount: Int
    /// Relative to the bundled snapshot directory. A set with no audit rows
    /// has no resource; its zero counts still remain in the manifest so the
    /// all-history denominator is explicit.
    let resource: String?
}

struct MagicTreatmentSnapshotCard: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let setCode: String
    let setName: String
    let collectorNumber: String
    let collectorNumberSuffix: String?
    let language: String
    let digital: Bool
    let layout: String?
    let rarity: String?
    let releasedAt: String?
    let finishes: [String]
    let promoTypes: [String]
    let frameEffects: [String]
    let variation: Bool?
    let variationOf: String?
}

/// The loaded, validated view of the manifest and its audit rows.
struct MagicTreatmentSnapshot: Sendable, Equatable {
    let manifest: MagicTreatmentSnapshotManifest
    let cardsBySetCode: [String: [MagicTreatmentSnapshotCard]]

    func cards(forSetCode code: String) -> [MagicTreatmentSnapshotCard] {
        cardsBySetCode[code.lowercased()] ?? []
    }

    var auditedCards: [MagicTreatmentSnapshotCard] {
        cardsBySetCode.values.flatMap { $0 }
    }
}

enum MagicTreatmentSnapshotError: LocalizedError, Sendable, Equatable {
    case missingBundleResource
    case unsupportedManifest
    case malformedManifest
    case missingResource(String)
    case malformedResource(String)
    case resourceSetMismatch(String)
    case invalidManualMapping(String)

    var errorDescription: String? {
        switch self {
        case .missingBundleResource:
            return "The bundled Magic treatment audit snapshot is unavailable."
        case .unsupportedManifest:
            return "The bundled Magic treatment audit snapshot uses an unsupported schema."
        case .malformedManifest:
            return "The bundled Magic treatment audit manifest is malformed."
        case let .missingResource(resource):
            return "The Magic treatment audit resource \(resource) is missing."
        case let .malformedResource(resource):
            return "The Magic treatment audit resource \(resource) is malformed."
        case let .resourceSetMismatch(resource):
            return "The Magic treatment audit resource \(resource) contains another set."
        case let .invalidManualMapping(mapping):
            return "The Magic treatment audit manual mapping \(mapping) is invalid."
        }
    }
}

/// Strict reader for the committed audit artifact. Unlike the runtime catalog
/// snapshot, this reader fails on a damaged resource: a partial audit would be
/// more dangerous than an absent audit when it is used to make parser rules.
enum MagicTreatmentSnapshotStore {
    static func bundled(bundle: Bundle = .main) throws -> MagicTreatmentSnapshot {
        guard let root = bundle.url(
            forResource: "MagicTreatmentSnapshot",
            withExtension: nil
        ) else {
            throw MagicTreatmentSnapshotError.missingBundleResource
        }
        return try load(from: root)
    }

    static func load(from directory: URL) throws -> MagicTreatmentSnapshot {
        let decoder = JSONDecoder()
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? decoder.decode(
                MagicTreatmentSnapshotManifest.self,
                from: manifestData
              ) else {
            throw MagicTreatmentSnapshotError.malformedManifest
        }
        guard manifest.isSupported else {
            throw MagicTreatmentSnapshotError.unsupportedManifest
        }
        guard manifest.totalCardCount >= manifest.auditedCardCount,
              !manifest.entries.isEmpty,
              manifest.source.contentSHA256.isEmpty == false else {
            throw MagicTreatmentSnapshotError.malformedManifest
        }

        var seenCodes = Set<String>()
        var cardsBySetCode: [String: [MagicTreatmentSnapshotCard]] = [:]
        var totalCardCount = 0
        var auditedCardCount = 0

        for entry in manifest.entries {
            let normalizedCode = entry.code.lowercased()
            guard !normalizedCode.isEmpty,
                  seenCodes.insert(normalizedCode).inserted,
                  entry.totalCardCount >= entry.auditedCardCount,
                  entry.auditedCardCount >= 0 else {
                throw MagicTreatmentSnapshotError.malformedManifest
            }
            totalCardCount += entry.totalCardCount
            auditedCardCount += entry.auditedCardCount

            guard let resource = entry.resource else {
                guard entry.auditedCardCount == 0 else {
                    throw MagicTreatmentSnapshotError.malformedManifest
                }
                cardsBySetCode[normalizedCode] = []
                continue
            }
            guard resource.hasPrefix("sets/"),
                  !resource.contains(".."),
                  !resource.contains("//") else {
                throw MagicTreatmentSnapshotError.malformedManifest
            }
            let file = directory.appendingPathComponent(resource)
            guard FileManager.default.fileExists(atPath: file.path) else {
                throw MagicTreatmentSnapshotError.missingResource(resource)
            }
            guard let data = try? Data(contentsOf: file),
                  let cards = try? decoder.decode(
                    [MagicTreatmentSnapshotCard].self,
                    from: data
                  ) else {
                throw MagicTreatmentSnapshotError.malformedResource(resource)
            }
            guard cards.count == entry.auditedCardCount,
                  Set(cards.map { $0.id }).count == cards.count,
                  cards.allSatisfy({ card in
                      let hasAuditSignal = card.collectorNumberSuffix != nil
                          || !card.promoTypes.isEmpty
                          || !card.frameEffects.isEmpty
                          || card.variation == true
                          || card.variationOf != nil
                      return hasAuditSignal
                          && card.collectorNumberSuffix
                              == MagicTreatmentSnapshotAudit.collectorNumberSuffix(
                                  in: card.collectorNumber
                              )
                  }),
                  cards.allSatisfy({ $0.setCode.lowercased() == normalizedCode }) else {
                throw MagicTreatmentSnapshotError.resourceSetMismatch(resource)
            }
            guard MagicTreatmentSnapshotAudit.counts(
                cards.compactMap { $0.collectorNumberSuffix }
            ) == entry.collectorNumberSuffixCounts,
            MagicTreatmentSnapshotAudit.counts(
                cards.flatMap { $0.promoTypes }
            ) == entry.promoTypeCounts,
            MagicTreatmentSnapshotAudit.counts(
                cards.flatMap { $0.frameEffects }
            ) == entry.frameEffectCounts,
            cards.filter({ $0.variation == true }).count == entry.variationCount,
            cards.filter({ $0.variationOf != nil }).count == entry.variationOfCount else {
                throw MagicTreatmentSnapshotError.resourceSetMismatch(resource)
            }
            cardsBySetCode[normalizedCode] = cards
        }

        guard totalCardCount == manifest.totalCardCount,
              auditedCardCount == manifest.auditedCardCount else {
            throw MagicTreatmentSnapshotError.malformedManifest
        }
        try MagicTreatmentSnapshotAudit.validateManualMappings(
            manifest.manualMappings,
            cardsBySetCode: cardsBySetCode
        )
        return MagicTreatmentSnapshot(
            manifest: manifest,
            cardsBySetCode: cardsBySetCode
        )
    }
}

#if DEBUG
/// The exact card shape needed from Scryfall's `default_cards` bulk file.
/// Keeping this separate from `ScryfallCard` makes the audit resilient to the
/// app's network response model and keeps the committed artifact's scope clear.
struct MagicTreatmentSourceCard: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let setCode: String
    let setName: String
    let collectorNumber: String
    let language: String
    let digital: Bool
    let layout: String?
    let rarity: String?
    let releasedAt: String?
    let setType: String?
    let finishes: [String]
    let promoTypes: [String]
    let frameEffects: [String]
    let variation: Bool?
    let variationOf: String?

    init(
        id: String,
        name: String,
        setCode: String,
        setName: String,
        collectorNumber: String,
        language: String = "en",
        digital: Bool = false,
        layout: String? = nil,
        rarity: String? = nil,
        releasedAt: String? = nil,
        setType: String? = nil,
        finishes: [String] = [],
        promoTypes: [String] = [],
        frameEffects: [String] = [],
        variation: Bool? = nil,
        variationOf: String? = nil
    ) {
        self.id = id
        self.name = name
        self.setCode = setCode
        self.setName = setName
        self.collectorNumber = collectorNumber
        self.language = language
        self.digital = digital
        self.layout = layout
        self.rarity = rarity
        self.releasedAt = releasedAt
        self.setType = setType
        self.finishes = finishes
        self.promoTypes = promoTypes
        self.frameEffects = frameEffects
        self.variation = variation
        self.variationOf = variationOf
    }

    enum CodingKeys: String, CodingKey {
        case id, name, digital, layout, rarity, finishes
        case setCode = "set"
        case setName = "set_name"
        case collectorNumber = "collector_number"
        case language = "lang"
        case releasedAt = "released_at"
        case setType = "set_type"
        case promoTypes = "promo_types"
        case frameEffects = "frame_effects"
        case variation
        case variationOf = "variation_of"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        setCode = try container.decode(String.self, forKey: .setCode)
        setName = try container.decodeIfPresent(String.self, forKey: .setName) ?? ""
        collectorNumber = try container.decode(String.self, forKey: .collectorNumber)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en"
        digital = try container.decodeIfPresent(Bool.self, forKey: .digital) ?? false
        layout = try container.decodeIfPresent(String.self, forKey: .layout)
        rarity = try container.decodeIfPresent(String.self, forKey: .rarity)
        releasedAt = try container.decodeIfPresent(String.self, forKey: .releasedAt)
        setType = try container.decodeIfPresent(String.self, forKey: .setType)
        finishes = try container.decodeIfPresent([String].self, forKey: .finishes) ?? []
        promoTypes = try container.decodeIfPresent([String].self, forKey: .promoTypes) ?? []
        frameEffects = try container.decodeIfPresent([String].self, forKey: .frameEffects) ?? []
        variation = try container.decodeIfPresent(Bool.self, forKey: .variation)
        variationOf = try container.decodeIfPresent(String.self, forKey: .variationOf)
    }
}

enum MagicTreatmentSnapshotGenerator {
    static let defaultBulkDataType = MagicTreatmentSnapshotVersion.sourceBulkDataType

    static func generate(
        inputFile: URL,
        outputDirectory: URL,
        source: MagicTreatmentSnapshotSource,
        generatedAt: String = currentISO8601(),
        manualMappings: [MagicTreatmentSnapshotManualMapping]
            = MagicTreatmentSnapshotManualEvidence.mappings
    ) throws {
        let cards = try decodeSourceCards(from: inputFile)
        let snapshot = try makeSnapshot(
            from: cards,
            source: source,
            generatedAt: generatedAt,
            manualMappings: manualMappings
        )
        try write(snapshot, to: outputDirectory)
    }

    /// Scryfall's current bulk API publishes JSON Lines in a gzip archive. The
    /// older `download_uri` response was a JSON array, so accepting both keeps
    /// the release tool reproducible across the API's metadata transition.
    private static func decodeSourceCards(from inputFile: URL) throws -> [MagicTreatmentSourceCard] {
        let firstChunk: Data
        do {
            let handle = try FileHandle(forReadingFrom: inputFile)
            firstChunk = handle.readData(ofLength: 4_096)
            try? handle.close()
        }
        let firstNonWhitespace = firstChunk.first {
            ![0x20, 0x09, 0x0A, 0x0D].contains($0)
        }
        if firstNonWhitespace == 0x5B { // "["
            let data = try Data(contentsOf: inputFile)
            return try JSONDecoder().decode([MagicTreatmentSourceCard].self, from: data)
        }

        let handle = try FileHandle(forReadingFrom: inputFile)
        defer { try? handle.close() }
        let decoder = JSONDecoder()
        var pending = Data()
        var result: [MagicTreatmentSourceCard] = []

        while true {
            let chunk = handle.readData(ofLength: 1_048_576)
            if chunk.isEmpty { break }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[..<newline]
                pending.removeSubrange(pending.startIndex..<pending.index(after: newline))
                let trimmed = line.drop(while: { [0x20, 0x09, 0x0D].contains($0) })
                guard !trimmed.isEmpty else { continue }
                result.append(try decoder.decode(MagicTreatmentSourceCard.self, from: Data(trimmed)))
            }
        }

        let trimmed = pending.drop(while: { [0x20, 0x09, 0x0D, 0x0A].contains($0) })
        if !trimmed.isEmpty {
            result.append(try decoder.decode(MagicTreatmentSourceCard.self, from: Data(trimmed)))
        }
        return result
    }

    static func makeSnapshot(
        from cards: [MagicTreatmentSourceCard],
        source: MagicTreatmentSnapshotSource,
        generatedAt: String = currentISO8601(),
        manualMappings: [MagicTreatmentSnapshotManualMapping] = []
    ) throws -> MagicTreatmentSnapshot {
        let groups = Dictionary(grouping: cards) { $0.setCode.lowercased() }
        guard !groups.isEmpty,
              groups.keys.allSatisfy({ !$0.isEmpty }) else {
            throw MagicTreatmentSnapshotError.malformedManifest
        }

        let entriesAndCards = groups.keys.sorted().map { code in
            let sourceCards = (groups[code] ?? []).sorted { left, right in
                (left.collectorNumber, left.id) < (right.collectorNumber, right.id)
            }
            let auditedCards = sourceCards.filter(isAuditRelevant)
            let first = sourceCards[0]
            let suffixCounts = counts(
                sourceCards.compactMap { collectorNumberSuffix(in: $0.collectorNumber) }
            )
            let promoTypeCounts = counts(
                sourceCards.flatMap { canonicalList($0.promoTypes) }
            )
            let frameEffectCounts = counts(
                sourceCards.flatMap { canonicalList($0.frameEffects) }
            )
            let cards = auditedCards.map(snapshotCard)
            let resourceFingerprint = MagicTreatmentSnapshotFingerprint.string(
                [source.bulkDataID, code, first.setName].joined(separator: "|")
            )
            let resource = cards.isEmpty
                ? nil
                : "sets/\(resourceFingerprint).json"
            let entry = MagicTreatmentSnapshotSetEntry(
                code: first.setCode,
                name: first.setName,
                releaseDate: first.releasedAt,
                setType: first.setType,
                totalCardCount: sourceCards.count,
                auditedCardCount: cards.count,
                collectorNumberSuffixCounts: suffixCounts,
                promoTypeCounts: promoTypeCounts,
                frameEffectCounts: frameEffectCounts,
                variationCount: sourceCards.filter { $0.variation == true }.count,
                variationOfCount: sourceCards.filter { $0.variationOf != nil }.count,
                resource: resource
            )
            return (entry, cards)
        }

        let cardsBySetCode = Dictionary(uniqueKeysWithValues: entriesAndCards.map {
            ($0.0.code.lowercased(), $0.1)
        })
        try MagicTreatmentSnapshotAudit.validateManualMappings(
            manualMappings,
            cardsBySetCode: cardsBySetCode
        )

        let manifest = MagicTreatmentSnapshotManifest(
            schemaVersion: MagicTreatmentSnapshotVersion.schema,
            rulesVersion: MagicTreatmentSnapshotVersion.auditRules,
            generatedAt: generatedAt,
            source: source,
            totalCardCount: cards.count,
            auditedCardCount: entriesAndCards.reduce(0) { $0 + $1.1.count },
            manualMappings: manualMappings,
            entries: entriesAndCards.map(\.0)
        )
        return MagicTreatmentSnapshot(
            manifest: manifest,
            cardsBySetCode: cardsBySetCode
        )
    }

    static func write(
        _ snapshot: MagicTreatmentSnapshot,
        to outputDirectory: URL
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let resourceDirectory = outputDirectory.appendingPathComponent("sets", isDirectory: true)
        try fileManager.createDirectory(at: resourceDirectory, withIntermediateDirectories: true)

        // Resources are written before the manifest. A failed run therefore
        // leaves the previous manifest as the last known-good publication.
        for entry in snapshot.manifest.entries {
            guard let resource = entry.resource else { continue }
            let file = outputDirectory.appendingPathComponent(resource)
            try fileManager.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(snapshot.cards(forSetCode: entry.code))
                .write(to: file, options: .atomic)
        }
        let manifestURL = outputDirectory.appendingPathComponent("manifest.json")
        try encoder.encode(snapshot.manifest).write(to: manifestURL, options: .atomic)

        let resources = Set(snapshot.manifest.compactResources)
        if let files = try? fileManager.contentsOfDirectory(
            at: resourceDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for file in files where !resources.contains("sets/" + file.lastPathComponent) {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    /// Returns a suffix only when it is directly bound to an all-numeric
    /// collector-number stem. This deliberately does not interpret spaces,
    /// slashes, stars, or rarity context; those are separate questions and a
    /// false suffix would poison the empirical audit.
    static func collectorNumberSuffix(in collectorNumber: String) -> String? {
        MagicTreatmentSnapshotAudit.collectorNumberSuffix(in: collectorNumber)
    }

    private static func isAuditRelevant(_ card: MagicTreatmentSourceCard) -> Bool {
        collectorNumberSuffix(in: card.collectorNumber) != nil
            || !card.promoTypes.isEmpty
            || !card.frameEffects.isEmpty
            || card.variation == true
            || card.variationOf != nil
    }

    private static func snapshotCard(
        _ card: MagicTreatmentSourceCard
    ) -> MagicTreatmentSnapshotCard {
        MagicTreatmentSnapshotCard(
            id: card.id,
            name: card.name,
            setCode: card.setCode,
            setName: card.setName,
            collectorNumber: card.collectorNumber,
            collectorNumberSuffix: collectorNumberSuffix(in: card.collectorNumber),
            language: card.language,
            digital: card.digital,
            layout: card.layout,
            rarity: card.rarity,
            releasedAt: card.releasedAt,
            finishes: canonicalList(card.finishes),
            promoTypes: canonicalList(card.promoTypes),
            frameEffects: canonicalList(card.frameEffects),
            variation: card.variation,
            variationOf: card.variationOf
        )
    }

    private static func canonicalList(_ values: [String]) -> [String] {
        MagicTreatmentSnapshotAudit.canonicalList(values)
    }

    private static func canonicalSignal(_ value: String) -> String {
        MagicTreatmentSnapshotAudit.canonicalSignal(value)
    }

    private static func counts(_ values: [String]) -> [String: Int] {
        MagicTreatmentSnapshotAudit.counts(values)
    }

    private static func currentISO8601() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

private extension MagicTreatmentSnapshotManifest {
    var compactResources: [String] {
        entries.compactMap(\.resource)
    }
}
#endif

private enum MagicTreatmentSnapshotFingerprint {
    static func string(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

private enum MagicTreatmentSnapshotAudit {
    static func collectorNumberSuffix(in collectorNumber: String) -> String? {
        let value = collectorNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        var suffixStart = value.endIndex
        while suffixStart > value.startIndex {
            let previous = value.index(before: suffixStart)
            guard value[previous].isASCII,
                  value[previous].isLetter else { break }
            suffixStart = previous
        }
        guard suffixStart < value.endIndex else { return nil }
        let stem = value[..<suffixStart]
        guard !stem.isEmpty,
              stem.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }) else {
            return nil
        }
        return value[suffixStart...].lowercased()
    }

    static func canonicalList(_ values: [String]) -> [String] {
        Array(Set(values.map(canonicalSignal).filter { !$0.isEmpty })).sorted()
    }

    static func canonicalSignal(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func counts(_ values: [String]) -> [String: Int] {
        values.map(canonicalSignal).filter { !$0.isEmpty }.reduce(into: [:]) { result, value in
            result[value, default: 0] += 1
        }
    }

    static func validateManualMappings(
        _ mappings: [MagicTreatmentSnapshotManualMapping],
        cardsBySetCode: [String: [MagicTreatmentSnapshotCard]]
    ) throws {
        var seenMappingIDs = Set<String>()

        for mapping in mappings {
            let mappingID = canonicalSignal(mapping.id)
            let setCode = canonicalSignal(mapping.setCode)
            let treatment = canonicalSignal(mapping.treatment)
            guard !mappingID.isEmpty,
                  seenMappingIDs.insert(mappingID).inserted,
                  !setCode.isEmpty,
                  !treatment.isEmpty,
                  !mapping.cards.isEmpty,
                  !mapping.provenanceURLs.isEmpty,
                  mapping.provenanceURLs.allSatisfy(isOfficialProvenanceURL),
                  let cards = cardsBySetCode[setCode] else {
                throw MagicTreatmentSnapshotError.invalidManualMapping(mapping.id)
            }

            let treatmentCards = cards.filter { card in
                card.promoTypes.contains(treatment)
                    || card.frameEffects.contains(treatment)
            }
            let treatmentCardIDs = Set(treatmentCards.map(\.id))
            let mappedCardIDs = Set(mapping.cards.map(\.cardID))
            guard mapping.cards.count == mappedCardIDs.count,
                  mappedCardIDs == treatmentCardIDs else {
                throw MagicTreatmentSnapshotError.invalidManualMapping(mapping.id)
            }

            for mappedCard in mapping.cards {
                guard !mappedCard.cardID.isEmpty,
                      !mappedCard.collectorNumber.isEmpty,
                      !canonicalSignal(mappedCard.value).isEmpty,
                      let card = cards.first(where: { $0.id == mappedCard.cardID }),
                      card.collectorNumber == mappedCard.collectorNumber,
                      card.promoTypes.contains(treatment)
                          || card.frameEffects.contains(treatment) else {
                    throw MagicTreatmentSnapshotError.invalidManualMapping(mapping.id)
                }
            }
        }
    }

    private static func isOfficialProvenanceURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased() else {
            return false
        }
        return host == "wizards.com" || host.hasSuffix(".wizards.com")
    }
}
