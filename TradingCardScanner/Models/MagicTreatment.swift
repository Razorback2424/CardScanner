import Foundation

/// A publisher-defined treatment applied to a Magic printing's physical surface.
///
/// This is deliberately a second axis beside `PhysicalVariant`. Scryfall can
/// say that a printing is both `foil` and `surgefoil`: `foil` answers how the
/// cardboard is finished, while `surgefoil` answers which treatment the printed
/// face carries. The provider's price remains safe when its object is this exact
/// printing; the axes must still stay separate in the app's identity model.
///
/// The axis is also independent of `MagicContentKind` and `CollectionItemKind`.
/// A treated token can be a token, a treated regular card can be raw or graded,
/// and a future sealed product can contain either without any of those facts
/// becoming unrepresentable.
enum MagicTreatment: Identifiable, Hashable, Sendable, Codable {
    case surgeFoil
    case galaxyFoil
    case silverFoil
    case rippleFoil
    case rainbowFoil
    case haloFoil
    case doubleRainbow
    case firstPlaceFoil
    case textured
    case stepAndCompleat
    case raisedFoil
    case fractureFoil
    case manaFoil
    case gilded
    case confettiFoil
    case oilSlick
    case invisibleInk
    case embossed
    case neonInk
    case chocoboTrackFoil
    case dazzleFoil
    case dragonScaleFoil
    case facetFoil
    case cosmicFoil
    case singularityFoil
    case gleamingGold
    case serialized
    case thick
    case plastic
    case metal
    case glossy
    case unclassified(String)

    /// The reviewed vocabulary in provider signal order. This is the single
    /// source of truth for modelled treatments; the bundled catalog generator
    /// reads the same order from `MagicTreatmentCatalog/vocabulary.json`.
    static let modelled: [MagicTreatment] = [
        .surgeFoil, .galaxyFoil, .silverFoil, .rippleFoil, .rainbowFoil,
        .haloFoil, .doubleRainbow, .firstPlaceFoil, .textured, .stepAndCompleat,
        .raisedFoil, .fractureFoil, .manaFoil, .gilded, .confettiFoil,
        .oilSlick, .invisibleInk, .embossed, .neonInk, .chocoboTrackFoil,
        .dazzleFoil, .dragonScaleFoil, .facetFoil,
        .cosmicFoil, .singularityFoil, .gleamingGold, .serialized, .thick,
        .plastic, .metal, .glossy
    ]

    /// Treatments that may be selected as a scanner lock. The menu stays
    /// intentionally narrow even though the model and catalog are exhaustive.
    static let lockable: [MagicTreatment] = [.surgeFoil, .neonInk]

    static func == (lhs: MagicTreatment, rhs: MagicTreatment) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var id: String {
        switch self {
        case .surgeFoil:
            return "surgefoil"
        case .galaxyFoil:
            return "galaxyfoil"
        case .silverFoil:
            return "silverfoil"
        case .rippleFoil:
            return "ripplefoil"
        case .rainbowFoil:
            return "rainbowfoil"
        case .haloFoil:
            return "halofoil"
        case .doubleRainbow:
            return "doublerainbow"
        case .firstPlaceFoil:
            return "firstplacefoil"
        case .textured:
            return "textured"
        case .stepAndCompleat:
            return "stepandcompleat"
        case .raisedFoil:
            return "raisedfoil"
        case .fractureFoil:
            return "fracturefoil"
        case .manaFoil:
            return "manafoil"
        case .gilded:
            return "gilded"
        case .confettiFoil:
            return "confettifoil"
        case .oilSlick:
            return "oilslick"
        case .invisibleInk:
            return "invisibleink"
        case .embossed:
            return "embossed"
        case .neonInk:
            return "neonink"
        case .chocoboTrackFoil:
            return "chocobotrackfoil"
        case .dazzleFoil:
            return "dazzlefoil"
        case .dragonScaleFoil:
            return "dragonscalefoil"
        case .facetFoil:
            return "facetfoil"
        case .cosmicFoil:
            return "cosmicfoil"
        case .singularityFoil:
            return "singularityfoil"
        case .gleamingGold:
            return "gleaminggold"
        case .serialized:
            return "serialized"
        case .thick:
            return "thick"
        case .plastic:
            return "plastic"
        case .metal:
            return "metal"
        case .glossy:
            return "glossy"
        case let .unclassified(rawValue):
            return rawValue.lowercased()
        }
    }

