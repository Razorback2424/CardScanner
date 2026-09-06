import Foundation

/// The label evidence read from a graded slab.
///
/// This is deliberately evidence rather than card identity. The card's own
/// footer still has to resolve through the normal catalog path before a scan
/// can be committed. Keeping the two pieces separate also lets an unreadable
/// label degrade to the existing raw-card scanner behavior.
struct GradedSlabEvidence: Equatable, Hashable, Sendable {
    let company: GradingCompany
    let grade: CardGrade
    let certificationNumber: String?
    let labelCardText: [String]

    /// Stable enough to carry through confirmation and suppression, while
    /// retaining the distinction between an unread certificate and a known
    /// certificate.
    var suppressionFragment: String {
        [
            company.rawValue,
            grade.identityFragment,
            "cert=\(certificationNumber ?? "?")"
        ].joined(separator: "|")
    }
}

/// Whether a printed number normally appears before or after the grade word.
/// It is a tie-breaker only; both forms are accepted by the parser.
enum GradingNumberPosition: Sendable {
    case beforeWord
    case afterWord
}

private struct GradedGradeWord: Sendable {
    let tokens: [String]
    let label: String

    init(_ tokens: [String], label: String) {
        self.tokens = tokens
        self.label = label
    }
}

/// The small amount of per-grader knowledge the OCR parser needs.
///
/// The table is intentionally data, not a switch tree. Adding a new label
/// spelling should not change the parsing algorithm or create a new path that
/// can accidentally outrank an existing grader.
private struct GradingLabelSpec: Sendable {
    let company: GradingCompany
    let companyTokens: [[String]]
    let gradeWords: [GradedGradeWord]
    /// A bare number in these labels is usually the card's collector number.
    /// TAG is the deliberate exception because its label may expose only a
    /// numeric grade.
    let requiresGradeWord: Bool
    let numberPosition: GradingNumberPosition
    let certDigits: ClosedRange<Int>
    let qualifierTokens: [String]
}

enum GradedLabelParser {
    private struct LabelToken: Hashable, Sendable {
        let text: String
        let slashAdjacent: Bool
    }

    private struct TokenPosition: Hashable, Sendable {
        let lineIndex: Int
        let tokenIndex: Int
    }

    private struct LocatedToken: Hashable, Sendable {
        let token: LabelToken
        let position: TokenPosition
    }

    private struct LocatedPhrase: Hashable, Sendable {
        let lineIndex: Int
        let startTokenIndex: Int
        let endTokenIndex: Int

        var position: TokenPosition {
            TokenPosition(lineIndex: lineIndex, tokenIndex: startTokenIndex)
        }
    }

    private struct ParsedLine: Sendable {
        let original: String
        let tokens: [LabelToken]
    }

