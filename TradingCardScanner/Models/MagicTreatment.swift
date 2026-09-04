import Foundation

/// A publisher-defined treatment applied to a Magic printing's physical surface.
///
/// This is deliberately a second axis beside `PhysicalVariant`. Scryfall can
/// say that a printing is both `foil` and `surgefoil`: `foil` answers how the
/// cardboard is finished, while `surgefoil` answers which treatment the printed
/// face carries. Treating the latter as another finish would make the provider's
/// `usd_foil` value look like a price for every foil treatment.
///
/// The axis is also independent of `MagicContentKind` and `CollectionItemKind`.
/// A treated token can be a token, a treated regular card can be raw or graded,
/// and a future sealed product can contain either without any of those facts
/// becoming unrepresentable.
enum MagicTreatment: Identifiable, Hashable, Sendable, Codable {
    case surgeFoil
    case neonInk
    case unclassified(String)

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
        case .neonInk:
            return "neonink"
        case let .unclassified(rawValue):
            return rawValue.lowercased()
        }
    }

    /// The provider signal this treatment is derived from.
    var providerSignal: String {
        switch self {
        case .surgeFoil: return "surgefoil"
        case .neonInk: return "neonink"
        case let .unclassified(rawValue): return rawValue
        }
    }

    /// Both treatments in this slice are printed on foil cards. This is a
    /// relationship, not a replacement for the separate `.foil` finish.
    var requiredFinish: PhysicalVariant? {
        switch self {
        case .surgeFoil, .neonInk:
            return .foil
        case .unclassified:
            return nil
        }
    }

    var label: String {
        switch self {
        case .surgeFoil:
            return "Surge Foil"
        case .neonInk:
            return "Neon Ink"
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
        case "neonink":
            self = .neonInk
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
        switch self {
        case .surgeFoil, .neonInk:
            try container.encode(id)
        case let .unclassified(rawValue):
            try container.encode(rawValue)
        }
    }
}

/// Treatment evidence attached to an exact Magic printing.
///
/// This value deliberately contains no OCR confidence and no visual guess. It
/// is only the result of exact provider metadata plus exact, reviewed catalog
/// enrichment. A future resolver can use it as evidence without making it part
/// of the finish enum or the content/ownership axes.
struct MagicTreatmentEvidence: Equatable, Hashable, Sendable {
    let treatments: [MagicTreatment]
    /// Qualifiers are keyed by treatment id so future publisher distinctions
    /// (color, serial, stamp type, and so on) do not add treatment-specific
    /// persisted fields.
    let qualifiers: [String: String]

    var isEmpty: Bool { treatments.isEmpty }

    init(
        treatments: [MagicTreatment],
        qualifiers: [String: String] = [:]
    ) {
        self.treatments = treatments
        self.qualifiers = qualifiers
    }

    func qualifier(for treatment: MagicTreatment) -> String? {
        qualifiers[treatment.id]
    }
}
