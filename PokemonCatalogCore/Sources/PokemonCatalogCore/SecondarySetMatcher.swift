import Foundation

public enum PokemonCatalogSecondarySetMatcher {
    public enum Outcome: Equatable, Sendable {
        case matched(PokemonCatalogSecondarySet)
        case none
        case ambiguous([String])
    }

    public static func match(
        tcgdex: PokemonCatalogProviderSet,
        directoryRow: PokemonCatalogProviderDirectoryRow,
        candidates: [PokemonCatalogSecondarySet]
    ) -> Outcome {
        let tcgdexName = PokemonCatalogTextNormalization.canonicalMembershipName(
            tcgdex.name
        )
        let directoryName = PokemonCatalogTextNormalization.canonicalMembershipName(
            directoryRow.name
        )
        let name = tcgdexName.isEmpty ? directoryName : tcgdexName
        let code = PokemonCatalogTextNormalization.normalizedCode(
            tcgdex.abbreviation?.official
        )
        let date = PokemonCatalogTextNormalization.date(
            tcgdex.releaseDate ?? directoryRow.releaseDate
        )
        let total = tcgdex.cardCount?.total ?? directoryRow.cardCount?.total
        let official = tcgdex.cardCount?.official ?? directoryRow.cardCount?.official

        let matches = candidates.filter { candidate in
            let signals = signalCount(
                candidate: candidate,
                tcgdexName: name,
                tcgdexCode: code,
                tcgdexDate: date,
                tcgdexTotal: total,
                tcgdexOfficial: official
            )
            return signals.count >= 3 && (signals.totalMatch || signals.nameMatch)
        }

        switch matches.count {
        case 0: return .none
        case 1: return .matched(matches[0])
        default:
            return .ambiguous(matches.map(\.id).sorted())
        }
    }

    private struct Signals {
        let count: Int
        let totalMatch: Bool
        let nameMatch: Bool
    }

    private static func signalCount(
        candidate: PokemonCatalogSecondarySet,
        tcgdexName: String,
        tcgdexCode: String?,
        tcgdexDate: Date?,
        tcgdexTotal: Int?,
        tcgdexOfficial: Int?
    ) -> Signals {
        let codeMatch = tcgdexCode != nil
            && PokemonCatalogTextNormalization.normalizedCode(candidate.ptcgoCode) == tcgdexCode
        let dateMatch: Bool = {
            guard let tcgdexDate,
                  let candidateDate = PokemonCatalogTextNormalization.date(candidate.releaseDate)
            else { return false }
            return abs(candidateDate.timeIntervalSince(tcgdexDate)) <= 3 * 86_400
        }()
        let totalMatch = tcgdexTotal != nil && candidate.total == tcgdexTotal
        let printedTotalMatch = (tcgdexOfficial ?? 0) > 0
            && candidate.printedTotal == tcgdexOfficial
        let candidateName = PokemonCatalogTextNormalization.canonicalMembershipName(
            candidate.name
        )
        let exactNameMatch = !tcgdexName.isEmpty
            && !candidateName.isEmpty
            && tcgdexName == candidateName
        // A bare prefix is unsafe for parent/subset pairs such as
        // "30th Celebration" and "30th Celebration Classic Collection".
        // Let prefix matching help only when the card totals corroborate the
        // same identity; exact names remain an independent signal.
        let prefixNameMatch = totalMatch
            && !tcgdexName.isEmpty
            && !candidateName.isEmpty
            && (tcgdexName.hasPrefix(candidateName)
                || candidateName.hasPrefix(tcgdexName))
        let nameMatch = exactNameMatch || prefixNameMatch

        return Signals(
            count: [codeMatch, dateMatch, totalMatch, printedTotalMatch, nameMatch]
                .filter { $0 }
                .count,
            totalMatch: totalMatch,
            nameMatch: nameMatch
        )
    }
}