    /// The provider signal this treatment is derived from.
    var providerSignal: String {
        switch self {
        case let .unclassified(rawValue): return rawValue
        default: return id
        }
    }

    /// The finishes on which this treatment is published. An empty set means
    /// the treatment is a product/provenance signal rather than a physical
    /// surface relationship. This is a relationship, not a replacement for
    /// the separate `PhysicalVariant` finish axis.
    var requiredFinishes: Set<PhysicalVariant> {
        switch self {
        case .serialized, .thick, .plastic, .metal, .glossy, .unclassified:
            return []
        case .rippleFoil:
            return [.foil, .etched]
        case .surgeFoil, .galaxyFoil, .silverFoil, .rainbowFoil, .haloFoil,
             .doubleRainbow, .firstPlaceFoil, .textured, .stepAndCompleat,
             .raisedFoil, .fractureFoil, .manaFoil, .gilded, .confettiFoil,
             .oilSlick, .invisibleInk, .embossed, .neonInk, .chocoboTrackFoil,
             .dazzleFoil, .dragonScaleFoil, .facetFoil, .cosmicFoil,
             .singularityFoil, .gleamingGold:
            return [.foil]
        }
    }

    var sheenFamily: SheenFamily {
        self == .neonInk ? .neon : .dispersed
    }

    var label: String {
        switch self {
        case .surgeFoil:
            return "Surge Foil"
        case .galaxyFoil:
            return "Galaxy Foil"
        case .silverFoil:
            return "Silver Foil"
        case .rippleFoil:
            return "Ripple Foil"
        case .rainbowFoil:
            return "Rainbow Foil"
        case .haloFoil:
            return "Halo Foil"
        case .doubleRainbow:
            return "Double Rainbow"
        case .firstPlaceFoil:
            return "First Place Foil"
        case .textured:
            return "Textured"
        case .stepAndCompleat:
            return "Step and Compleat"
        case .raisedFoil:
            return "Raised Foil"
        case .fractureFoil:
            return "Fracture Foil"
        case .manaFoil:
            return "Mana Foil"
        case .gilded:
            return "Gilded"
        case .confettiFoil:
            return "Confetti Foil"
        case .oilSlick:
            return "Oil Slick"
        case .invisibleInk:
            return "Invisible Ink"
        case .embossed:
            return "Embossed"
        case .neonInk:
            return "Neon Ink"
        case .chocoboTrackFoil:
            return "Chocobo Track Foil"
        case .dazzleFoil:
            return "Dazzle Foil"
        case .dragonScaleFoil:
            return "Dragon Scale Foil"
        case .facetFoil:
            return "Facet Foil"
        case .cosmicFoil:
            return "Cosmic Foil"
        case .singularityFoil:
            return "Singularity Foil"
        case .gleamingGold:
            return "Gleaming Gold"
        case .serialized:
            return "Serialized"
        case .thick:
            return "Thick"
        case .plastic:
            return "Plastic"
        case .metal:
            return "Metal"
        case .glossy:
            return "Glossy"
        case let .unclassified(rawValue):
            return "Unclassified · \(rawValue)"
        }
    }

