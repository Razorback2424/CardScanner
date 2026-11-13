import Foundation

/// A collector's own description of a Pokémon card they hold that the catalog
/// cannot verify yet: a finish or stamp the printing is not known to have, or a
/// printing from a set the catalog does not contain.
///
/// The report travels with an ownership row as JSON (`CollectedCard
/// .unverifiedReportJSON`). Protection never depends on decoding it: the row's
/// collection key carries the marker (`UnverifiedReportKey`), so a damaged or
/// newer-format report still leaves the row unverified, unpriced, and untouched
/// by automatic processing.
struct UnverifiedReport: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    enum Kind: String, Codable, Sendable {
        /// The printing is in the catalog; only the physical variant is missing.
        case knownCard
        /// The printed set or number is not in the catalog at all.
        case unknownSet
    }

    /// What the collector read or typed, kept verbatim. Never normalized into a
    /// catalog identity: that is the link's job, after the catalog catches up.
    struct ObservedIdentity: Codable, Equatable, Sendable {
        var setCode: String
        var setName: String?
        var number: String
        var name: String?
    }

    var schemaVersion: Int = Self.currentSchemaVersion
    var reportID: UUID
    var kind: Kind
    /// The catalog printing the collector confirmed. Present for `.knownCard`.
    /// Deliberately not stored in `providerID` or `catalogProviderID`: no code
    /// that matches ownership rows by provider identity may find this row.
    var baseProviderID: String?
    var reportedFinishID: String?
    var reportedStamps: [String] = []
    var reportedSubtype: String?
    /// "Other (describe)". A report with a note is never linked automatically.
    var note: String?
    var observed: ObservedIdentity?
    var createdAt: Date
    var catalogRevisionAtCreation: Int?
    /// The base printing's catalog variants when the report was made. A later
    /// automatic link must match a variant that is *not* in this list, so an
    /// unchanged catalog can never resolve the report it failed to describe.
    var knownVariantIDsAtCreation: [String] = []
    var lastEvaluatedCatalogRevision: Int?
    /// Raw so a newer build can add states without an older build failing to
    /// decode the whole report.
    var reviewStateRaw: String = ReviewState.waiting.rawValue
    var reviewDismissedAt: Date?
    var linkedAt: Date?
    /// Set when the collector undid a link. Such a report never links
    /// automatically again; it waits for the collector's review.
    var unlinkedAt: Date?
    /// Everything undo needs to put the row back exactly as it was. Present
    /// only while linked.
    var preLinkIdentity: PreLinkIdentity?
    /// The dated corrections the link wrote, one per acquisition claim. Undo
    /// writes the opposite corrections; the ledger history is never edited.
    var linkOperationIDs: [UUID] = []

    /// The unverified row's identity fields, captured at link time.
    struct PreLinkIdentity: Codable, Equatable, Sendable {
        var collectionKey: String
        var providerID: String
        var catalogProviderID: String?
        var variantID: String?
        var variantLabel: String?
        var variantResolutionRaw: String?
        var identityResolutionRaw: String
        var name: String
        var setName: String
        var setCode: String
        var cardNumber: String
        var rarity: String?
        var imageURL: String?
        var thumbnailURL: String?
        var setReleaseOrder: Int
        var pokemonPrintRunRaw: String?

        init(_ row: CollectedCard) {
            collectionKey = row.collectionKey
            providerID = row.providerID
            catalogProviderID = row.catalogProviderID
            variantID = row.variantID
            variantLabel = row.variantLabel
            variantResolutionRaw = row.variantResolutionRaw
            identityResolutionRaw = row.identityResolutionRaw
            name = row.name
            setName = row.setName
            setCode = row.setCode
            cardNumber = row.cardNumber
            rarity = row.rarity
            imageURL = row.imageURL
            thumbnailURL = row.thumbnailURL
            setReleaseOrder = row.setReleaseOrder
            pokemonPrintRunRaw = row.pokemonPrintRunRaw
        }
    }

    enum ReviewState: String, Sendable {
        case waiting
        case needsReview
        /// The ownership history cannot be linked by this build (for example a
        /// partly removed acquisition). Not something the collector can fix.
        case linkUnavailable
    }

    init(
        reportID: UUID = UUID(),
        kind: Kind,
        baseProviderID: String? = nil,
        reportedFinishID: String? = nil,
        reportedStamps: [String] = [],
        reportedSubtype: String? = nil,
        note: String? = nil,
        observed: ObservedIdentity? = nil,
        createdAt: Date = .now,
        catalogRevisionAtCreation: Int? = nil,
        knownVariantIDsAtCreation: [String] = []
    ) {
        self.reportID = reportID
        self.kind = kind
        self.baseProviderID = baseProviderID
        self.reportedFinishID = reportedFinishID
        self.reportedStamps = Array(Set(reportedStamps.map { $0.lowercased() })).sorted()
        self.reportedSubtype = reportedSubtype?.lowercased()
        self.note = note.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        self.observed = observed
        self.createdAt = createdAt
        self.catalogRevisionAtCreation = catalogRevisionAtCreation
        self.knownVariantIDsAtCreation = knownVariantIDsAtCreation.sorted()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        reportID = try container.decode(UUID.self, forKey: .reportID)
        kind = try container.decode(Kind.self, forKey: .kind)
        baseProviderID = try container.decodeIfPresent(String.self, forKey: .baseProviderID)
        reportedFinishID = try container.decodeIfPresent(String.self, forKey: .reportedFinishID)
        reportedStamps = try container.decodeIfPresent([String].self, forKey: .reportedStamps) ?? []
        reportedSubtype = try container.decodeIfPresent(String.self, forKey: .reportedSubtype)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        observed = try container.decodeIfPresent(ObservedIdentity.self, forKey: .observed)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        catalogRevisionAtCreation = try container.decodeIfPresent(Int.self, forKey: .catalogRevisionAtCreation)
        knownVariantIDsAtCreation = try container.decodeIfPresent(
            [String].self, forKey: .knownVariantIDsAtCreation
        ) ?? []
        lastEvaluatedCatalogRevision = try container.decodeIfPresent(
            Int.self, forKey: .lastEvaluatedCatalogRevision
        )
        reviewStateRaw = try container.decodeIfPresent(String.self, forKey: .reviewStateRaw)
            ?? ReviewState.waiting.rawValue
        reviewDismissedAt = try container.decodeIfPresent(Date.self, forKey: .reviewDismissedAt)
        linkedAt = try container.decodeIfPresent(Date.self, forKey: .linkedAt)
        unlinkedAt = try container.decodeIfPresent(Date.self, forKey: .unlinkedAt)
        preLinkIdentity = try container.decodeIfPresent(PreLinkIdentity.self, forKey: .preLinkIdentity)
        linkOperationIDs = try container.decodeIfPresent([UUID].self, forKey: .linkOperationIDs) ?? []
    }

    /// A report written by a newer build may carry meaning this build cannot
    /// see. It stays displayable and protected, but is never acted on.
    var isUnderstood: Bool { schemaVersion <= Self.currentSchemaVersion }

    /// `nil` for an unrecognized raw value written by a newer build.
    var reviewState: ReviewState? { ReviewState(rawValue: reviewStateRaw) }

    /// The catalog-shaped variant this report describes, when its fields are
    /// structured enough to name one. A note-only report names none.
    var reportedVariant: PhysicalVariant? {
        guard let reportedFinishID else { return nil }
        let base = PhysicalVariant.resolving(reportedFinishID)
        guard !reportedStamps.isEmpty else { return base }
        return PokemonCatalogStampVariant.make(
            base: base,
            stamps: reportedStamps,
            subtype: reportedSubtype
        )
    }

    var label: String {
        if let reportedVariant { return reportedVariant.label }
        return note ?? "Unlisted variant"
    }

    func encodedJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ json: String?) -> UnverifiedReport? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(UnverifiedReport.self, from: data)
    }
}

