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
        directory: ProductSetDirectory
    ) -> String? {
        if game == .pokemonJapan, let japaneseSetID {
            let prefix = japaneseSetID.lowercased() + "-"
            let matches = directory.slugs.filter { $0.hasPrefix(prefix) }
            // Exactly one or nothing. Two candidates means the prefix is not the
            // identity we assumed it was, and picking either would be a guess.
            if matches.count == 1 { return matches[0] }
        }
        return directory.slug(forCatalogSetName: setName, game: game)
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

/// The vendor's set list, indexed so a catalog set name can find it.
///
/// Deriving the slug from the catalog's own name and requiring an exact hit —
/// what this replaced — resolved 55 of 163 browsable Pokémon sets. The vendor
/// prefixes by era (`sv-prismatic-evolutions-pokemon`, `ex-dragon-pokemon`,
/// `swsh01-sword-shield-base-set-pokemon`) and TCGdex names carry no prefix, so
/// two thirds of the catalogue derived a slug that does not exist. Every card in
/// those sets failed set resolution before a request was made, which is why a
/// collection could sit at hundreds of cards priced only in euros with the
/// fallback reporting progress and changing nothing.
///
/// Matching the vendor's published *name* instead lifts that to 133 of 163.
struct ProductSetDirectory: Sendable {
    /// Every slug the vendor publishes, for the paths that match on slug shape
    /// rather than on name.
    let slugs: [String]
    private let byName: [String: String]

    init(sets: [(id: String, name: String?)]) {
        var slugs: [String] = []
        // Three tiers, best first. A weaker key never displaces a stronger one,
        // and a key two different sets both claim is dropped rather than guessed.
        var tiers: [[String: String]] = [[:], [:], [:], [:]]
        var ambiguous: [Set<String>] = [[], [], [], []]

        for set in sets {
            slugs.append(set.id)
            guard let name = set.name else { continue }
            for (tier, key) in Self.keys(for: name) {
                if let claimed = tiers[tier][key], claimed != set.id {
                    ambiguous[tier].insert(key)
                } else {
                    tiers[tier][key] = set.id
                }
            }
        }

        var byName: [String: String] = [:]
        for tier in (0..<tiers.count).reversed() {
            for (key, id) in tiers[tier] where !ambiguous[tier].contains(key) {
                byName[key] = id
            }
        }
        self.slugs = slugs
        self.byName = byName
    }

    /// The era tokens the vendor puts in front of a set's own name.
    private static let eraPrefixes: Set<String> = [
        "ex", "sv", "sm", "xy", "swsh", "hgss", "dp", "bw", "pl", "hs"
    ]

    private static func keys(for name: String) -> [(tier: Int, key: String)] {
        var result: [(Int, String)] = [(0, CatalogIdentityNormalization.canonicalText(name))]
        // "SV: Prismatic Evolutions", "SWSH01: Sword & Shield Base Set".
        if let suffix = name.split(separator: ":", maxSplits: 1).last, name.contains(":") {
            result.append((1, CatalogIdentityNormalization.canonicalText(String(suffix))))
        }
        // "EX Dragon", "XY Base Set".
        let words = CatalogIdentityNormalization.canonicalText(name).split(separator: " ")
        if let first = words.first, eraPrefixes.contains(String(first)), words.count > 1 {
            result.append((2, words.dropFirst().joined(separator: " ")))
        }
        // The vendor names an era's opening set "<era> Base Set" where the
        // catalog names it after the era alone: `SWSH01: Sword & Shield Base
        // Set` against TCGdex's `Sword & Shield`. Weakest tier, so it can never
        // displace a set actually called "Base Set".
        let suffix = " base set"
        for (_, key) in result where key.hasSuffix(suffix) && key != suffix.trimmingCharacters(in: .whitespaces) {
            result.append((3, String(key.dropLast(suffix.count))))
        }
        return result.filter { !$0.1.isEmpty }
    }

    /// The vendor set that carries this catalog set, or nil when none does.
    func slug(forCatalogSetName name: String, game: ProductCatalogIdentity.Game) -> String? {
        if let matched = byName[CatalogIdentityNormalization.canonicalText(name)] {
            return matched
        }
        // The derived form still wins where the vendor happens to agree, which
        // covers sets whose published name is missing.
        let derived = "\(ProductCatalogIdentity.slugify(name))-\(game.rawValue)"
        // An empty directory is "nothing to check against", not "no such set" —
        // the derivation is still the best guess available.
        guard !slugs.isEmpty else { return derived }
        return slugs.contains(derived) ? derived : nil
    }
}
