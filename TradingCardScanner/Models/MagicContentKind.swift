import Foundation

/// What kind of Magic object a printed footer describes.
///
/// Deliberately *not* `CollectionItemKind`. That axis is how a thing is owned —
/// raw, graded, sealed — and this one is what the thing is. A graded token is
/// both a `gradedCard` and a `token`, so collapsing the two would make one of
/// them unrepresentable.
///
/// This exists because the printed marker is semantic. Magic prints
///
///     T 0017
///     MSH • EN
///
/// on a token, and the `T` is the only thing distinguishing it from the ordinary
/// card at `MSH 17`. Those are different cards: `MSH 17` is Invisible Woman and
/// `TMSH 17` is a Clue token. Dropping the marker silently adds the wrong one.
enum MagicContentKind: String, Codable, CaseIterable, Hashable, Sendable {
    case regular
    case token
    case artCard

    var label: String {
        switch self {
        case .regular: return "Card"
        case .token: return "Token"
        case .artCard: return "Art Card"
        }
    }

    /// Scryfall layouts that legitimately answer a lookup of this kind.
    ///
    /// Validation runs in both directions: a token lookup must come back with a
    /// token layout, and an ordinary lookup must *not*. Without the second half,
    /// removing the old blanket layout filter would let a token arrive through a
    /// regular lookup — the same bug pointing the other way.
    var acceptedLayouts: Set<String> {
        switch self {
        case .regular:
            return []  // Handled by the existing unsupported-layout denylist.
        case .token:
            return ["token", "double_faced_token", "emblem"]
        case .artCard:
            return ["art_series"]
        }
    }

    /// The Scryfall `set_type` a child set of this kind carries.
    ///
    /// Art series sets are **memorabilia**, not "art_series" — that string is a
    /// card *layout* and is not a set type at all. The existing directory filter
    /// lists `"art_series"` among its excluded set types, where it has never
    /// matched anything; `"memorabilia"` is what actually excludes them.
    var childSetType: String? {
        switch self {
        case .regular: return nil
        case .token: return "token"
        case .artCard: return "memorabilia"
        }
    }
}

/// The marker printed before the collector number.
///
/// Kept verbatim alongside the parsed kind so the scanner can show the user what
/// it actually read — `Token · T 0017 MSH EN` — rather than only the provider
/// identity it resolved to. A wrong resolution is much easier to spot when the
/// printed identity is on screen beside the card name.
enum MagicPrintedMarker: String, Hashable, Sendable {
    case token = "T"
    case artCard = "A"

    var contentKind: MagicContentKind {
        switch self {
        case .token: return .token
        case .artCard: return .artCard
        }
    }

    /// Whether a leading letter on the collector-number line is a content marker
    /// or just the rarity letter Magic also prints there.
    ///
    /// Only `T` is treated as a marker today. `A` is listed for completeness but
    /// deliberately excluded until the printed syntax has been confirmed from a
    /// physical art card — guessing here would misread ordinary cards, and the
    /// rarity letters (C/U/R/M/S/L/P) must keep being ignored.
    static func marker(for letter: String) -> MagicPrintedMarker? {
        letter.uppercased() == "T" ? .token : nil
    }
}
