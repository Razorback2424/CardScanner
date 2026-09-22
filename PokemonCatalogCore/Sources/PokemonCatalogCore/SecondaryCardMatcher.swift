import Foundation

/// Conservative cross-provider card matching for artwork-only enrichment.
/// Missing keys are intentional: a card that cannot be paired with confidence
/// must remain on the provider's placeholder path rather than receive a
/// plausible-looking image for a different card.
public enum PokemonCatalogSecondaryCardMatcher {
    public static func match(
        tcgdexCards: [PokemonCatalogProviderCardBrief],
        secondaryCards: [PokemonCatalogSecondaryCard]
    ) -> [String: PokemonCatalogSecondaryCard] {
        guard tcgdexCards.count == secondaryCards.count else { return [:] }

        let tcgdexNames = tcgdexCards.map {
            PokemonCatalogTextNormalization.canonicalMembershipName($0.name)
        }
        let secondaryNames = secondaryCards.map {
            PokemonCatalogTextNormalization.canonicalMembershipName($0.name)
        }
        var unmatchedTCGdex = Set(tcgdexCards.indices)
        var unmatchedSecondary = Set(secondaryCards.indices)
        var matches: [String: PokemonCatalogSecondaryCard] = [:]

        func pair(_ tcgdexIndex: Int, _ secondaryIndex: Int) {
            guard unmatchedTCGdex.remove(tcgdexIndex) != nil,
                  unmatchedSecondary.remove(secondaryIndex) != nil else { return }
            matches[tcgdexCards[tcgdexIndex].id] = secondaryCards[secondaryIndex]
        }

        let tcgdexByName = Dictionary(grouping: tcgdexCards.indices, by: { tcgdexNames[$0] })
        let secondaryByName = Dictionary(grouping: secondaryCards.indices, by: { secondaryNames[$0] })
        for name in Set(tcgdexByName.keys).intersection(secondaryByName.keys).sorted() {
            guard !name.isEmpty,
                  tcgdexByName[name]?.count == 1,
                  secondaryByName[name]?.count == 1,
                  let tcgdexIndex = tcgdexByName[name]?.first,
                  let secondaryIndex = secondaryByName[name]?.first else { continue }
            pair(tcgdexIndex, secondaryIndex)
        }

        // A suffix such as "LV X" is safe only when it is the sole remaining
        // candidate on both sides. The separator check avoids treating names
        // such as "Mew" and "Mewtwo" as a prefix relationship.
        var prefixClaims: [Int: [Int]] = [:]
        for tcgdexIndex in unmatchedTCGdex {
            let name = tcgdexNames[tcgdexIndex]
            guard !name.isEmpty else { continue }
            let candidates = unmatchedSecondary.filter { secondaryIndex in
                let candidate = secondaryNames[secondaryIndex]
                return candidate.hasPrefix(name + " ")
            }
            guard candidates.count == 1, let secondaryIndex = candidates.first else { continue }
            prefixClaims[secondaryIndex, default: []].append(tcgdexIndex)
        }
        for (secondaryIndex, tcgdexIndices) in prefixClaims where tcgdexIndices.count == 1 {
            pair(tcgdexIndices[0], secondaryIndex)
        }

        let remainingTCGdexByName = Dictionary(
            grouping: unmatchedTCGdex,
            by: { tcgdexNames[$0] }
        )
        let remainingSecondaryByName = Dictionary(
            grouping: unmatchedSecondary,
            by: { secondaryNames[$0] }
        )
        for name in Set(remainingTCGdexByName.keys)
            .intersection(remainingSecondaryByName.keys)
            .sorted() {
            guard !name.isEmpty,
                  let tcgdexIndices = remainingTCGdexByName[name],
                  let secondaryIndices = remainingSecondaryByName[name],
                  tcgdexIndices.count > 1,
                  tcgdexIndices.count == secondaryIndices.count else { continue }
            let orderedTCGdex = tcgdexIndices.sorted {
                numberSortKey(tcgdexCards[$0].localID) < numberSortKey(tcgdexCards[$1].localID)
            }
            let orderedSecondary = secondaryIndices.sorted {
                numberSortKey(secondaryCards[$0].number) < numberSortKey(secondaryCards[$1].number)
            }
            for (tcgdexIndex, secondaryIndex) in zip(orderedTCGdex, orderedSecondary) {
                pair(tcgdexIndex, secondaryIndex)
            }
        }

        return matches
    }

    private struct NumberSortKey: Comparable {
        let number: Int
        let suffix: String
        let raw: String

        static func < (lhs: NumberSortKey, rhs: NumberSortKey) -> Bool {
            if lhs.number != rhs.number { return lhs.number < rhs.number }
            if lhs.suffix != rhs.suffix { return lhs.suffix < rhs.suffix }
            return lhs.raw < rhs.raw
        }
    }

    private static func numberSortKey(_ value: String) -> NumberSortKey {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digitPrefix = String(raw.prefix { $0.isNumber })
        let suffix = String(raw.dropFirst(digitPrefix.count))
        return NumberSortKey(
            number: Int(digitPrefix) ?? Int.max,
            suffix: suffix,
            raw: raw
        )
    }
}
