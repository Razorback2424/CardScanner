import Foundation

struct YuGiOhRecognitionAdapter: GameRecognitionAdapter {
    static let underArtRegion = SupplementalTextRegion(id: "yugioh.under-art",
        cardRelativeRect: CGRect(x: 0.03, y: 0.20, width: 0.94, height: 0.11))
    let catalog: YuGiOhCatalog
    var game: CardGame { .yuGiOh }
    var customWords: [String] { [] }
    var supplementalRegion: SupplementalTextRegion? { Self.underArtRegion }
    private static let codeExpression = try! NSRegularExpression(pattern: "(?<![A-Z0-9])([A-Z0-9]{2,4})\\s?[-–—]\\s?([A-Z0-9]{3,5})(?![A-Z0-9])")
    private static let passcodeExpression = try! NSRegularExpression(pattern: "(?<![0-9])[0-9]{8}(?![0-9])")
    private static func valid(_ line: RecognizedLine) -> Bool {
        guard line.text.utf16.count <= 1024 else { return false }
        guard let box = line.boundingBox else { return true }
        return box.minX.isFinite && box.minY.isFinite && box.width.isFinite && box.height.isFinite
            && box.width > 0 && box.height > 0 && CGRect(x: 0, y: 0, width: 1, height: 1).contains(box)
    }
    func needsSupplementalText(afterFooterLines lines: [RecognizedLine]) -> Bool {
        lines.contains { line in
            guard Self.valid(line), line.text.utf16.count <= 120 else { return false }
            return line.text.range(of: "KONAMI|\\bEDITION\\b|(?<![0-9])[0-9]{8}(?![0-9])", options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
    func identify(_ lines: [RecognizedLine]) -> GameRecognitionOutcome { identify(footerLines: lines, supplementalLines: []) }
    func identify(footerLines: [RecognizedLine], supplementalLines: [RecognizedLine]) -> GameRecognitionOutcome {
        let footer = footerLines.filter(Self.valid), band = supplementalLines.filter(Self.valid)
        var codes: Set<String> = []
        let codeLines = footer.filter { $0.boundingBox.map { $0.minX < 0.5 } ?? true }
            + band.filter { $0.boundingBox.map { $0.midX >= 0.45 } ?? true }
        for line in codeLines {
            let text = line.text.uppercased() as NSString
            for match in Self.codeExpression.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
                let literal = text.substring(with: match.range(at: 1)) + "-" + text.substring(with: match.range(at: 2))
                if catalog.printingsByCode[literal] != nil { codes.insert(literal); continue }
                codes.formUnion(readings(literal).filter { catalog.printingsByCode[$0] != nil })
            }
        }
        guard codes.count <= 1 else { return .ambiguous }
        guard let code = codes.first, let family = catalog.printingsByCode[code] else { return .nothing }
        var passcodes: Set<Int> = []
        for line in footer where line.boundingBox.map({ $0.minX < 0.45 }) ?? true {
            let text = line.text as NSString
            for match in Self.passcodeExpression.matches(in: line.text, range: NSRange(location: 0, length: text.length)) {
                if let value = Int(text.substring(with: match.range)) { passcodes.insert(value) }
            }
        }
        let known = family.reduce(into: Set<Int>()) { $0.formUnion($1.card.passcodes) }
        if !passcodes.isEmpty && !known.isEmpty && known.isDisjoint(with: passcodes) {
            return .rejected(.init(reason: "Passcode conflicts with printed code", blocksFallbackRecognition: true))
        }
        let editionLines = footer.filter { $0.boundingBox.map { $0.minX < 0.5 } ?? true }
            + band.filter { $0.boundingBox.map { $0.maxX <= 0.5 } ?? true }
        return .identified(.init(identifier: try! Self.identifier(code: code, generation: catalog.generation),
            printedEdition: .merged(editionLines.map { Self.edition($0.text) })))
    }
    /// Only digit-led First tokens are accepted. T/S/I fragments overlap Limited
    /// and are deliberately illegible. These are synthetic rules, not camera calibration.
    static func edition(_ text: String) -> PrintedEditionEvidence {
        guard text.utf16.count <= 40, text.range(of: "\\bEDITION\\b", options: [.regularExpression, .caseInsensitive]) != nil else { return .absent }
        let upper = text.uppercased()
        let first = upper.range(of: "(?<![A-Z0-9])1(?:ST|T|[\"’])?\\s+EDITION\\b", options: .regularExpression) != nil
        let limited = upper.range(of: "\\b(?:LIMITED|LIMI|LIMITE|IMITED|MITED|ITED)\\s*EDITION\\b", options: .regularExpression) != nil
        var observations: [PrintedEditionEvidence] = []
        if first { observations.append(.observed(.yugiohFirstEdition)) }
        if limited { observations.append(.observed(.yugiohLimited)) }
        return observations.isEmpty ? .unreadable : .merged(observations)
    }
    private func readings(_ code: String) -> Set<String> {
        let substitutions: [Character: Character] = ["O":"0", "0":"O", "I":"1", "L":"1", "S":"5", "5":"S", "B":"8", "8":"B", "Z":"2", "2":"Z"]
        let chars = Array(code)
        let positions = chars.indices.filter { substitutions[chars[$0]] != nil }
        guard positions.count <= 6 else { return [] }
        var values: Set<String> = [code]
        for index in positions {
            for value in Array(values) {
                var changed = Array(value); changed[index] = substitutions[changed[index]]!
                values.insert(String(changed))
            }
        }
        return values
    }
    static func identifier(code: String, generation: String) throws -> ScanIdentifier {
        try .init(game: .yuGiOh, namespace: "printed-set-code", fields: [.init(key: "code", value: code)],
            displayIdentifier: code, suppressionIdentity: "code:\(code)", catalogGeneration: generation)
    }
}
