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
    /// Optional physical evidence read from leftover label text. Slab
    /// identity does not depend on either field.
    let printedFinish: PhysicalVariant?
    let printedPrintRun: PokemonPrintRun?

    init(
        company: GradingCompany,
        grade: CardGrade,
        certificationNumber: String?,
        labelCardText: [String],
        printedFinish: PhysicalVariant? = nil,
        printedPrintRun: PokemonPrintRun? = nil
    ) {
        self.company = company
        self.grade = grade
        self.certificationNumber = certificationNumber
        self.labelCardText = labelCardText
        self.printedFinish = printedFinish
        self.printedPrintRun = printedPrintRun
    }

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
        let endLineIndex: Int
        let endTokenIndex: Int
        let tokenPositions: [TokenPosition]

        var position: TokenPosition {
            TokenPosition(lineIndex: lineIndex, tokenIndex: startTokenIndex)
        }

        init(lineIndex: Int, startTokenIndex: Int, endTokenIndex: Int) {
            self.lineIndex = lineIndex
            self.startTokenIndex = startTokenIndex
            self.endLineIndex = lineIndex
            self.endTokenIndex = endTokenIndex
            self.tokenPositions = (startTokenIndex...endTokenIndex).map {
                TokenPosition(lineIndex: lineIndex, tokenIndex: $0)
            }
        }

        init(
            lineIndex: Int,
            startTokenIndex: Int,
            endLineIndex: Int,
            endTokenIndex: Int,
            tokenPositions: [TokenPosition]
        ) {
            self.lineIndex = lineIndex
            self.startTokenIndex = startTokenIndex
            self.endLineIndex = endLineIndex
            self.endTokenIndex = endTokenIndex
            self.tokenPositions = tokenPositions
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
        let graderWords = specs.flatMap { spec in
            spec.companyTokens.flatMap { $0 } + spec.gradeWords.flatMap { $0.tokens }
        }
        return (graderWords + [
            "HOLO", "HOLOFOIL", "REVERSE", "REV", "1ST", "FIRST",
            "EDITION", "SHADOWLESS", "UNLIMITED"
        ]).uniqued()
    }

    /// Bootstrap-only evidence for the provisional camera guide. A company
    /// match is intentionally weaker than a parsed slab and never activates
    /// slab identity on its own.
    static func company(in lines: [RecognizedLine]) -> GradingCompany? {
        let parsedLines = lines.compactMap { line -> ParsedLine? in
            let original = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !original.isEmpty else { return nil }
            return ParsedLine(original: original, tokens: tokenize(original))
        }
        let matches = specs.compactMap { spec -> GradingCompany? in
            phraseMatches(spec.companyTokens, in: parsedLines).isEmpty ? nil : spec.company
        }
        let companies = Set(matches)
        return companies.count == 1 ? companies.first : nil
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
        let printedEvidence = printedEvidence(from: labelCardText)

        return GradedSlabEvidence(
            company: spec.company,
            grade: CardGrade(
                value: selectedNumber.map { canonicalGradeValue($0.2) },
                label: selectedWord?.word.label,
                qualifier: qualifier
            ),
            certificationNumber: certificationNumber,
            labelCardText: labelCardText,
            printedFinish: printedEvidence.finish,
            printedPrintRun: printedEvidence.printRun
        )
    }

    private static func printedEvidence(
        from lines: [String]
    ) -> (finish: PhysicalVariant?, printRun: PokemonPrintRun?) {
        // Keep phrases on their source line. Flattening all leftover text lets
        // unrelated label rows combine into a finish or print-run assertion.
        let tokenLines = lines.map { tokenize($0).map(\.text) }

        func contains(_ phrase: [String]) -> Bool {
            tokenLines.contains { tokens in
                guard !phrase.isEmpty, tokens.count >= phrase.count else { return false }
                return (0...(tokens.count - phrase.count)).contains { start in
                    Array(tokens[start..<(start + phrase.count)]) == phrase
                }
            }
        }

        // A negated phrase is not positive finish evidence. Leave the finish
        // unresolved so the catalog/user correction path, rather than a parser
        // guess, owns the answer.
        let negatesHolo = contains(["NON", "HOLO"])
            || contains(["NON", "HOLOFOIL"])
            || contains(["NON", "REVERSE", "HOLO"])
        let negatesFoil = contains(["NON", "FOIL"])

        let finish: PhysicalVariant?
        if !negatesHolo && !negatesFoil
            && (contains(["REVERSE", "HOLO"]) || contains(["REV", "HOLO"])) {
            finish = .reverse
        } else if !negatesHolo && !negatesFoil
                    && tokenLines.contains(where: { $0.contains("HOLO") || $0.contains("HOLOFOIL") }) {
            finish = .holo
        } else {
            finish = nil
        }

        let printRuns: [PokemonPrintRun] = [
            (contains(["1ST", "EDITION"]) || contains(["FIRST", "EDITION"])) ? .firstEdition : nil,
            tokenLines.contains(where: { $0.contains("SHADOWLESS") }) ? .shadowless : nil,
            tokenLines.contains(where: { $0.contains("UNLIMITED") }) ? .unlimited : nil
        ].compactMap { $0 }
        let printRun = Set(printRuns).count == 1 ? printRuns.first : nil
        return (finish, printRun)
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

            // Some real labels wrap a two-token grade at the line boundary,
            // e.g. GEM at the end of one OCR line and MT at the start of the
            // next. Keep this exact and adjacent; line proximity is widened
            // separately by `isNear`.
            guard phrase.count > 1, lines.count > 1 else { continue }
            for lineIndex in 0..<(lines.count - 1) {
                let line = lines[lineIndex]
                let nextLine = lines[lineIndex + 1]
                for split in 1..<phrase.count {
                    let leftCount = split
                    let rightCount = phrase.count - split
                    guard line.tokens.count >= leftCount,
                          nextLine.tokens.count >= rightCount else { continue }

                    let leftStart = line.tokens.count - leftCount
                    let leftTokens = line.tokens[leftStart...]
                    let rightTokens = nextLine.tokens[..<rightCount]
                    guard zip(phrase[..<split], leftTokens).allSatisfy({ expected, actual in
                        expected == actual.text
                    }), zip(phrase[split...], rightTokens).allSatisfy({ expected, actual in
                        expected == actual.text
                    }) else { continue }

                    let positions = leftTokens.enumerated().map { offset, _ in
                        TokenPosition(lineIndex: lineIndex, tokenIndex: leftStart + offset)
                    } + rightTokens.enumerated().map { offset, _ in
                        TokenPosition(lineIndex: lineIndex + 1, tokenIndex: offset)
                    }
                    matches.append(
                        LocatedPhrase(
                            lineIndex: lineIndex,
                            startTokenIndex: leftStart,
                            endLineIndex: lineIndex + 1,
                            endTokenIndex: rightCount - 1,
                            tokenPositions: positions
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
            lineDistance(location, other) <= 2
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
            lineDistance(position, other) <= 2
                && (position.lineIndex != other.lineIndex
                    || position.tokenIndex >= other.startTokenIndex - 4
                    && position.tokenIndex <= other.endTokenIndex + 4)
        }
    }

    private static func isNear(
        _ location: LocatedPhrase,
        _ position: TokenPosition
    ) -> Bool {
        lineDistance(position, location) <= 2
            && (location.lineIndex != position.lineIndex
                || position.tokenIndex >= location.startTokenIndex - 4
                && position.tokenIndex <= location.endTokenIndex + 4)
    }

    private static func lineDistance(_ lhs: LocatedPhrase, _ rhs: LocatedPhrase) -> Int {
        if lhs.endLineIndex < rhs.lineIndex { return rhs.lineIndex - lhs.endLineIndex }
        if rhs.endLineIndex < lhs.lineIndex { return lhs.lineIndex - rhs.endLineIndex }
        return 0
    }

    private static func lineDistance(_ position: TokenPosition, _ phrase: LocatedPhrase) -> Int {
        if position.lineIndex < phrase.lineIndex { return phrase.lineIndex - position.lineIndex }
        if position.lineIndex > phrase.endLineIndex { return position.lineIndex - phrase.endLineIndex }
        return 0
    }

    private static func proximity(
        _ location: LocatedPhrase,
        to otherLocations: [LocatedPhrase]
    ) -> Int {
        otherLocations.map { other in
            lineDistance(location, other) * 10
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
            lineDistance(number.position, company) * 10
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
            score += lineDistance(number.position, wordLocation) * 20
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
        positions.formUnion(phrase.tokenPositions)
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
        guard let evidence else { return nil }
        let matchingObservations = observations.compactMap { observation -> GradedSlabEvidence? in
            guard let observation, matches(observation, evidence) else { return nil }
            return observation
        }
        guard matchingObservations.count >= matchesRequired else { return nil }

        reset()
        return evidence
    }

    mutating func reset() {
        observations.removeAll(keepingCapacity: true)
    }

    private func matches(_ lhs: GradedSlabEvidence, _ rhs: GradedSlabEvidence) -> Bool {
        guard lhs.suppressionFragment == rhs.suppressionFragment else { return false }
        guard lhs.certificationNumber == nil, rhs.certificationNumber == nil else { return true }

        let lhsLines = lhs.labelCardText
            .map(Self.normalizedLabelTokens)
            .filter { !$0.isEmpty }
        let rhsLines = rhs.labelCardText
            .map(Self.normalizedLabelTokens)
            .filter { !$0.isEmpty }

        // A glare-obscured label can legitimately leave no card text at all;
        // the shared company/grade/certificate-less suppression fragment is the
        // only evidence available, and it must match itself.
        guard !lhsLines.isEmpty || !rhsLines.isEmpty else { return true }
        guard !lhsLines.isEmpty, !rhsLines.isEmpty else { return false }

        // Require a majority of the larger line's tokens to match. Matching is
        // tolerant of one OCR character substitution, but a single shared word
        // cannot make two different card labels the same slab.
        return lhsLines.contains { lhsTokens in
            rhsLines.contains { rhsTokens in
                let matched = lhsTokens.filter { lhsToken in
                    rhsTokens.contains { rhsToken in
                        Self.tokensMatch(lhsToken, rhsToken)
                    }
                }.count
                return matched * 2 > max(lhsTokens.count, rhsTokens.count)
            }
        }
    }

    private static func normalizedLabelLine(_ line: String) -> String {
        let scalars = line.uppercased().unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == " " ? scalar : " "
        }
        return scalars
            .map(String.init)
            .joined()
            .split(whereSeparator: { $0 == " " })
            .joined(separator: " ")
    }

    private static func normalizedLabelTokens(_ line: String) -> [String] {
        normalizedLabelLine(line).split(separator: " ").map(String.init)
    }

    private static func tokensMatch(_ lhs: String, _ rhs: String) -> Bool {
        guard lhs != rhs else { return true }
        guard lhs.count >= 3, rhs.count >= 3 else { return false }
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            current.reserveCapacity(right.count + 1)
            for (rightIndex, rightCharacter) in right.enumerated() {
                let substitution = previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                let insertion = current[rightIndex] + 1
                let deletion = previous[rightIndex + 1] + 1
                current.append(min(substitution, insertion, deletion))
            }
            previous = current
        }
        return previous[right.count] <= 1
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
