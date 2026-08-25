import Foundation

/// One physically distinct object a collector can hold for a given printing.
///
/// Pokémon calls these variants or patterns; Magic separates frame *treatment*
/// — which is part of the printing identity and is already answered by the
/// collector number — from *finish*, which is a separate physical property. The
/// two games get one type because the resolution mechanism is identical:
///
///     exact printing -> possible physical variants -> trusted evidence -> resolved or one tap
///
/// `id` is persisted, so it must stay stable. `label` is presentation only.
struct PhysicalVariant: Identifiable, Hashable, Sendable {
    let id: String
    let label: String

    init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

extension PhysicalVariant {
    // Pokémon.
    static let normal = PhysicalVariant(id: "normal", label: "Normal")
    static let holo = PhysicalVariant(id: "holo", label: "Holo")
    static let reverse = PhysicalVariant(id: "reverse", label: "Reverse")
    static let firstEdition = PhysicalVariant(id: "firstEdition", label: "1st Edition")
    static let pokeBall = PhysicalVariant(id: "pokeBall", label: "Poké Ball")
    static let masterBall = PhysicalVariant(id: "masterBall", label: "Master Ball")
    static let duskBall = PhysicalVariant(id: "duskBall", label: "Dusk Ball")
    static let friendBall = PhysicalVariant(id: "friendBall", label: "Friend Ball")
    static let quickBall = PhysicalVariant(id: "quickBall", label: "Quick Ball")
    static let loveBall = PhysicalVariant(id: "loveBall", label: "Love Ball")

    // Magic. These ids match Scryfall's `finishes` values exactly, so a printing's
    // possible finishes come straight from the catalog with no translation table
    // to drift out of date.
    static let nonfoil = PhysicalVariant(id: "nonfoil", label: "Nonfoil")
    static let foil = PhysicalVariant(id: "foil", label: "Foil")
    static let etched = PhysicalVariant(id: "etched", label: "Etched Foil")

    /// Every variant this app can name, for the Finish Lock menu and for turning a
    /// persisted id back into a label.
    static let known: [PhysicalVariant] = [
        .normal, .holo, .reverse, .firstEdition,
        .pokeBall, .masterBall, .duskBall, .friendBall, .quickBall, .loveBall,
        .nonfoil, .foil, .etched
    ]

    /// TCGdex's `foil` vocabulary for parallel patterns, mapped onto this app's
    /// ids. The two differ only in casing, but the map is explicit so a new
    /// pattern name shows up here as a decision rather than as a silent
    /// lowercase id that no longer matches what the CSV importer produced.
    ///
    /// An unrecognised pattern is carried through under its own name. It is a
    /// real distinct object that this build simply cannot label yet, and it must
    /// never collapse onto plain reverse.
    static func pokemonFoilPattern(_ foil: String) -> PhysicalVariant {
        switch foil.lowercased().replacingOccurrences(of: "-", with: "") {
        case "pokeball": return .pokeBall
        case "masterball": return .masterBall
        case "duskball": return .duskBall
        case "friendball": return .friendBall
        case "quickball": return .quickBall
        case "loveball": return .loveBall
        default: return PhysicalVariant(id: foil, label: foil.capitalized)
        }
    }

    static func named(_ id: String) -> PhysicalVariant? {
        known.first { $0.id == id }
    }

    /// A catalog may name a finish this build has never heard of. Carry it through
    /// verbatim rather than dropping it: an unknown-but-real variant must still be
    /// offered to the user, and silently discarding one would let the resolver
    /// believe a multi-variant printing was unique.
    static func resolving(_ id: String) -> PhysicalVariant {
        named(id) ?? PhysicalVariant(id: id, label: id.capitalized)
    }

