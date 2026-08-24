import Foundation

/// Turning what the collection knows about a card into what the price vendor
/// needs to find it — and, more importantly, deciding whether what came back is
/// actually the same card.
///
/// This type exists because the alternative was measured and it was dangerous.
/// A spike that searched by card name and fuzzy-matched the set returned a 1996
/// Base Expansion Pack Oddish for a 2025 Inferno X Oddish — same name, wrong
/// decade, $5.45 against a card worth pennies. Every rule below is there to make
/// that class of answer impossible rather than unlikely.
enum ProductCatalogIdentity {

    // MARK: - Games

    enum Game: String, Sendable {
        case pokemon = "pokemon"
        case pokemonJapan = "pokemon-japan"
        case magic = "magic-the-gathering"
    }

    /// Japanese printings are a separate product line, not a locale of the
    /// English one, so the game is part of identity rather than a setting.
    static func game(for game: CardGame, catalogID: String?) -> Game {
        switch game {
        case .magic:
            return .magic
        case .pokemon:
            let isJapanese = catalogID.map {
                CatalogIdentityNormalization.locale(forCatalogCardID: $0) == .ja
            } ?? false
            return isJapanese ? .pokemonJapan : .pokemon
        }
    }

    // MARK: - Set slugs

    /// The vendor's slug for a set, built rather than searched for.
    ///
    /// Two shapes, both deterministic:
    ///
    /// - Japanese sets are `<tcgdex-ja-id>-<name>-pokemon-japan`, so the id we
    ///   already resolved is a prefix key. Verified unique across all 441 of
    ///   their Japanese sets, and it is what distinguishes `sv3-ruler-of-the-
    ///   black-flame` from the `sv-ruler-of-the-black-flame-deck-build-box`
    ///   that a name match cannot tell apart.
    /// - Everything else is `<slugified set name>-<game>`.
    ///
    /// Returns `nil` rather than a guess when neither applies.
    static func setSlug(
        setName: String,
        japaneseSetID: String?,
        game: Game,
        knownSlugs: [String]
    ) -> String? {
        if game == .pokemonJapan, let japaneseSetID {
            let prefix = japaneseSetID.lowercased() + "-"
            let matches = knownSlugs.filter { $0.hasPrefix(prefix) }
            // Exactly one or nothing. Two candidates means the prefix is not the
            // identity we assumed it was, and picking either would be a guess.
            return matches.count == 1 ? matches[0] : nil
        }

        let candidate = "\(slugify(setName))-\(game.rawValue)"
        guard knownSlugs.isEmpty || knownSlugs.contains(candidate) else { return nil }
        return candidate
    }

    /// The vendor's slug alphabet.
    ///
    /// Deliberately *not* `CatalogIdentityNormalization.canonicalText`, which
    /// expands `&` to `and`. The vendor drops it: "Miscellaneous Cards &
    /// Products" is `miscellaneous-cards-products`, not `...-cards-and-...`.
    static func slugify(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let scalars = folded.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
        }
        return String(scalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: "-")
            .lowercased()
    }

    // MARK: - Accepting a result

    /// Whether a returned product is genuinely the card that was asked for.
    ///
    /// All three of set, number and name must agree. Any one of them alone
    /// admits a wrong card:
    ///
    /// - name alone returned the 1996 Oddish
    /// - set + name alone returned a `1/114` Snivy for a `001/086` Snivy
    ///
    /// The number comparison is the subtle one. `CatalogIdentityNormalization
    /// .localNumber` reduces both `001/086` and `001/114` to `"1"`, because for
    /// catalog lookups the set total is redundant. Here it is the only thing
    /// separating two different cards, so the *printed* number is compared and
    /// the set total is only ignored when one side genuinely omits it.
    static func isSameCard(
        requestedName: String,
        requestedNumber: String,
        requestedSetSlug: String,
        candidateName: String,
        candidateNumber: String,
        candidateSetSlug: String
    ) -> Bool {
        guard requestedSetSlug.caseInsensitiveCompare(candidateSetSlug) == .orderedSame else {
            return false
        }
        guard numbersMatch(requestedNumber, candidateNumber) else { return false }
        return CatalogIdentityNormalization.namesMatch(
            imported: requestedName,
            catalog: candidateName
        )
    }

    /// Printed-number equality.
    ///
    /// `001/086` and `001/114` are different cards and must not compare equal.
    /// `13 // 11` (a double-faced token) has to survive intact. And a bare `011`
    /// against `011` still matches, because neither side claims a total.
    static func numbersMatch(_ requested: String, _ candidate: String) -> Bool {
        let left = numberParts(requested)
        let right = numberParts(candidate)
        guard left.local == right.local, !left.local.isEmpty else { return false }
        // Only compare totals when both sides state one. A vendor that omits the
        // denominator is not thereby claiming a different printing.
        if let leftTotal = left.total, let rightTotal = right.total {
            return leftTotal == rightTotal
        }
        return true
    }

    private static func numberParts(_ value: String) -> (local: String, total: String?) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Double-faced tokens print as "13 // 11". That is one identifier, not a
        // number over a total, so it is compared whole.
        if trimmed.contains("//") {
            return (normalizeSegments(trimmed, separator: "//"), nil)
        }
        let pieces = trimmed.split(separator: "/", maxSplits: 1).map(String.init)
        let local = normalizeNumber(pieces.first ?? trimmed)
        let total = pieces.count > 1 ? normalizeNumber(pieces[1]) : nil
        return (local, total)
    }

    private static func normalizeSegments(_ value: String, separator: String) -> String {
        value
            .components(separatedBy: separator)
            .map { normalizeNumber($0) }
            .joined(separator: "//")
    }

    /// Leading zeros are presentation, not identity: `001` and `1` are the same
    /// card. Anything non-numeric is compared as written, lowercased.
    private static func normalizeNumber(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Int(trimmed) { return String(number) }
        return trimmed.lowercased()
    }
}