    /// Longest grade phrases come first. This prevents `GEM MINT` from being
    /// reduced to the shorter `MINT` match when both are present.
    private static let specs: [GradingLabelSpec] = [
        GradingLabelSpec(
            company: .psa,
            companyTokens: [["PSA"]],
            gradeWords: [
                GradedGradeWord(["AUTHENTIC"], label: "Authentic"),
                GradedGradeWord(["GEM", "MT"], label: "Gem Mint"),
                GradedGradeWord(["NM", "MT"], label: "NM-MT"),
                GradedGradeWord(["EX", "MT"], label: "EX-MT"),
                GradedGradeWord(["VG", "EX"], label: "VG-EX"),
                GradedGradeWord(["MINT"], label: "Mint"),
                GradedGradeWord(["GOOD"], label: "Good"),
                GradedGradeWord(["NM"], label: "NM"),
                GradedGradeWord(["EX"], label: "EX"),
                GradedGradeWord(["VG"], label: "VG"),
                GradedGradeWord(["PR"], label: "PR")
            ],
            requiresGradeWord: true,
            numberPosition: .afterWord,
            certDigits: 8...9,
            qualifierTokens: ["OC", "ST", "MK", "PD", "MC"]
        ),
        GradingLabelSpec(
            company: .bgs,
            companyTokens: [["BGS"], ["BECKETT"]],
            gradeWords: [
                GradedGradeWord(["BLACK", "LABEL"], label: "Black Label"),
                GradedGradeWord(["GEM", "MINT"], label: "Gem Mint"),
                GradedGradeWord(["GEM", "MT"], label: "Gem Mint"),
                GradedGradeWord(["PRISTINE"], label: "Pristine"),
                GradedGradeWord(["NM", "MT"], label: "NM-MT"),
                GradedGradeWord(["EX", "MT"], label: "EX-MT"),
                GradedGradeWord(["VG", "EX"], label: "VG-EX"),
                GradedGradeWord(["MINT"], label: "Mint"),
                GradedGradeWord(["NM"], label: "NM"),
                GradedGradeWord(["EX"], label: "EX"),
                GradedGradeWord(["VG"], label: "VG")
            ],
            requiresGradeWord: true,
            numberPosition: .beforeWord,
            certDigits: 10...10,
            qualifierTokens: []
        ),
        GradingLabelSpec(
            company: .cgc,
            companyTokens: [["CGC"]],
            gradeWords: [
                GradedGradeWord(["PRISTINE"], label: "Pristine"),
                GradedGradeWord(["GEM", "MINT"], label: "Gem Mint"),
                GradedGradeWord(["NM", "MINT"], label: "NM/Mint"),
                GradedGradeWord(["MINT+"], label: "Mint+"),
                GradedGradeWord(["MINT"], label: "Mint"),
                GradedGradeWord(["NM"], label: "NM")
            ],
            requiresGradeWord: true,
            numberPosition: .beforeWord,
            certDigits: 9...10,
            qualifierTokens: []
        ),
        GradingLabelSpec(
            company: .sgc,
            companyTokens: [["SGC"]],
            gradeWords: [
                GradedGradeWord(["PRISTINE"], label: "Pristine"),
                GradedGradeWord(["GEM"], label: "Gem"),
                GradedGradeWord(["MT+"], label: "MT+"),
                GradedGradeWord(["MT"], label: "MT"),
                GradedGradeWord(["MINT"], label: "Mint")
            ],
            requiresGradeWord: true,
            numberPosition: .beforeWord,
            certDigits: 9...10,
            qualifierTokens: []
        ),
        GradingLabelSpec(
            company: .bccg,
            companyTokens: [["BCCG"]],
            gradeWords: [
                GradedGradeWord(["MINT"], label: "Mint"),
                GradedGradeWord(["NM", "MT"], label: "NM-MT"),
                GradedGradeWord(["NM"], label: "NM")
            ],
            requiresGradeWord: true,
            numberPosition: .beforeWord,
            certDigits: 9...10,
            qualifierTokens: []
        ),
        GradingLabelSpec(
            company: .bvg,
            companyTokens: [["BVG"]],
            gradeWords: [
                GradedGradeWord(["PRISTINE"], label: "Pristine"),
                GradedGradeWord(["GEM", "MINT"], label: "Gem Mint"),
                GradedGradeWord(["MINT"], label: "Mint"),
                GradedGradeWord(["NM", "MT"], label: "NM-MT"),
                GradedGradeWord(["NM"], label: "NM")
            ],
            requiresGradeWord: true,
            numberPosition: .beforeWord,
            certDigits: 9...10,
            qualifierTokens: []
        ),
        GradingLabelSpec(
            company: .tag,
            companyTokens: [["TAG"]],
            gradeWords: [
                GradedGradeWord(["PRISTINE"], label: "Pristine")
            ],
            requiresGradeWord: false,
            numberPosition: .beforeWord,
            // TAG's certificate format has changed across label revisions. A
            // broad range is intentional until device captures calibrate it.
            certDigits: 6...12,
            qualifierTokens: []
        )
    ]

    /// Vocabulary passed to Vision for the low-frequency label request. The
    /// parser remains authoritative; these words only make the OCR candidate
    /// list less likely to lose short grader tokens such as `PSA` or `TAG`.
    static var visionCustomWords: [String] {
        specs.flatMap { spec in
            spec.companyTokens.flatMap { $0 } + spec.gradeWords.flatMap { $0.tokens }
        }.uniqued()
    }

