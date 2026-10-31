import Foundation

/// First slice accepts a complete, contiguous footer in one observation. It
/// never joins unrelated title/number/language observations across a frame.
struct LorcanaRecognitionAdapter: GameRecognitionAdapter {
    let registry: LorcanaCatalogRegistry
    var game: CardGame { .lorcana }
    var customWords: [String] { registry.customWords }
    private static let expression = try! NSRegularExpression(pattern:
        "(?<![A-Z0-9/-])([0-9OIL]{1,4})[\\t ]*/[\\t ]*([A-Z0-9][A-Z0-9-]{0,11})[\\t ]+([A-Z]{2})[\\t ]+([A-Z0-9][A-Z0-9-]{0,11})(?![A-Z0-9/-])")

    func identify(_ lines: [RecognizedLine]) -> GameRecognitionOutcome {
        var found: Set<LorcanaPrintedIdentity> = []
        for line in lines {
            guard line.text.utf16.count <= 1_024 else { continue }
            if let bounds = line.boundingBox {
                guard bounds.minX.isFinite, bounds.minY.isFinite, bounds.width.isFinite, bounds.height.isFinite,
                      bounds.width > 0, bounds.height > 0,
                      CGRect(x: 0, y: 0, width: 1, height: 1).contains(bounds) else { continue }
            }
            let text = line.text.uppercased() as NSString
            for match in Self.expression.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
                var number = text.substring(with: match.range(at: 1))
                var denominator = text.substring(with: match.range(at: 2))
                let language = text.substring(with: match.range(at: 3)).lowercased()
                let marker = text.substring(with: match.range(at: 4))
                let denominators = registry.denominatorsByScope["\(language):\(marker)"]
                // Confusions are only repaired in numeric positions of a known
                // footer scope. Promo tokens and release markers stay literal.
                if let denominators {
                    number = Self.numericReading(number)
                    if !denominators.contains(denominator),
                       LorcanaPrintedIdentity.matches(denominator, "[0-9OIL]+"),
                       denominators.contains(Self.numericReading(denominator)) {
                        denominator = Self.numericReading(denominator)
                    }
                }
                guard let footer = try? LorcanaPrintedIdentity(collectorNumber: number,
                    denominator: denominator, language: language, printedSetMarker: marker) else { continue }
                found.insert(footer)
                if found.count > 1 { return .ambiguous }
            }
        }
        guard let footer = found.first,
              let identifier = try? Self.identifier(footer, generation: registry.generation) else { return .nothing }
        return .identified(ScanSubject(identifier: identifier))
    }

    static func identifier(_ footer: LorcanaPrintedIdentity, generation: String) throws -> ScanIdentifier {
        try .init(game: .lorcana, namespace: "printed-footer",
                  fields: [.init(key: "collectorNumber", value: footer.collectorNumber),
                           .init(key: "denominator", value: footer.denominator),
                           .init(key: "language", value: footer.language),
                           .init(key: "printedSetMarker", value: footer.printedSetMarker)],
                  displayIdentifier: footer.displayIdentifier, suppressionIdentity: "footer:\(footer.evidenceKey)",
                  catalogGeneration: generation)
    }

    private static func numericReading(_ value: String) -> String {
        value.replacingOccurrences(of: "O", with: "0").replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "L", with: "1")
    }
}