    /// Which variants a Finish Lock can be set to, per game. Ordered the way the
    /// menu should read.
    static func selectable(for game: CardGame) -> [PhysicalVariant] {
        switch game {
        case .pokemon:
            return [
                .normal, .holo, .reverse,
                .pokeBall, .masterBall, .duskBall, .friendBall, .quickBall, .loveBall,
                .firstEdition
            ]
        case .magic: return [.nonfoil, .foil, .etched]
        }
    }

    /// Ordering for the one-tap control: most likely first, because the first
    /// button is the one already under the user's thumb. This is a fixed prior,
    /// not a claim about the card in frame — the app is choosing button order,
    /// never the answer.
    var choicePriority: Int {
        switch id {
        case PhysicalVariant.reverse.id: return 0
        case PhysicalVariant.normal.id: return 1
        case PhysicalVariant.nonfoil.id: return 1
        case PhysicalVariant.holo.id: return 2
        case PhysicalVariant.foil.id: return 2
        case PhysicalVariant.pokeBall.id: return 3
        case PhysicalVariant.etched.id: return 3
        case PhysicalVariant.masterBall.id: return 4
        case PhysicalVariant.duskBall.id,
             PhysicalVariant.friendBall.id,
             PhysicalVariant.quickBall.id,
             PhysicalVariant.loveBall.id:
            return 5
        case PhysicalVariant.firstEdition.id: return 6
        default: return 7
        }
    }
}

/// Why the app believes the variant it recorded.
///
/// This is provenance, not decoration. If a deterministic rule is later found to
/// be incomplete, every record that leaned on that rule can be found and
/// reassessed without casting doubt on records the user confirmed by hand.
enum VariantResolution: String, Codable, Hashable, Sendable {
    /// The catalog says this printing physically exists in exactly one variant.
    case uniqueInCatalog
    /// A set-specific rule this app owns narrowed the possibilities to one.
    case deterministicSetRule
    /// The user's Finish Lock named a variant the catalog agrees is possible.
    case finishLock
    /// The user tapped it.
    case userConfirmed
    /// The finish came from an imported collection file.
    case imported
    /// The catalog exposes no variant information for this printing at all. The
    /// record honestly stores "unknown" rather than inventing a plausible finish.
    case catalogSilent

    var label: String {
        switch self {
        case .uniqueInCatalog: return "Only variant printed"
        case .deterministicSetRule: return "Set rule"
        case .finishLock: return "Finish Lock"
        case .userConfirmed: return "You confirmed"
        case .imported: return "Imported"
        case .catalogSilent: return "Not published"
        }
    }

    /// Whether the app may revisit the fact automatically if a rule changes.
    /// User choices and imported records stay as supplied.
    var isAutomatic: Bool {
        switch self {
        case .userConfirmed, .finishLock, .imported: return false
        case .uniqueInCatalog, .deterministicSetRule, .catalogSilent: return true
        }
    }
}

/// Why the app believes the card's identity. Deliberately separate from
/// `VariantResolution`: identity can be certain from printed identifiers at the
/// same moment the finish is a hand-made choice. Those are two different facts
/// and must not share one confidence field.
enum IdentityResolution: String, Codable, Hashable, Sendable {
    /// Printed set code and collector number, confirmed across OCR passes and
    /// then matched against a real catalog record.
    case printedIdentifier
    /// The user selected this exact printing from the remote card catalog.
    case catalogSelected
    /// The printing identity came from an imported collection file.
    case imported
    /// The user corrected identity metadata after reviewing collection history.
    case userCorrected

    var label: String {
        switch self {
        case .printedIdentifier: return "Printed identifier"
        case .catalogSelected: return "Selected from catalog"
        case .imported: return "Imported"
        case .userCorrected: return "You corrected"
        }
    }
}

/// A complete answer to "which physical object is this".
struct ResolvedVariant: Equatable, Hashable, Sendable {
    /// `nil` only when the catalog publishes no variant information.
    let variant: PhysicalVariant?
    let resolution: VariantResolution

    var label: String { variant?.label ?? "Unknown finish" }
}