    /// Parses a label band conservatively. A company by itself is never enough
    /// to claim a slab, and evidence from two different graders is rejected as
    /// ambiguous rather than ranked.
    static func parse(_ lines: [RecognizedLine]) -> GradedSlabEvidence? {
        let parsedLines = lines.compactMap { line -> ParsedLine? in
            let original = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !original.isEmpty else { return nil }
            return ParsedLine(original: original, tokens: tokenize(original))
        }
        guard !parsedLines.isEmpty else { return nil }

        let companyMatches = specs.compactMap { spec -> (GradingLabelSpec, [LocatedPhrase])? in
            let matches = phraseMatches(spec.companyTokens, in: parsedLines)
            return matches.isEmpty ? nil : (spec, matches)
        }
        let companies = Set(companyMatches.map { $0.0.company })
        guard companies.count == 1, let (spec, companyLocations) = companyMatches.first else {
            return nil
        }

        let wordMatches = spec.gradeWords.enumerated().flatMap { wordIndex, word in
            phraseMatches([word.tokens], in: parsedLines).map {
                (wordIndex: wordIndex, word: word, location: $0)
            }
        }
        let nearbyWordMatches = wordMatches.filter {
            isNear($0.location, companyLocations)
        }
        let selectedWord = nearbyWordMatches.sorted { lhs, rhs in
            if lhs.word.tokens.count != rhs.word.tokens.count {
                return lhs.word.tokens.count > rhs.word.tokens.count
            }
            return proximity(lhs.location, to: companyLocations)
                < proximity(rhs.location, to: companyLocations)
        }.first

        let numericCandidates = locatedTokens(in: parsedLines).compactMap { located -> (LocatedToken, String, Double)? in
            guard !located.token.slashAdjacent,
                  let normalized = normalizedNumericText(located.token.text),
                  let value = Double(normalized),
                  value >= 1,
                  value <= 10,
                  isHalfStep(value)
            else { return nil }
            return (located, normalized, value)
        }.filter { candidate in
            guard isNear(candidate.0.position, companyLocations) else { return false }
            if let selectedWord {
                return isNear(selectedWord.location, candidate.0.position)
            }
            return true
        }

        let selectedNumber = numericCandidates.sorted { lhs, rhs in
            numberScore(
                lhs.0,
                companyLocations: companyLocations,
                wordLocation: selectedWord?.location,
                position: spec.numberPosition
            ) < numberScore(
                rhs.0,
                companyLocations: companyLocations,
                wordLocation: selectedWord?.location,
                position: spec.numberPosition
            )
        }.first

        guard selectedWord != nil || selectedNumber != nil else { return nil }
        guard !spec.requiresGradeWord || selectedWord != nil else { return nil }

        let qualifiers = locatedTokens(in: parsedLines)
            .filter { located in
                spec.qualifierTokens.contains(located.token.text)
                    && isNear(located.position, companyLocations)
            }
            .map(\.token.text)
            .uniqued()
        let qualifier = qualifiers.count == 1 ? qualifiers.first : nil

        let certificationCandidates = locatedTokens(in: parsedLines).compactMap { located -> String? in
            guard !located.token.slashAdjacent,
                  let digits = normalizedDigitString(located.token.text),
                  spec.certDigits.contains(digits.count),
                  !isGradeToken(located.token.text)
            else { return nil }
            return digits
        }
        let certificationValues = certificationCandidates.uniqued()
        let certificationNumber = certificationValues.count == 1 ? certificationValues.first : nil

        let recognizedPositions = recognizedTokenPositions(
            parsedLines: parsedLines,
            companyLocations: companyLocations,
            wordMatches: wordMatches,
            selectedNumber: selectedNumber?.0,
            qualifierTokens: spec.qualifierTokens,
            certificationCandidates: certificationCandidates
        )

        let labelCardText = parsedLines.enumerated().compactMap { lineIndex, line -> String? in
            let hasCardText = line.tokens.enumerated().contains { tokenIndex, token in
                let position = TokenPosition(lineIndex: lineIndex, tokenIndex: tokenIndex)
                return !recognizedPositions.contains(position)
                    && !labelOnlyTokens.contains(token.text)
            }
            return hasCardText ? line.original : nil
        }

        return GradedSlabEvidence(
            company: spec.company,
            grade: CardGrade(
                value: selectedNumber.map { canonicalGradeValue($0.2) },
                label: selectedWord?.word.label,
                qualifier: qualifier
            ),
            certificationNumber: certificationNumber,
            labelCardText: labelCardText
        )
    }

    private static let labelOnlyTokens: Set<String> = [
        "CENTERING", "CORNERS", "EDGES", "SURFACE", "SUBGRADES",
        "FINAL", "GRADE", "REPORT", "QR"
    ]

