import Foundation
import OnePieceCatalogCore

enum OnePieceLanguageConfirmation: Sendable { case unconfirmed, userConfirmedEnglish }

struct OnePieceScanProfile: Sendable {
    let generation: String
    let customWords: [String]
    private let expression: NSRegularExpression
    private let languageConfirmation: OnePieceLanguageConfirmation

    init(registry: OnePieceCatalogRegistry, languageConfirmation: OnePieceLanguageConfirmation = .unconfirmed) {
        generation = registry.generation
        customWords = registry.recognitionPrefixes
        self.languageConfirmation = languageConfirmation
        let prefixes = customWords.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern).joined(separator: "|")
        expression = try! NSRegularExpression(pattern: prefixes.isEmpty ? "(?!)" :
            "(?<![A-Z0-9])(" + prefixes + ")[\\t ]*[-‐‑–—][\\t ]*([0-9OIL]{3})(?![A-Z0-9])")
    }

    func identify(_ lines: [RecognizedLine]) -> GameRecognitionOutcome {
        var found: Set<String> = []
        for line in lines {
            // Production observations are already restricted to the footer ROI.
            // Reject invalid/out-of-band geometry; text-only tests use nil.
            if let bounds = line.boundingBox {
                guard bounds.minX.isFinite, bounds.minY.isFinite, bounds.width.isFinite, bounds.height.isFinite,
                      bounds.width > 0, bounds.height > 0,
                      CGRect(x: 0, y: 0, width: 1, height: 1).contains(bounds) else { continue }
            }
            let text = line.text.uppercased()
            let nsText = text as NSString
            for match in expression.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
                let prefix = nsText.substring(with: match.range(at: 1))
                let numeric = nsText.substring(with: match.range(at: 2))
                    .replacingOccurrences(of: "O", with: "0")
                    .replacingOccurrences(of: "I", with: "1")
                    .replacingOccurrences(of: "L", with: "1")
                let number = "\(prefix)-\(numeric)"
                // Catalog coverage is a later stage. An uncataloged number in
                // a supported series still counts toward frame ambiguity and
                // can be retained as an incomplete, recoverable scan.
                found.insert(number)
            }
        }
        guard found.count <= 1 else { return .ambiguous }
        guard let number = found.first else { return .nothing }
        let confirmed = languageConfirmation == .userConfirmedEnglish
        guard let identifier = try? ScanIdentifier(
            game: .onePiece, namespace: "numbered-card",
            fields: [.init(key: "number", value: number),
                     .init(key: "language", value: confirmed ? "en" : "unknown"),
                     .init(key: "languageConfirmation", value: confirmed ? "user-confirmed" : "unconfirmed")],
            displayIdentifier: number, suppressionIdentity: "number:\(number)", catalogGeneration: generation
        ) else { return .nothing }
        return .identified(ScanSubject(identifier: identifier))
    }
}
