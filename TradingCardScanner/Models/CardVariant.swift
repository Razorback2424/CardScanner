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
struct PhysicalVariant: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let label: String

    init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// Stable representation of a TCGdex physical object distinguished by one or
/// more stamps. The source card remains the card identity; this value is the
/// variant layer persisted beside its finish. Stamps are sorted so API ordering
/// cannot create duplicate collection keys.
enum PokemonCatalogStampVariant {
    private static let prefix = "pokemonStamp|"

    static func make(
        base: PhysicalVariant,
        stamps: [String],
        subtype: String? = nil
    ) -> PhysicalVariant? {
        let normalized = Array(Set(stamps.map { $0.lowercased() })).sorted()
        guard !normalized.isEmpty else { return nil }
        let normalizedSubtype = subtype?.lowercased() ?? ""
        return PhysicalVariant(
            id: prefix + [base.id, normalized.joined(separator: ","), normalizedSubtype]
                .joined(separator: "|"),
            label: label(base: base, stamps: normalized, subtype: normalizedSubtype)
        )
    }

    static func decode(_ id: String) -> (base: PhysicalVariant, stamps: [String], subtype: String?)? {
        guard id.hasPrefix(prefix) else { return nil }
        let fields = String(id.dropFirst(prefix.count))
            .split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 3 else { return nil }
        let base = PhysicalVariant.resolving(String(fields[0]))
        let stamps = fields[1].split(separator: ",").map(String.init)
        guard !stamps.isEmpty else { return nil }
        let subtype = fields[2].isEmpty ? nil : String(fields[2])
        return (base, stamps, subtype)
    }

    static func resolving(_ id: String) -> PhysicalVariant? {
        guard let decoded = decode(id) else { return nil }
        return make(base: decoded.base, stamps: decoded.stamps, subtype: decoded.subtype)
    }

    static func isStamped(_ variant: PhysicalVariant) -> Bool {
        decode(variant.id) != nil
    }

    private static func label(base: PhysicalVariant, stamps: [String], subtype: String) -> String {
        let stampLabel = stamps.map(displayName).joined(separator: " + ")
        let subtypeLabel = subtype.isEmpty ? nil : displayName(subtype)
        return ([base.label, stampLabel] + [subtypeLabel].compactMap { $0 })
            .joined(separator: " · ")
    }

    private static func displayName(_ value: String) -> String {
        switch value {
        case "1st-edition": return "1st Edition"
        case "pre-release": return "Prerelease"
        case "pokemon-center": return "Pokémon Center"
        case "set-logo": return "Set Logo"
        case "w-promo": return "W Promo"
        case "trick-or-trade": return "Trick or Trade"
        case "player-rewards-program": return "Prize Pack"
        case "gamestop": return "GameStop"
        case "eb-games": return "EB Games"
        default:
            return value.split(separator: "-")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }
}

/// Verified stamped reprints whose mark is not encoded by the printed footer.
///
/// These are exact underlying TCGdex identities, not name/number guesses. The
/// marketplace product and its printing come from the corresponding TCGplayer
/// Trick or Trade groups. Keeping all four values together prevents a stamped
/// card from borrowing the price of its original expansion printing.
enum PokemonStampedReleaseCatalog {
    struct Entry: Equatable, Hashable, Sendable {
        let providerID: String
        let year: Int
        let tcgplayerProductID: String
        let printing: String

        var variant: PhysicalVariant {
            PhysicalVariant(
                id: "trickOrTrade\(year)\(printing.replacingOccurrences(of: " ", with: ""))",
                label: "Stamped (\(year))"
            )
        }
    }