    private static func tokenize(_ text: String) -> [LabelToken] {
        var tokens: [LabelToken] = []
        var current = ""
        var slashBeforeCurrent = false
        var pendingSlash = false

        for scalar in text.uppercased().unicodeScalars {
            let isASCIIAlphaNumeric = (48...57).contains(scalar.value)
                || (65...90).contains(scalar.value)
            let isDecimalPoint = scalar == "."
                && current.unicodeScalars.last.map({ (48...57).contains($0.value) }) == true
            let isGradePunctuation = scalar == "+" && !current.isEmpty

            if isASCIIAlphaNumeric || isDecimalPoint || isGradePunctuation {
                if current.isEmpty {
                    slashBeforeCurrent = pendingSlash
                    pendingSlash = false
                }
                current.unicodeScalars.append(scalar)
            } else {
                if !current.isEmpty {
                    tokens.append(
                        LabelToken(
                            text: current,
                            slashAdjacent: slashBeforeCurrent || scalar == "/"
                        )
                    )
                    current.removeAll(keepingCapacity: true)
                    slashBeforeCurrent = false
                }
                pendingSlash = scalar == "/"
            }
        }

        if !current.isEmpty {
            tokens.append(LabelToken(text: current, slashAdjacent: slashBeforeCurrent))
        }
        return tokens
    }

    private static func phraseMatches(
        _ phrases: [[String]],
        in lines: [ParsedLine]
    ) -> [LocatedPhrase] {
        var matches: [LocatedPhrase] = []
        for phrase in phrases where !phrase.isEmpty {
            for (lineIndex, line) in lines.enumerated() {
                guard line.tokens.count >= phrase.count else { continue }
                for start in 0...(line.tokens.count - phrase.count) {
                    let matchesPhrase = zip(phrase, line.tokens[start..<(start + phrase.count)])
                        .allSatisfy { expected, actual in expected == actual.text }
                    guard matchesPhrase else { continue }
                    matches.append(
                        LocatedPhrase(
                            lineIndex: lineIndex,
                            startTokenIndex: start,
                            endTokenIndex: start + phrase.count - 1
                        )
                    )
                }
            }
        }
        return matches
    }

    private static func locatedTokens(in lines: [ParsedLine]) -> [LocatedToken] {
        lines.enumerated().flatMap { lineIndex, line in
            line.tokens.enumerated().map { tokenIndex, token in
                LocatedToken(
                    token: token,
                    position: TokenPosition(lineIndex: lineIndex, tokenIndex: tokenIndex)
                )
            }
        }
    }

    private static func isNear(
        _ location: LocatedPhrase,
        _ otherLocations: [LocatedPhrase]
    ) -> Bool {
        otherLocations.contains { other in
            abs(location.lineIndex - other.lineIndex) <= 1
                && (location.lineIndex != other.lineIndex
                    || location.startTokenIndex <= other.endTokenIndex + 4
                    && other.startTokenIndex <= location.endTokenIndex + 4)
        }
    }

    private static func isNear(
        _ position: TokenPosition,
        _ otherLocations: [LocatedPhrase]
    ) -> Bool {
        otherLocations.contains { other in
            abs(position.lineIndex - other.lineIndex) <= 1
                && (position.lineIndex != other.lineIndex
                    || position.tokenIndex >= other.startTokenIndex - 4
                    && position.tokenIndex <= other.endTokenIndex + 4)
        }
    }

    private static func isNear(
        _ location: LocatedPhrase,
        _ position: TokenPosition
    ) -> Bool {
        abs(location.lineIndex - position.lineIndex) <= 1
            && (location.lineIndex != position.lineIndex
                || position.tokenIndex >= location.startTokenIndex - 4
                && position.tokenIndex <= location.endTokenIndex + 4)
    }

    private static func proximity(
        _ location: LocatedPhrase,
        to otherLocations: [LocatedPhrase]
    ) -> Int {
        otherLocations.map { other in
            abs(location.lineIndex - other.lineIndex) * 10
                + abs(location.startTokenIndex - other.startTokenIndex)
        }.min() ?? Int.max
    }

    private static func numberScore(
        _ number: LocatedToken,
        companyLocations: [LocatedPhrase],
        wordLocation: LocatedPhrase?,
        position: GradingNumberPosition
    ) -> Int {
        var score = companyLocations.map { company in
            abs(number.position.lineIndex - company.lineIndex) * 10
                + abs(number.position.tokenIndex - company.startTokenIndex)
        }.min() ?? Int.max / 2

        if let wordLocation {
            let expectedTokenIndex: Int
            switch position {
            case .beforeWord:
                expectedTokenIndex = wordLocation.startTokenIndex - 1
            case .afterWord:
                expectedTokenIndex = wordLocation.endTokenIndex + 1
            }
            score += abs(number.position.lineIndex - wordLocation.lineIndex) * 20
                + abs(number.position.tokenIndex - expectedTokenIndex)
        }
        return score
    }