/// The ownership-key markers that make report protection fail closed.
///
/// `~` appears in no other collection-key grammar (`#` finish/treatment, `@`
/// print run, `:` graded/cert namespaces), so the marker can never be produced
/// or consumed by an existing key builder.
enum UnverifiedReportKey {
    static let unverifiedMarker = "~unverified="
    static let linkedMarker = "~report="
    static let providerPrefix = "unverified:"

    static func unverifiedKey(base: String, reportID: UUID) -> String {
        base + unverifiedMarker + reportID.uuidString.lowercased()
    }

    static func linkedKey(base: String, reportID: UUID) -> String {
        base + linkedMarker + reportID.uuidString.lowercased()
    }

    /// The synthetic ownership identity every unverified row uses, known card
    /// or not. Price identity derives from it, so no stored quote can match.
    static func providerID(reportID: UUID) -> String {
        providerPrefix + reportID.uuidString.lowercased()
    }

    static func isUnverified(_ collectionKey: String) -> Bool {
        collectionKey.contains(unverifiedMarker)
    }

    static func hasReport(_ collectionKey: String) -> Bool {
        collectionKey.contains(unverifiedMarker) || collectionKey.contains(linkedMarker)
    }

    /// The marker's suffix verbatim. Returned as text rather than a `UUID` so a
    /// damaged suffix still yields a distinct, unpriceable identity.
    static func reportToken(in collectionKey: String) -> String? {
        for marker in [unverifiedMarker, linkedMarker] {
            if let range = collectionKey.range(of: marker, options: .backwards) {
                return String(collectionKey[range.upperBound...])
            }
        }
        return nil
    }
}