    static let entries: [Entry] = [
        Entry(providerID: "swsh6-57", year: 2022, tcgplayerProductID: "283766", printing: "Holofoil"),
        Entry(providerID: "swsh9-056", year: 2022, tcgplayerProductID: "283785", printing: "Holofoil"),
        Entry(providerID: "swsh10-059", year: 2022, tcgplayerProductID: "283786", printing: "Holofoil"),
        Entry(providerID: "swsh9-062", year: 2022, tcgplayerProductID: "283787", printing: "Holofoil"),
        Entry(providerID: "swsh3-105", year: 2022, tcgplayerProductID: "283788", printing: "Holofoil"),
        Entry(providerID: "swsh2-33", year: 2022, tcgplayerProductID: "283790", printing: "Holofoil"),
        Entry(providerID: "swsh2-15", year: 2022, tcgplayerProductID: "283793", printing: "Holofoil"),
        Entry(providerID: "swsh7-77", year: 2022, tcgplayerProductID: "283795", printing: "Holofoil"),
        Entry(providerID: "swsh3-81", year: 2022, tcgplayerProductID: "283798", printing: "Holofoil"),
        Entry(providerID: "swsh6-73", year: 2022, tcgplayerProductID: "283801", printing: "Holofoil"),
        Entry(providerID: "swsh7-49", year: 2022, tcgplayerProductID: "283805", printing: "Normal"),
        Entry(providerID: "swsh5-69", year: 2022, tcgplayerProductID: "283807", printing: "Normal"),
        Entry(providerID: "swsh5-89", year: 2022, tcgplayerProductID: "283810", printing: "Normal"),
        Entry(providerID: "swsh6-55", year: 2022, tcgplayerProductID: "283811", printing: "Normal"),
        Entry(providerID: "swsh6-56", year: 2022, tcgplayerProductID: "283812", printing: "Normal"),
        Entry(providerID: "swsh3-102", year: 2022, tcgplayerProductID: "283815", printing: "Normal"),
        Entry(providerID: "swsh3-103", year: 2022, tcgplayerProductID: "283818", printing: "Normal"),
        Entry(providerID: "swsh5-93", year: 2022, tcgplayerProductID: "283819", printing: "Normal"),
        Entry(providerID: "swsh10-058", year: 2022, tcgplayerProductID: "283820", printing: "Normal"),
        Entry(providerID: "swsh9-060", year: 2022, tcgplayerProductID: "283821", printing: "Normal"),
        Entry(providerID: "swsh9-061", year: 2022, tcgplayerProductID: "283822", printing: "Normal"),
        Entry(providerID: "swsh2-31", year: 2022, tcgplayerProductID: "283824", printing: "Normal"),
        Entry(providerID: "swsh2-32", year: 2022, tcgplayerProductID: "283825", printing: "Normal"),
        Entry(providerID: "swsh8-16", year: 2022, tcgplayerProductID: "283826", printing: "Normal"),
        Entry(providerID: "swsh7-76", year: 2022, tcgplayerProductID: "283828", printing: "Normal"),
        Entry(providerID: "swsh10-103", year: 2022, tcgplayerProductID: "283831", printing: "Normal"),
        Entry(providerID: "swsh3.5-18", year: 2022, tcgplayerProductID: "283833", printing: "Normal"),
        Entry(providerID: "swsh6-72", year: 2022, tcgplayerProductID: "283836", printing: "Normal"),
        Entry(providerID: "swsh3-82", year: 2022, tcgplayerProductID: "283838", printing: "Normal"),
        Entry(providerID: "swsh3-83", year: 2022, tcgplayerProductID: "283839", printing: "Normal"),
        Entry(providerID: "swsh11-016", year: 2023, tcgplayerProductID: "515647", printing: "Normal"),
        Entry(providerID: "swsh11-017", year: 2023, tcgplayerProductID: "515648", printing: "Holofoil"),
        Entry(providerID: "swsh4-19", year: 2023, tcgplayerProductID: "515649", printing: "Normal"),
        Entry(providerID: "sv01-034", year: 2023, tcgplayerProductID: "515650", printing: "Holofoil"),
        Entry(providerID: "swsh11-024", year: 2023, tcgplayerProductID: "515651", printing: "Normal"),
        Entry(providerID: "swsh11-025", year: 2023, tcgplayerProductID: "515652", printing: "Normal"),
        Entry(providerID: "swsh11-026", year: 2023, tcgplayerProductID: "515653", printing: "Holofoil"),
        Entry(providerID: "sv02-062", year: 2023, tcgplayerProductID: "515654", printing: "Holofoil"),
        Entry(providerID: "swsh4-95", year: 2023, tcgplayerProductID: "515655", printing: "Normal"),
        Entry(providerID: "swsh2-102", year: 2023, tcgplayerProductID: "515656", printing: "Normal"),
        Entry(providerID: "swsh11-064", year: 2023, tcgplayerProductID: "515659", printing: "Normal"),
        Entry(providerID: "swsh11-065", year: 2023, tcgplayerProductID: "515660", printing: "Normal"),
        Entry(providerID: "swsh11-066", year: 2023, tcgplayerProductID: "515661", printing: "Holofoil"),
        Entry(providerID: "swsh4-69", year: 2023, tcgplayerProductID: "515662", printing: "Normal"),
        Entry(providerID: "swsh4-70", year: 2023, tcgplayerProductID: "515663", printing: "Normal"),
        Entry(providerID: "swsh4-71", year: 2023, tcgplayerProductID: "515664", printing: "Holofoil"),
        Entry(providerID: "sv01-087", year: 2023, tcgplayerProductID: "515665", printing: "Normal"),
        Entry(providerID: "swsh11-073", year: 2023, tcgplayerProductID: "515666", printing: "Normal"),
        Entry(providerID: "sv02-088", year: 2023, tcgplayerProductID: "515668", printing: "Normal"),
        Entry(providerID: "sv01-089", year: 2023, tcgplayerProductID: "515670", printing: "Normal"),
        Entry(providerID: "sv01-090", year: 2023, tcgplayerProductID: "515671", printing: "Normal"),
        Entry(providerID: "sv02-097", year: 2023, tcgplayerProductID: "515672", printing: "Holofoil"),
        Entry(providerID: "swsh7-80", year: 2023, tcgplayerProductID: "515673", printing: "Holofoil"),
        Entry(providerID: "swsh11-081", year: 2023, tcgplayerProductID: "515674", printing: "Holofoil"),
        Entry(providerID: "swsh1-89", year: 2023, tcgplayerProductID: "515675", printing: "Normal"),
        Entry(providerID: "swsh1-90", year: 2023, tcgplayerProductID: "515676", printing: "Normal"),
        Entry(providerID: "sv01-104", year: 2023, tcgplayerProductID: "515677", printing: "Normal"),
        Entry(providerID: "sv01-106", year: 2023, tcgplayerProductID: "515678", printing: "Holofoil"),
        Entry(providerID: "swsh12-103", year: 2023, tcgplayerProductID: "515679", printing: "Normal"),
        Entry(providerID: "sv02-131", year: 2023, tcgplayerProductID: "515680", printing: "Normal"),
        Entry(providerID: "sv02-012", year: 2024, tcgplayerProductID: "568512", printing: "Normal"),
        Entry(providerID: "sv02-050", year: 2024, tcgplayerProductID: "568513", printing: "Normal"),
        Entry(providerID: "sv03-130", year: 2024, tcgplayerProductID: "568704", printing: "Normal"),
        Entry(providerID: "sv03-131", year: 2024, tcgplayerProductID: "568705", printing: "Normal"),
        Entry(providerID: "sv03-133", year: 2024, tcgplayerProductID: "568748", printing: "Normal"),
        Entry(providerID: "sv03-136", year: 2024, tcgplayerProductID: "568826", printing: "Holofoil"),
        Entry(providerID: "sv04-023", year: 2024, tcgplayerProductID: "568941", printing: "Normal"),
        Entry(providerID: "sv04-077", year: 2024, tcgplayerProductID: "568968", printing: "Normal"),
        Entry(providerID: "sv04-078", year: 2024, tcgplayerProductID: "569041", printing: "Normal"),
        Entry(providerID: "sv04.5-018", year: 2024, tcgplayerProductID: "569132", printing: "Holofoil"),
        Entry(providerID: "sv04.5-037", year: 2024, tcgplayerProductID: "569227", printing: "Holofoil"),
        Entry(providerID: "sv04.5-042", year: 2024, tcgplayerProductID: "569228", printing: "Normal"),
        Entry(providerID: "sv04.5-043", year: 2024, tcgplayerProductID: "569323", printing: "Normal"),
        Entry(providerID: "sv04.5-057", year: 2024, tcgplayerProductID: "570271", printing: "Holofoil"),
        Entry(providerID: "sv05-077", year: 2024, tcgplayerProductID: "570272", printing: "Normal"),
        Entry(providerID: "sv05-078", year: 2024, tcgplayerProductID: "570273", printing: "Holofoil"),
        Entry(providerID: "sv05-102", year: 2024, tcgplayerProductID: "570320", printing: "Normal"),
        Entry(providerID: "sv05-103", year: 2024, tcgplayerProductID: "570361", printing: "Normal"),
        Entry(providerID: "sv05-139", year: 2024, tcgplayerProductID: "570362", printing: "Normal"),
        Entry(providerID: "sv06-012", year: 2024, tcgplayerProductID: "570363", printing: "Normal"),
        Entry(providerID: "sv06-013", year: 2024, tcgplayerProductID: "570364", printing: "Normal"),
        Entry(providerID: "sv06-021", year: 2024, tcgplayerProductID: "570365", printing: "Normal"),
        Entry(providerID: "sv06-022", year: 2024, tcgplayerProductID: "570462", printing: "Holofoil"),
        Entry(providerID: "sv06-024", year: 2024, tcgplayerProductID: "570463", printing: "Holofoil"),
        Entry(providerID: "sv06-036", year: 2024, tcgplayerProductID: "570563", printing: "Normal"),
        Entry(providerID: "sv06-037", year: 2024, tcgplayerProductID: "570564", printing: "Normal"),
        Entry(providerID: "sv06-038", year: 2024, tcgplayerProductID: "570565", printing: "Normal"),
        Entry(providerID: "sv06-095", year: 2024, tcgplayerProductID: "570567", printing: "Holofoil"),
        Entry(providerID: "sv06-096", year: 2024, tcgplayerProductID: "570568", printing: "Holofoil"),
        Entry(providerID: "sv06-111", year: 2024, tcgplayerProductID: "570569", printing: "Holofoil")
    ]

    static func entries(providerID: String) -> [Entry] {
        entries.filter { $0.providerID == providerID }
    }

    static func entry(variantID: String) -> Entry? {
        entries.first { $0.variant.id == variantID }
    }

    static func entry(providerID: String, variantID: String?) -> Entry? {
        guard let variantID else { return nil }
        return entries(providerID: providerID).first { $0.variant.id == variantID }
    }

    static func isStamped(variantID: String?) -> Bool {
        guard let variantID else { return false }
        return entry(variantID: variantID) != nil
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
            ?? PokemonStampedReleaseCatalog.entry(variantID: id)?.variant
            ?? PokemonCatalogStampVariant.resolving(id)
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
