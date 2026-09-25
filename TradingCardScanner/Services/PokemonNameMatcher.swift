import Foundation

/// Conservative OCR/name agreement for Pokémon cards. Every comparison starts
/// with the same normalization used by catalog identity checks; fuzzy matches
/// are deliberately limited to names long enough to carry useful evidence.
enum PokemonNameMatcher {
    static func agrees(cardName: String, readings: [String]) -> Bool {
        !matches([cardName], readings: readings).isEmpty
    }

    /// Returns matching name indices. Any exact or punctuation/spacing variant
    /// suppresses fuzzy matches, so a near spelling cannot compete with a name
    /// that OCR read exactly.
    static func matches(_ names: [String], readings: [String]) -> [Int] {
        let normalizedNames = names.map(CatalogIdentityNormalization.canonicalText)
        let normalizedReadings = readings
            .map(CatalogIdentityNormalization.canonicalText)
            .filter { !$0.isEmpty }

        let exact = normalizedNames.indices.filter { index in
            let name = normalizedNames[index]
            guard !name.isEmpty else { return false }
            let compactName = compact(name)
            return normalizedReadings.contains { reading in
                reading == name || compact(reading) == compactName
            }
        }
        if !exact.isEmpty { return exact }

        return normalizedNames.indices.filter { index in
            let name = compact(normalizedNames[index])
            guard name.count >= 5 else { return false }
            let maximumDistance = name.count <= 7 ? 1 : 2
            return normalizedReadings.contains { reading in
                let reading = compact(reading)
                guard reading.count >= 5 else { return false }
                return damerauLevenshteinDistance(name, reading, limit: maximumDistance)
                    <= maximumDistance
            }
        }
    }

    private static func compact(_ canonical: String) -> String {
        canonical.filter { !$0.isWhitespace }
    }

    /// Unrestricted Damerau–Levenshtein distance. Card names are short, and
    /// callers only ask whether the result is at most two.
    private static func damerauLevenshteinDistance(
        _ lhs: String,
        _ rhs: String,
        limit: Int
    ) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        let leftCount = left.count
        let rightCount = right.count
        if leftCount == 0 { return rightCount }
        if rightCount == 0 { return leftCount }
        if abs(leftCount - rightCount) > limit { return limit + 1 }

        let maximumDistance = leftCount + rightCount
        var matrix = Array(
            repeating: Array(repeating: 0, count: rightCount + 2),
            count: leftCount + 2
        )
        matrix[0][0] = maximumDistance
        for i in 0...leftCount {
            matrix[i + 1][0] = maximumDistance
            matrix[i + 1][1] = i
        }
        for j in 0...rightCount {
            matrix[0][j + 1] = maximumDistance
            matrix[1][j + 1] = j
        }

        var lastRowForCharacter: [Character: Int] = [:]
        for i in 1...leftCount {
            var lastMatchingColumn = 0
            for j in 1...rightCount {
                let previousMatchingRow = lastRowForCharacter[right[j - 1], default: 0]
                let previousMatchingColumn = lastMatchingColumn
                let substitutionCost: Int
                if left[i - 1] == right[j - 1] {
                    substitutionCost = 0
                    lastMatchingColumn = j
                } else {
                    substitutionCost = 1
                }

                let transpositionDistance = matrix[previousMatchingRow][previousMatchingColumn]
                    + (i - previousMatchingRow - 1)
                    + 1
                    + (j - previousMatchingColumn - 1)
                matrix[i + 1][j + 1] = min(
                    min(
                        matrix[i][j] + substitutionCost,
                        matrix[i + 1][j] + 1,
                        matrix[i][j + 1] + 1
                    ),
                    transpositionDistance
                )
            }
            lastRowForCharacter[left[i - 1]] = i
        }
        return matrix[leftCount + 1][rightCount + 1]
    }
}