    /// Parses the stable persisted/catalog id. Unknown future treatments are
    /// intentionally not guessed into a known case; they remain available as
    /// unclassified evidence until the app has a reviewed model for them.
    init?(id: String) {
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        switch normalized {
        case "surgefoil":
            self = .surgeFoil
        case "galaxyfoil":
            self = .galaxyFoil
        case "silverfoil":
            self = .silverFoil
        case "ripplefoil":
            self = .rippleFoil
        case "rainbowfoil":
            self = .rainbowFoil
        case "halofoil":
            self = .haloFoil
        case "doublerainbow":
            self = .doubleRainbow
        case "firstplacefoil":
            self = .firstPlaceFoil
        case "textured":
            self = .textured
        case "stepandcompleat":
            self = .stepAndCompleat
        case "raisedfoil":
            self = .raisedFoil
        case "fracturefoil":
            self = .fractureFoil
        case "manafoil":
            self = .manaFoil
        case "gilded":
            self = .gilded
        case "confettifoil":
            self = .confettiFoil
        case "oilslick":
            self = .oilSlick
        case "invisibleink":
            self = .invisibleInk
        case "embossed":
            self = .embossed
        case "neonink":
            self = .neonInk
        case "chocobotrackfoil":
            self = .chocoboTrackFoil
        case "dazzlefoil":
            self = .dazzleFoil
        case "dragonscalefoil":
            self = .dragonScaleFoil
        case "facetfoil":
            self = .facetFoil
        case "cosmicfoil":
            self = .cosmicFoil
        case "singularityfoil":
            self = .singularityFoil
        case "gleaminggold":
            self = .gleamingGold
        case "serialized":
            self = .serialized
        case "thick":
            self = .thick
        case "plastic":
            self = .plastic
        case "metal":
            self = .metal
        case "glossy":
            self = .glossy
        default:
            self = .unclassified(id.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let id = try container.decode(String.self)
        guard let treatment = MagicTreatment(id: id) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid empty Magic treatment id"
            )
        }
        self = treatment
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(providerSignal)
    }
}

enum SheenFamily: Sendable, Equatable {
    case neon
    case dispersed
}

/// Treatment evidence attached to an exact Magic printing.
///
/// This value deliberately contains no OCR confidence and no visual guess. It
/// is only the result of exact provider metadata plus exact, reviewed enrichment
/// from the bundled catalog artifact. A future resolver can use it as evidence
/// without making it part of the finish enum or the content/ownership axes.
struct MagicTreatmentEvidence: Equatable, Hashable, Sendable {
    let treatments: [MagicTreatment]
    /// Qualifiers are keyed by treatment id so future publisher distinctions
    /// (color, serial, stamp type, and so on) do not add treatment-specific
    /// persisted fields.
    let qualifiers: [String: String]

    var isEmpty: Bool { treatments.isEmpty }

    /// Presentation labels keep the treatment axis visible without pretending
    /// that a qualifier is another finish. A reviewed qualifier is appended to
    /// its treatment, so a color or stamp type cannot be mistaken for a
    /// separate physical-variant choice.
    var displayLabels: [String] {
        treatments.map { treatmentLabel(for: $0) }
    }

    var displayLabel: String? {
        displayLabels.isEmpty ? nil : displayLabels.joined(separator: " · ")
    }

    /// Treatments are a function of the exact printing and the finish the
    /// person actually owns. A foil-only treatment is not present on the
    /// nonfoil copy of a dual-finish printing. Unknown treatments have no
    /// known finish relationship, so they remain visible for any selected
    /// finish and are never guessed into a known one.
    func applicableTreatments(for finish: PhysicalVariant?) -> [MagicTreatment] {
        treatments.filter { treatment in
            guard !treatment.requiredFinishes.isEmpty else { return true }
            guard let finish else { return false }
            return treatment.requiredFinishes.contains { requiredFinish in
                finish.id.caseInsensitiveCompare(requiredFinish.id) == .orderedSame
            }
        }
    }

    /// A known treatment can make the physical finish redundant in compact
    /// presentation. Unknown treatments deliberately return false: retaining
    /// both facts is safer than guessing a future treatment's finish. A
    /// multi-finish treatment also keeps the selected finish visible because
    /// its signal alone cannot identify which physical surface is owned.
    func impliesFinish(_ finish: PhysicalVariant?) -> Bool {
        guard let finish else { return false }
        return treatments.contains { treatment in
            guard treatment.requiredFinishes.count == 1,
                  let requiredFinish = treatment.requiredFinishes.first else {
                return false
            }
            return finish.id.caseInsensitiveCompare(requiredFinish.id) == .orderedSame
        }
    }

