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

    // Magic. These ids match Scryfall's `finishes` values exactly, so a printing's
    // possible finishes come straight from the catalog with no translation table
    // to drift out of date.
    static let nonfoil = PhysicalVariant(id: "nonfoil", label: "Nonfoil")
    static let foil = PhysicalVariant(id: "foil", label: "Foil")
    static let etched = PhysicalVariant(id: "etched", label: "Etched Foil")

    /// Every variant this app can name, for the Finish Lock menu and for turning a
    /// persisted id back into a label.
    static let known: [PhysicalVariant] = [
        .normal, .holo, .reverse, .firstEdition, .pokeBall, .masterBall,
        .nonfoil, .foil, .etched
    ]

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
        case .pokemon: return [.normal, .holo, .reverse, .pokeBall, .masterBall, .firstEdition]
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
        case PhysicalVariant.firstEdition.id: return 5
        default: return 6
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
    /// The catalog exposes no variant information for this printing at all. The
    /// record honestly stores "unknown" rather than inventing a plausible finish.
    case catalogSilent

    var label: String {
        switch self {
        case .uniqueInCatalog: return "Only variant printed"
        case .deterministicSetRule: return "Set rule"
        case .finishLock: return "Finish Lock"
        case .userConfirmed: return "You confirmed"
        case .catalogSilent: return "Not published"
        }
    }

    /// Whether a human supplied the fact. Used to decide what may be revisited
    /// automatically if a rule is later corrected.
    var isAutomatic: Bool {
        switch self {
        case .userConfirmed, .finishLock: return false
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
    /// then matched against a real catalog record. The only way this MVP ever
    /// establishes identity.
    case printedIdentifier

    var label: String {
        switch self {
        case .printedIdentifier: return "Printed identifier"
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
