import Foundation

struct ScanCandidate: Equatable, Sendable {
    let setCode: String
    let cardNumber: String
    let printedSetTotal: Int
    let setDefinition: PokemonSetDefinition

    var displayIdentifier: String {
        let unpadded = Int(cardNumber).map(String.init) ?? cardNumber
        return "\(setCode) \(unpadded)/\(printedSetTotal)"
    }
}

/// Keeps confirmation tolerant of an occasional missed OCR frame without allowing
/// an old one-off reading to remain valid indefinitely.
struct CandidateConfirmationWindow {
    let matchesRequired: Int
    let windowSize: Int

    private var observations: [ScanCandidate?] = []

    init(matchesRequired: Int = 2, windowSize: Int = 4) {
        self.matchesRequired = matchesRequired
        self.windowSize = max(windowSize, matchesRequired)
    }

    mutating func observe(_ candidate: ScanCandidate?) -> ScanCandidate? {
        observations.append(candidate)
        if observations.count > windowSize {
            observations.removeFirst(observations.count - windowSize)
        }

        guard let candidate else { return nil }

        let matchingCount = observations.compactMap { $0 }.filter { $0 == candidate }.count
        guard matchingCount >= matchesRequired else { return nil }

        reset()
        return candidate
    }

    mutating func reset() {
        observations.removeAll(keepingCapacity: true)
    }
}

enum ScanParser {
    // OCR commonly merges neighboring tokens (OBF223/197, G223/197) and confuses
    // O/0 or I/L/1 in tiny numeric text. Accept those narrow cases, then validate
    // the denominator against a known set before returning a candidate.
    private static let numberRegex = try! NSRegularExpression(
        pattern: #"(?<![0-9])([0-9OIL]{1,3})\s*/\s*([0-9OIL]{1,3})(?![0-9])"#,
        options: []
    )

    // A code may touch digits ("OBF223/197"), but must not be embedded inside an
    // alphabetic word such as "MASCAGNI" -> "ASC".
    private static let setCodeRegex: NSRegularExpression = {
        let alternatives = SetCodeMap.codes
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        return try! NSRegularExpression(
            pattern: "(?<![A-Z])(?:\(alternatives))(?![A-Z])",
            options: []
        )
    }()

    /// Prefer Vision's individual observations so a code stays paired with the
    /// collector number on the same line. Only fall back to joined text when no
    /// individual line resolves, which handles split observations like "OBF" +
    /// "223/197" without making two visible card identifiers ambiguous.
    static func parse(_ recognizedLines: [String]) -> ScanCandidate? {
        let lineCandidates = uniqueCandidates(
            recognizedLines.compactMap { uniqueCandidate(in: $0) }
        )

        if lineCandidates.count == 1 {
            return lineCandidates[0]
        }
        if lineCandidates.count > 1 {
            return nil
        }

        return uniqueCandidate(in: recognizedLines.joined(separator: " "))
    }

    static func parse(_ recognizedText: String) -> ScanCandidate? {
        uniqueCandidate(in: recognizedText)
    }

    private static func uniqueCandidate(in recognizedText: String) -> ScanCandidate? {
        let normalized = recognizedText
            .uppercased()
            .replacingOccurrences(of: "\n", with: " ")

        let codes = setCodeMatches(in: normalized)
        let numbers = numberMatches(in: normalized)
        guard !codes.isEmpty, !numbers.isEmpty else { return nil }

        var candidates: [ScanCandidate] = []

        for code in codes {
            guard let definition = SetCodeMap.definitions[code] else { continue }

            for number in numbers where number.total == definition.officialCount {
                // Collector number zero is never valid. Avoid an unnecessary /000
                // network lookup, but do not impose an arbitrary upper multiplier:
                // some legitimate Pokémon sets have unusually large secret ranges.
                guard number.card >= 1 else { continue }

                candidates.append(
                    ScanCandidate(
                        setCode: code,
                        cardNumber: String(format: "%03d", number.card),
                        printedSetTotal: number.total,
                        setDefinition: definition
                    )
                )
            }
        }

        let unique = uniqueCandidates(candidates)
        return unique.count == 1 ? unique[0] : nil
    }

    private static func setCodeMatches(in text: String) -> [String] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return setCodeRegex.matches(in: text, options: [], range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    private static func numberMatches(in text: String) -> [(card: Int, total: Int)] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return numberRegex.matches(in: text, options: [], range: range).compactMap { match in
            guard let cardRange = Range(match.range(at: 1), in: text),
                  let totalRange = Range(match.range(at: 2), in: text),
                  let card = normalizedInteger(String(text[cardRange])),
                  let total = normalizedInteger(String(text[totalRange])) else {
                return nil
            }
            return (card, total)
        }
    }

    private static func normalizedInteger(_ text: String) -> Int? {
        let corrected = text
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "L", with: "1")
        return Int(corrected)
    }

    private static func uniqueCandidates(_ candidates: [ScanCandidate]) -> [ScanCandidate] {
        var result: [ScanCandidate] = []
        for candidate in candidates where !result.contains(candidate) {
            result.append(candidate)
        }
        return result
    }
}