    func displayLabel(with finish: PhysicalVariant?) -> String? {
        let compatibleLabels = applicableTreatments(for: finish)
            .map { treatmentLabel(for: $0) }

        guard !compatibleLabels.isEmpty else {
            return finish?.label
        }
        let finishLabel = impliesFinish(finish) ? nil : finish?.label
        return [finishLabel, compatibleLabels.joined(separator: " · ")]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    init(
        treatments: [MagicTreatment],
        qualifiers: [String: String] = [:]
    ) {
        self.treatments = treatments
        self.qualifiers = MagicTreatmentKeyCodec.storedQualifiers(from: qualifiers)
    }

    func qualifier(for treatment: MagicTreatment) -> String? {
        qualifiers[treatment.id]
    }

    private func treatmentLabel(for treatment: MagicTreatment) -> String {
        guard let qualifier = qualifier(for: treatment) else {
            return treatment.label
        }
        return "\(treatment.label) · \(qualifier.capitalized)"
    }
}

/// Encodes the treatment axis without changing either identity family's
/// existing base format.
///
/// Collection keys use `#` segments because raw keys already use `#finish`.
/// Price, reference-quote, and vendor-identity keys use the independent
/// colon-delimited format owned by `PriceRecord.key`. The suffixes are kept
/// separate deliberately: making a collection key look like a price key would
/// orphan existing rows, while using the collection suffix in a price key
/// would make every stored price unreadable.
enum MagicTreatmentKeyCodec {
    private static let priceTreatmentMarker = ":treatment="

    /// Canonical, stable ids used in a key. Sorting makes a future co-occurring
    /// treatment set independent of provider array order.
    static func canonicalIDs(from treatments: [MagicTreatment]) -> [String] {
        Array(Set(treatments.map(\.id).filter { !$0.isEmpty })).sorted()
    }

    /// The persisted form keeps an unknown treatment's original spelling for
    /// display/forward compatibility, while deduplicating by its normalized id.
    static func storedIDs(from treatments: [MagicTreatment]) -> [String] {
        var seen = Set<String>()
        return treatments.compactMap { treatment in
            let raw = treatment.providerSignal
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let normalized = MagicTreatment(id: raw),
                  seen.insert(normalized.id).inserted else {
                return nil
            }
            return raw
        }
    }

    /// Normalizes ids read from a migrated/imported row without throwing away
    /// an unknown future value.
    static func storedIDs(from rawIDs: [String]) -> [String] {
        var seen = Set<String>()
        return rawIDs.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let treatment = MagicTreatment(id: trimmed),
                  seen.insert(treatment.id).inserted else {
                return nil
            }
            return treatment.providerSignal
        }
    }

    /// Qualifiers use treatment ids as their map keys. Normalize those keys the
    /// same way as the treatment identity, but keep the publisher's value (for
    /// example `Red` versus `Blue`) intact for display and CSV round-tripping.
    static func storedQualifiers(from qualifiers: [String: String]) -> [String: String] {
        var normalized: [String: String] = [:]
        for (rawKey, rawValue) in qualifiers {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let treatment = MagicTreatment(id: rawKey), !value.isEmpty else { continue }
            normalized[treatment.id] = value
        }
        return normalized
    }