    private static func normalizedNumericText(_ text: String) -> String? {
        let mapped = text.uppercased().map { character -> Character in
            switch character {
            case "O": return "0"
            case "I", "L": return "1"
            default: return character
            }
        }
        let result = String(mapped)
        guard !result.isEmpty,
              result.filter({ $0 == "." }).count <= 1,
              result.allSatisfy({ $0.isNumber || $0 == "." })
        else { return nil }

        if result.contains(".") {
            return Double(result).map { String($0) }
        }
        // Keep the project's deliberately narrow OCR confusion policy in one
        // place for integer readings as well.
        guard ScanText.normalizedInteger(result) != nil else { return nil }
        return result
    }

    private static func normalizedDigitString(_ text: String) -> String? {
        let mapped = text.uppercased().map { character -> Character in
            switch character {
            case "O": return "0"
            case "I", "L": return "1"
            default: return character
            }
        }
        let result = String(mapped)
        guard !result.isEmpty,
              result.allSatisfy(\.isNumber),
              ScanText.normalizedInteger(result) != nil
        else { return nil }
        return result
    }

    private static func isGradeToken(_ text: String) -> Bool {
        guard let numeric = normalizedNumericText(text), let value = Double(numeric) else {
            return false
        }
        return value >= 1 && value <= 10 && isHalfStep(value)
    }

    private static func isHalfStep(_ value: Double) -> Bool {
        abs((value * 2).rounded() - value * 2) < 0.0001
    }

    private static func canonicalGradeValue(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    private static func recognizedTokenPositions(
        parsedLines: [ParsedLine],
        companyLocations: [LocatedPhrase],
        wordMatches: [(wordIndex: Int, word: GradedGradeWord, location: LocatedPhrase)],
        selectedNumber: LocatedToken?,
        qualifierTokens: [String],
        certificationCandidates: [String]
    ) -> Set<TokenPosition> {
        var recognized = Set<TokenPosition>()

        for phrase in companyLocations {
            mark(phrase, in: &recognized)
        }
        for match in wordMatches where isNear(match.location, companyLocations) {
            mark(match.location, in: &recognized)
        }
        if let selectedNumber {
            recognized.insert(selectedNumber.position)
        }
        for located in locatedTokens(in: parsedLines)
            where qualifierTokens.contains(located.token.text)
            && isNear(located.position, companyLocations) {
            recognized.insert(located.position)
        }
        // Certificate candidates are already reduced to strings. Mark any
        // matching token so a cert-only line does not leak into card text.
        for located in locatedTokens(in: parsedLines) {
            guard let digits = normalizedDigitString(located.token.text),
                  certificationCandidates.contains(digits)
            else { continue }
            recognized.insert(located.position)
        }
        return recognized
    }

    private static func mark(
        _ phrase: LocatedPhrase,
        in positions: inout Set<TokenPosition>
    ) {
        guard phrase.startTokenIndex <= phrase.endTokenIndex else { return }
        for tokenIndex in phrase.startTokenIndex...phrase.endTokenIndex {
            positions.insert(
                TokenPosition(lineIndex: phrase.lineIndex, tokenIndex: tokenIndex)
            )
        }
    }
}

/// A slab label must agree across multiple label passes before it can change
/// framing or become part of a physical-object identity.
struct SlabEvidenceConfirmationWindow: Equatable, Sendable {
    let matchesRequired: Int
    let windowSize: Int
    private var observations: [GradedSlabEvidence?] = []

    init(matchesRequired: Int = 2, windowSize: Int = 4) {
        self.matchesRequired = max(1, matchesRequired)
        self.windowSize = max(windowSize, self.matchesRequired)
    }

    mutating func observe(_ evidence: GradedSlabEvidence?) -> GradedSlabEvidence? {
        observations.append(evidence)
        if observations.count > windowSize {
            observations.removeFirst(observations.count - windowSize)
        }
        guard let evidence,
              observations.compactMap({ $0 }).filter({ $0 == evidence }).count >= matchesRequired
        else { return nil }
        reset()
        return evidence
    }

    mutating func reset() {
        observations.removeAll(keepingCapacity: true)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