    static func encodeQualifiers(_ qualifiers: [String: String]) -> String? {
        let normalized = storedQualifiers(from: qualifiers)
        guard !normalized.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(normalized) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func decodeQualifiers(_ encoded: String?) -> [String: String] {
        guard let encoded,
              let data = encoded.data(using: .utf8),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return storedQualifiers(from: values)
    }

    static func appendCollectionSuffix(
        to base: String,
        treatments: [MagicTreatment]
    ) -> String {
        appendCollectionSuffix(to: base, ids: canonicalIDs(from: treatments))
    }

    static func appendCollectionSuffix(
        to base: String,
        rawIDs: [String]
    ) -> String {
        appendCollectionSuffix(to: base, ids: canonicalIDs(from: rawIDs))
    }

    static func appendPriceSuffix(
        to base: String,
        treatments: [MagicTreatment]
    ) -> String {
        appendPriceSuffix(to: base, ids: canonicalIDs(from: treatments))
    }

    static func appendPriceSuffix(
        to base: String,
        rawIDs: [String]
    ) -> String {
        appendPriceSuffix(to: base, ids: canonicalIDs(from: rawIDs))
    }

    /// Price, quote, and vendor-identity keys use this literal marker before
    /// the encoded treatment value. Treat the vendor-native portion before the
    /// marker as opaque: it may itself contain additional colon segments.
    static func containsPriceTreatmentSuffix(in key: String) -> Bool {
        key.range(of: priceTreatmentMarker, options: [.caseInsensitive]) != nil
    }

    /// Reads treatment ids from either a price, reference-quote, or vendor
    /// identity key. The portion before the first marker is intentionally
    /// opaque: a vendor-native price storage id may itself contain colons
    /// (`justtcg:<version>:<id>`), so splitting the whole key into positional
    /// fields would misread old rows.
    static func priceTreatmentIDs(from key: String) -> [String] {
        var rawIDs: [String] = []
        var searchStart = key.startIndex

        while let marker = key.range(
            of: priceTreatmentMarker,
            options: [.caseInsensitive],
            range: searchStart..<key.endIndex
        ) {
            let valueStart = marker.upperBound
            let nextMarker = key.range(
                of: priceTreatmentMarker,
                options: [.caseInsensitive],
                range: valueStart..<key.endIndex
            )
            let valueEnd = nextMarker?.lowerBound ?? key.endIndex
            let encodedValue = String(key[valueStart..<valueEnd])
            guard !encodedValue.isEmpty else { return [] }
            let decodedValue = encodedValue.removingPercentEncoding ?? encodedValue
            guard let treatment = MagicTreatment(id: decodedValue) else { return [] }
            rawIDs.append(treatment.providerSignal)

            guard let nextMarker else { break }
            searchStart = nextMarker.lowerBound
        }

        return storedIDs(from: rawIDs)
    }

    /// Returns the treatment-free price identity without interpreting any of
    /// its colon-delimited prefix. This is used by migration/audit code when it
    /// needs to compare old and new price forms without orphaning a vendor key.
    static func priceBaseKey(_ key: String) -> String {
        guard let marker = key.range(of: priceTreatmentMarker, options: [.caseInsensitive]) else {
            return key
        }
        return String(key[..<marker.lowerBound])
    }

    /// Builds the raw collection identity while preserving the bare key when
    /// no finish is known. A treatment cannot be keyed without a selected
    /// finish because the known treatment relationship is finish-dependent.
    static func finishQualifiedCollectionKey(
        base: String,
        game: CardGame,
        finish: PhysicalVariant?,
        treatments: [MagicTreatment] = [],
        rawTreatmentIDs: [String] = []
    ) -> String {
        guard let finish else { return base }
        let finishKey = "\(base)#\(finish.id)"
        guard game == .magic else { return finishKey }
        if !treatments.isEmpty {
            return appendCollectionSuffix(to: finishKey, treatments: treatments)
        }
        return appendCollectionSuffix(to: finishKey, rawIDs: rawTreatmentIDs)
    }

    /// The pre-treatment collection identity for a canonical key.
    ///
    /// Treatment identity was added after raw, graded, and sealed collection
    /// namespaces already existed. Read-through must therefore remove only the
    /// `#treatment=` segments and preserve the family's original base, finish,
    /// certificate, and any legacy Pokémon print-run suffix. Returning a list
    /// keeps this API ready for another superseded collection shape without
    /// making callers know which namespace they are looking at.
    static func legacyCollectionKeys(for canonicalKey: String) -> [String] {
        let components = canonicalKey
            .split(separator: "#", omittingEmptySubsequences: false)
            .map(String.init)
        let treatmentPrefix = "treatment="
        guard components.contains(where: {
            $0.lowercased().hasPrefix(treatmentPrefix)
        }) else {
            return []
        }

        var legacyComponents: [String] = []
        var trailingSuffix = ""
        for component in components {
            guard component.lowercased().hasPrefix(treatmentPrefix) else {
                legacyComponents.append(component)
                continue
            }

            // CollectionStore may append the independent Pokémon print-run
            // marker after the full key. Treatment values themselves are
            // percent-encoded, so a literal `@` here is that legacy suffix.
            if let suffixIndex = component.firstIndex(of: "@") {
                trailingSuffix = String(component[suffixIndex...])
            }
        }

        let legacy = legacyComponents.joined(separator: "#") + trailingSuffix
        return legacy == canonicalKey ? [] : [legacy]
    }

    /// Decodes treatment ids from a canonical collection key when a caller is
    /// healing a persisted row without a live provider response. New writes
    /// should pass their raw ids explicitly so unknown spelling remains
    /// lossless; this fallback recovers the normalized key identity.
    static func collectionTreatmentIDs(from canonicalKey: String) -> [String] {
        let treatmentPrefix = "treatment="
        let rawIDs = canonicalKey
            .split(separator: "#", omittingEmptySubsequences: false)
            .compactMap { component -> String? in
                let component = String(component)
                guard component.lowercased().hasPrefix(treatmentPrefix) else {
                    return nil
                }
                var encoded = String(component.dropFirst(treatmentPrefix.count))
                if let suffixIndex = encoded.firstIndex(of: "@") {
                    encoded = String(encoded[..<suffixIndex])
                }
                return encoded.removingPercentEncoding ?? encoded
            }
        return storedIDs(from: rawIDs)
    }

    static func canonicalIDs(from rawIDs: [String]) -> [String] {
        Array(
            Set(
                rawIDs.compactMap { raw in
                    MagicTreatment(id: raw.trimmingCharacters(in: .whitespacesAndNewlines))?.id
                }
            )
        )
        .filter { !$0.isEmpty }
        .sorted()
    }

    private static func appendCollectionSuffix(to base: String, ids: [String]) -> String {
        base + ids.map { "#treatment=\(encode($0))" }.joined()
    }

    private static func appendPriceSuffix(to base: String, ids: [String]) -> String {
        base + ids.map { ":treatment=\(encode($0))" }.joined()
    }

    private static func encode(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~")
        )
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// The two price-key generations share one opaque base plus zero or more
/// treatment markers. The base may contain additional colons when it embeds a
/// vendor-native id such as `justtcg:v2:<variant>`, so callers must not derive
/// this value by counting colon-separated fields.
struct MagicPriceKeyParts: Equatable, Sendable {
    let originalKey: String
    let baseKey: String
    let treatmentIDs: [String]

    var isTreatmentQualified: Bool { !treatmentIDs.isEmpty }
}

extension MagicTreatmentKeyCodec {
    /// Parses both legacy and treatment-qualified price/reference/vendor keys.
    /// An invalid marker is rejected rather than being mistaken for a generic
    /// price identity; the unmarked legacy form remains a valid empty axis.
    static func priceKeyParts(from key: String) -> MagicPriceKeyParts? {
        guard containsPriceTreatmentSuffix(in: key) else {
            return MagicPriceKeyParts(
                originalKey: key,
                baseKey: key,
                treatmentIDs: []
            )
        }
        let treatmentIDs = priceTreatmentIDs(from: key)
        guard !treatmentIDs.isEmpty else { return nil }
        return MagicPriceKeyParts(
            originalKey: key,
            baseKey: priceBaseKey(key),
            treatmentIDs: treatmentIDs
        )
    }
}

/// The persisted collection-key families that existed before and after Magic
/// treatment identity was added. A treatment is a suffix in each family; it is
/// not a positional field in the graded/sealed namespaces.
enum MagicCollectionKeyShape: String, Equatable, Sendable {
    case rawLegacy
    case rawFinish
    case rawFinishTreatment
    /// A CSV/provider import can use an opaque id containing `:`. Scryfall
    /// printing ids do not, so this form is valid collection identity but is not
    /// eligible for exact Scryfall enrichment.
    case rawImported
    case graded
    case gradedCertified
    case sealed
    /// CSV imports without a vendor UUID use a hash-delimited grader/grade
    /// fragment. These are not exact Scryfall identities, but they are valid
    /// persisted collection rows and must not make the migration fail closed.
    case gradedImported
    /// CSV imports without a vendor product/variant UUID use a compact product
    /// key. It is likewise a valid non-enrichable identity.
    case sealedImported
}

/// A validated decomposition of one Magic collection key. Only standard raw and
/// graded keys carry an exact Scryfall printing id. Imported/opaque and sealed
/// keys intentionally expose no such id: their identifiers are not proven card
/// printings.
struct MagicCollectionKeyParts: Equatable, Sendable {
    let originalKey: String
    let baseKey: String
    let shape: MagicCollectionKeyShape
    let exactPrintingID: String?
    let finishID: String?
    let treatmentIDs: [String]

    var isTreatmentQualified: Bool { !treatmentIDs.isEmpty }
    var isCertified: Bool { shape == .gradedCertified }
}

extension MagicTreatmentKeyCodec {
    /// Validates and classifies all persisted Magic collection forms without
    /// guessing from set code, collector number, or row metadata. Collection
    /// suffixes are `#` segments; their treatment values are percent-encoded.
    static func collectionKeyParts(from key: String) -> MagicCollectionKeyParts? {
        let components = key
            .split(separator: "#", omittingEmptySubsequences: false)
            .map(String.init)
        guard let root = components.first, !root.isEmpty else { return nil }

        var baseComponents: [String] = [root]
        var rawTreatmentIDs: [String] = []
        var sawTreatmentMarker = false

        for component in components.dropFirst() {
            let prefix = "treatment="
            if component.lowercased().hasPrefix(prefix) {
                sawTreatmentMarker = true
                var encoded = String(component.dropFirst(prefix.count))
                // The old Pokémon print-run suffix may follow a collection
                // treatment component. It is not valid for Magic, but keeping
                // the parser compatible with the shared codec avoids treating
                // that suffix as part of an unknown treatment value.
                if let suffixIndex = encoded.firstIndex(of: "@") {
                    encoded = String(encoded[..<suffixIndex])
                }
                guard !encoded.isEmpty else { return nil }
                let decoded = encoded.removingPercentEncoding ?? encoded
                guard let treatment = MagicTreatment(id: decoded) else { return nil }
                rawTreatmentIDs.append(treatment.providerSignal)
            } else {
                baseComponents.append(component)
            }
        }

        let treatmentIDs = storedIDs(from: rawTreatmentIDs)
        guard !sawTreatmentMarker || !treatmentIDs.isEmpty else { return nil }
        let baseKey = baseComponents.joined(separator: "#")

        let rawPrefix = "magic:"
        if root.lowercased().hasPrefix(rawPrefix) {
            let printingID = String(root.dropFirst(rawPrefix.count))
            guard !printingID.isEmpty, baseComponents.count <= 2 else {
                return nil
            }
            let finishID = baseComponents.dropFirst().first
            if let finishID {
                guard !finishID.isEmpty, !finishID.contains("@") else { return nil }
            } else {
                guard treatmentIDs.isEmpty else { return nil }
            }
            let shape: MagicCollectionKeyShape
            if printingID.contains(":") {
                shape = .rawImported
            } else if finishID != nil {
                shape = treatmentIDs.isEmpty ? .rawFinish : .rawFinishTreatment
            } else {
                shape = .rawLegacy
            }
            return MagicCollectionKeyParts(
                originalKey: key,
                baseKey: baseKey,
                shape: shape,
                // Imported/provider-native ids may contain colons. They are
                // valid collection identities, but a colon is not part of a
                // Scryfall printing id, so never send those opaque ids to the
                // exact-printing enrichment path.
                exactPrintingID: shape == .rawImported ? nil : printingID,
                finishID: finishID,
                treatmentIDs: treatmentIDs
            )
        }

        let gradedPrefix = "graded:magic:"
        if root.lowercased().hasPrefix(gradedPrefix) {
            if baseComponents.count == 2 {
                let importedPrintingID = String(root.dropFirst(gradedPrefix.count))
                guard !importedPrintingID.isEmpty,
                      !baseComponents[1].isEmpty else { return nil }
                return MagicCollectionKeyParts(
                    originalKey: key,
                    baseKey: baseKey,
                    shape: .gradedImported,
                    exactPrintingID: nil,
                    finishID: nil,
                    treatmentIDs: treatmentIDs
                )
            }
            guard baseComponents.count == 1 else { return nil }
            let fields = root.split(separator: ":", omittingEmptySubsequences: false)
            let importedPrintingID = String(root.dropFirst(gradedPrefix.count))
            guard !importedPrintingID.isEmpty else { return nil }
            guard fields.count == 4 || fields.count == 6 else {
                return MagicCollectionKeyParts(
                    originalKey: key,
                    baseKey: baseKey,
                    shape: .gradedImported,
                    exactPrintingID: nil,
                    finishID: nil,
                    treatmentIDs: treatmentIDs
                )
            }
            guard String(fields[0]).caseInsensitiveCompare("graded") == .orderedSame,
                  String(fields[1]).caseInsensitiveCompare("magic") == .orderedSame,
                  !fields[2].isEmpty,
                  !fields[3].isEmpty else {
                return nil
            }
            let shape: MagicCollectionKeyShape
            if fields.count == 4 {
                shape = .graded
            } else {
                guard String(fields[4]).caseInsensitiveCompare("cert") == .orderedSame,
                      !fields[5].isEmpty else { return nil }
                shape = .gradedCertified
            }
            return MagicCollectionKeyParts(
                originalKey: key,
                baseKey: baseKey,
                shape: shape,
                exactPrintingID: String(fields[2]),
                finishID: nil,
                treatmentIDs: treatmentIDs
            )
        }

        let sealedPrefix = "sealed:magic:"
        if root.lowercased().hasPrefix(sealedPrefix) {
            let fields = root.split(separator: ":", omittingEmptySubsequences: false)
            if fields.count != 4 {
                guard !String(root.dropFirst(sealedPrefix.count)).isEmpty else { return nil }
                return MagicCollectionKeyParts(
                    originalKey: key,
                    baseKey: baseKey,
                    shape: .sealedImported,
                    exactPrintingID: nil,
                    finishID: nil,
                    treatmentIDs: treatmentIDs
                )
            }
            guard baseComponents.count == 1 else { return nil }
            guard fields.count == 4,
                  String(fields[0]).caseInsensitiveCompare("sealed") == .orderedSame,
                  String(fields[1]).caseInsensitiveCompare("magic") == .orderedSame,
                  !fields[2].isEmpty,
                  !fields[3].isEmpty else {
                return nil
            }
            return MagicCollectionKeyParts(
                originalKey: key,
                baseKey: baseKey,
                shape: .sealed,
                exactPrintingID: nil,
                finishID: nil,
                treatmentIDs: treatmentIDs
            )
        }

        return nil
    }
}

/// A read-only integrity finding for provider data that contradicts a known
/// treatment relationship. The treatment remains visible for review; this
/// value only reports that its required finish was not published on the exact
/// printing.
struct MagicTreatmentDiagnostic: Equatable, Hashable, Sendable, Identifiable {
    let treatment: MagicTreatment
    let requiredFinishes: Set<PhysicalVariant>
    let publishedFinishes: [PhysicalVariant]

    var id: String {
        let finishes = requiredFinishes.map(\.id).sorted().joined(separator: ",")
        return "\(treatment.id):\(finishes)"
    }

    var title: String {
        "\(treatment.label) / \(requiredFinishLabel) mismatch"
    }

    var detail: String {
        let published = publishedFinishes.map(\.label).joined(separator: " · ")
        return "This printing is published as \(published), but \(treatment.label) requires \(requiredFinishLabel)."
    }

    private var requiredFinishLabel: String {
        requiredFinishes
            .sorted { $0.choicePriority < $1.choicePriority }
            .map(\.label)
            .joined(separator: " or ")
    }
}
