import Foundation
import Vision

/// General historical recognition has no card allowlist or bundled expiry.
/// The provider resolves the printing family; every encounter requires a choice.
struct MagicHistoricalLiveEvidence: Codable, Hashable, Sendable {
    static let version = "magic-historical-frames-v1"
    let title: String
    let collectorNumber: String?
    let denominator: Int?
    let titleBounds: CGRect
    let numberBounds: CGRect?
    var encounterID: UUID
    var englishConfirmed = false
    let recognitionVersion: String

    var valid: Bool {
        guard recognitionVersion == Self.version, title.count >= 3, title.count <= 100,
              !title.contains("\\"), !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              Self.validRect(titleBounds), titleBounds.midY >= (title.contains(" // ") ? 0.4 : 0.55),
              titleBounds.midX < 0.85 else { return false }
        if let number = collectorNumber {
            guard number.range(of: #"^[0-9]{1,4}[A-Za-z★]?$"#, options: .regularExpression) != nil,
                  let rect = numberBounds, Self.validRect(rect), rect.midY <= 0.18, rect.midX < 0.82 else { return false }
        } else if numberBounds != nil || denominator != nil { return false }
        return denominator == nil || (1...9999).contains(denominator!)
    }
    /// A search group is not an ownership identity. Exact choice/hydration keeps
    /// each oracle ID, including same-title cards with different logical IDs.
    var choiceGroupID: String { "magic-historical-title:" + MagicHistoricalTitleVocabulary.normalizedTitle(title) }
    private static func validRect(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
            && rect.width > 0 && rect.height > 0
            && CGRect(x: 0, y: 0, width: 1, height: 1).contains(rect)
    }
    func identifier() throws -> ScanIdentifier {
        guard valid else { throw CatalogLookupError.invalidAdapterOutcome }
        return try .init(game: .magic, namespace: "historical-live",
            fields: [.init(key: "evidence", value: String(decoding: JSONEncoder().encode(self), as: UTF8.self))],
            displayIdentifier: title + (collectorNumber.map { " · " + $0 } ?? ""),
            suppressionIdentity: "magic-historical-live:\(MagicHistoricalEvidenceKey.canonicalTitle(title)):\(collectorNumber ?? "title")",
            catalogGeneration: MagicCatalogAdapter.providerGeneration)
    }
    static func decode(_ identifier: ScanIdentifier) throws -> Self {
        guard identifier.game == .magic, identifier.namespace == "historical-live", identifier.fields.count == 1,
              identifier.fields.first?.key == "evidence" else { throw CatalogLookupError.invalidAdapterOutcome }
        let data = Data(identifier.fields[0].value.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["title", "collectorNumber", "denominator", "titleBounds", "numberBounds",
                  "encounterID", "englishConfirmed", "recognitionVersion"]) else { throw CatalogLookupError.invalidAdapterOutcome }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.valid else { throw CatalogLookupError.invalidAdapterOutcome }
        return value
    }
}

enum MagicHistoricalLiveOCR {
    /// Reference/imported photographs need framing; the camera uses its guide.
    /// Rectangle alternatives cannot introduce competing title identities.
    static func readPhotograph(handler: VNImageRequestHandler, encounterID: UUID) throws -> MagicHistoricalLiveEvidence? {
        let rectangles = VNDetectRectanglesRequest()
        rectangles.minimumAspectRatio = 0.55
        rectangles.maximumAspectRatio = 0.85
        rectangles.minimumSize = 0.12
        rectangles.minimumConfidence = 0.7
        rectangles.maximumObservations = 3
        try handler.perform([rectangles])
        var bounds = (rectangles.results ?? []).map(\.boundingBox)
        bounds.append(CGRect(x: 0, y: 0, width: 1, height: 1))
        let readings = try bounds.compactMap { try read(handler: handler, cardRect: $0, encounterID: encounterID) }
        let names = Set(readings.map { MagicHistoricalTitleVocabulary.normalizedTitle($0.title) })
        if let split = readings.first(where: { reading in
            let components = reading.title.components(separatedBy: " // ").map(MagicHistoricalTitleVocabulary.normalizedTitle)
            return components.count == 2 && names.isSubset(of: Set(components + [MagicHistoricalTitleVocabulary.normalizedTitle(reading.title)]))
        }) { return split }
        guard names.count == 1 else { return nil }
        return readings.first(where: { $0.collectorNumber != nil }) ?? readings.first
    }
    static func read(handler: VNImageRequestHandler, cardRect: CGRect, encounterID: UUID) throws -> MagicHistoricalLiveEvidence? {
        guard !cardRect.isEmpty, [cardRect.minX, cardRect.minY, cardRect.width, cardRect.height].allSatisfy(\.isFinite),
              CGRect(x: 0, y: 0, width: 1, height: 1).contains(cardRect) else { return nil }
        // Full card-relative text is required for full-art names, split cards and
        // Future Sight frames. Selection still rejects body text by geometry.
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = true
        request.regionOfInterest = cardRect
        try handler.perform([request])
        let lines = (request.results ?? []).compactMap { o -> RecognizedLine? in
            guard let candidate = o.topCandidates(1).first else { return nil }
            return .init(text: candidate.string, boundingBox: o.boundingBox, confidence: candidate.confidence)
        }
        return parse(lines: lines, encounterID: encounterID)
    }

    static func parse(lines: [RecognizedLine], encounterID: UUID) -> MagicHistoricalLiveEvidence? {
        let titleLines = lines.compactMap { line -> RecognizedLine? in
            guard let rect = line.boundingBox, rect.midX < 0.85,
                  (rect.midY >= 0.55 || (rect.midX < 0.3 && rect.height > rect.width * 0.6)),
                  line.confidence.map({ $0 >= 0.5 }) != false else { return nil }
            guard let title = MagicHistoricalTitleVocabulary.match(line.text) else { return nil }
            return .init(text: title, boundingBox: rect, confidence: line.confidence)
        }.sorted { $0.boundingBox!.midY > $1.boundingBox!.midY }
        guard let first = titleLines.first, let titleRect = first.boundingBox else { return nil }
        // Split titles in a shared top band are joined only when separated
        // horizontally; otherwise several spatial titles are ambiguous.
        let peers = titleLines.filter { abs($0.boundingBox!.midY - titleRect.midY) < 0.045 }
        var title = first.text
        if titleLines.count == 2, titleLines.allSatisfy({ $0.boundingBox!.midX < 0.3 }) {
            let sorted = titleLines.sorted { $0.boundingBox!.midY < $1.boundingBox!.midY }
            let joined = sorted.map(\.text).joined(separator: " // ")
            if let split = MagicHistoricalTitleVocabulary.match(joined) { title = split }
        }
        if peers.count == 2 {
            let sorted = peers.sorted { $0.boundingBox!.minX < $1.boundingBox!.minX }
            guard sorted[0].boundingBox!.maxX < sorted[1].boundingBox!.minX else { return nil }
            title = sorted.map(\.text).joined(separator: " // ")
        } else if peers.count > 2 { return nil }
        // Two unrelated cards or an unrelated title in the frame cannot become
        // a made-up split name or silently collapse to the highest title.
        guard let knownTitle = MagicHistoricalTitleVocabulary.names[MagicHistoricalTitleVocabulary.normalizedTitle(title)] else { return nil }
        let components = Set(knownTitle.components(separatedBy: " // ").map(MagicHistoricalTitleVocabulary.normalizedTitle))
        guard titleLines.allSatisfy({ components.contains(MagicHistoricalTitleVocabulary.normalizedTitle($0.text))
            || MagicHistoricalTitleVocabulary.normalizedTitle($0.text) == MagicHistoricalTitleVocabulary.normalizedTitle(knownTitle) }) else { return nil }
        title = knownTitle
        let regex = try! NSRegularExpression(pattern: #"(?<![0-9A-Za-z])([0-9]{1,4}[A-Za-z★]?)\s*/\s*([0-9]{1,4})(?![0-9A-Za-z])"#)
        var numbers: [(String, Int, CGRect)] = []
        for line in lines {
            guard let rect = line.boundingBox, rect.midY <= 0.18, rect.midX < 0.82,
                  !line.text.uppercased().contains("HP") else { continue }
            for match in regex.matches(in: line.text, range: NSRange(line.text.startIndex..., in: line.text)) {
                guard let n = Range(match.range(at: 1), in: line.text), let d = Range(match.range(at: 2), in: line.text),
                      let denominator = Int(line.text[d]), denominator > 20 else { continue }
                numbers.append((String(line.text[n]), denominator, rect))
            }
        }
        guard numbers.count <= 1 else { return nil }
        let evidence = MagicHistoricalLiveEvidence(title: title, collectorNumber: numbers.first?.0,
            denominator: numbers.first?.1, titleBounds: titleRect, numberBounds: numbers.first?.2,
            encounterID: encounterID, recognitionVersion: MagicHistoricalLiveEvidence.version)
        return evidence.valid ? evidence : nil
    }
}

struct MagicHistoricalLiveWindow {
    private var first: MagicHistoricalLiveEvidence?
    private var startedAt: TimeInterval?
    private var attempts = 0
    private(set) var encounterID = UUID()
    var hasPlausibleEvidence: Bool { first != nil }
    mutating func reset() { self = Self() }
    mutating func begin(at now: TimeInterval) -> Bool {
        if let start = startedAt, now - start > 1.5 { reset() }
        if startedAt == nil { startedAt = now }
        guard attempts < 6 else { return false }; attempts += 1; return true
    }
    mutating func observe(_ evidence: MagicHistoricalLiveEvidence?) -> ScanIdentifier? {
        guard var evidence else { first = nil; encounterID = UUID(); return nil }
        if let first, MagicHistoricalTitleVocabulary.normalizedTitle(first.title) == MagicHistoricalTitleVocabulary.normalizedTitle(evidence.title),
           first.collectorNumber == evidence.collectorNumber, first.denominator == evidence.denominator {
            return try? first.identifier()
        }
        encounterID = UUID(); evidence.encounterID = encounterID; first = evidence; return nil
    }
}

enum MagicHistoricalTitleVocabulary {
    /// Printed ligatures and typographic quotes changed across eras; normalize
    /// only spelling/punctuation equivalents, not card identity or collector IDs.
    static func normalizedTitle(_ raw: String) -> String {
        MagicHistoricalEvidenceKey.canonicalTitle(raw)
            .replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
    }
    private struct Artifact: Decodable { let schemaVersion: Int; let titles: [String] }
    static let names: [String: String] = {
        guard let url = Bundle.main.url(forResource: "historical-title-words", withExtension: "json", subdirectory: "MagicHistoricalPilot"),
              let data = try? Data(contentsOf: url), let artifact = try? JSONDecoder().decode(Artifact.self, from: data),
              artifact.schemaVersion == 1 else { return [:] }
        return Dictionary(artifact.titles.map { (normalizedTitle($0), $0) }, uniquingKeysWith: { a, _ in a })
    }()
    private static let buckets = Dictionary(grouping: names.keys) {
        "\($0.first.map(String.init) ?? ""):\($0.count)"
    }
    static func match(_ raw: String) -> String? {
        let key = normalizedTitle(raw)
        if let exact = names[key] { return exact }
        guard key.count >= 7 else { return nil }
        let candidates = (-1...1).flatMap { delta in
            buckets["\(key.first.map(String.init) ?? ""):\(key.count + delta)"] ?? []
        }
        let matches = candidates.filter { oneEditApart(key, $0) }
        return matches.count == 1 ? names[matches[0]] : nil
    }
    private static func oneEditApart(_ a: String, _ b: String) -> Bool {
        let a = Array(a), b = Array(b)
        var i = 0, j = 0, edits = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { i += 1; j += 1; continue }
            edits += 1; if edits > 1 { return false }
            if a.count >= b.count { i += 1 }
            if b.count >= a.count { j += 1 }
        }
        return edits + (a.count - i) + (b.count - j) <= 1
    }
}

/// The live pilot and corpus runner use the same card-relative OCR bands and
/// source coordinates. A corpus annotation supplies framing, never text evidence.
enum MagicHistoricalOCR {
    static func read(handler: VNImageRequestHandler, sourceSize: CGSize, cardRect: CGRect,
                     encounterID: UUID, snapshot: MagicHistoricalLocalSnapshot) throws -> MagicHistoricalScanEvidence? {
        guard sourceSize.width > 0, sourceSize.height > 0,
              [sourceSize.width, sourceSize.height, cardRect.minX, cardRect.minY,
               cardRect.width, cardRect.height].allSatisfy(\.isFinite),
              !cardRect.isEmpty, !cardRect.isNull,
              CGRect(x: 0, y: 0, width: 1, height: 1).contains(cardRect) else { return nil }
        func request(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> VNRecognizeTextRequest {
            let result = VNRecognizeTextRequest()
            result.recognitionLevel = .accurate
            result.recognitionLanguages = ["en-US"]
            result.usesLanguageCorrection = true
            result.regionOfInterest = CGRect(x: cardRect.minX + x * cardRect.width,
                y: cardRect.minY + y * cardRect.height,
                width: width * cardRect.width, height: height * cardRect.height)
            return result
        }
        let title = request(x: 0.035, y: 0.79, width: 0.93, height: 0.16)
        let footer = request(x: 0.025, y: 0.015, width: 0.95, height: 0.15)
        try handler.perform([title, footer])
        func lines(_ request: VNRecognizeTextRequest) -> [RecognizedLine] {
            (request.results ?? []).compactMap { observation in
                let candidates = observation.topCandidates(3)
                guard let candidate = candidates.first else { return nil }
                let full = CardFramingRegion.fullFrameVisionRect(
                    fromObservationBoundingBox: observation.boundingBox, in: request.regionOfInterest)
                return .init(text: candidate.string, boundingBox: observation.boundingBox,
                    confidence: candidate.confidence, alternatives: candidates.dropFirst().map(\.string),
                    sourcePixelRect: CGRect(x: full.minX * sourceSize.width, y: full.minY * sourceSize.height,
                        width: full.width * sourceSize.width, height: full.height * sourceSize.height))
            }
        }
        return MagicHistoricalScanParser.parse(titleLines: lines(title), footerLines: lines(footer),
            sourceSize: sourceSize, cardRect: cardRect, encounterID: encounterID, snapshot: snapshot)
    }
}

enum MagicEncounterLanguage: String, Codable, Sendable {
    case unknown, corroboratedEnglish, userConfirmedEnglish, conflictingOrNonEnglish
}

/// Title agreement never supplies language evidence. Confirmation is scoped to
/// the encounter carried in this evidence, including only that encounter's retries.
struct MagicHistoricalScanEvidence: Codable, Hashable, Sendable {
    let title: String
    let collectorNumber: String
    let denominator: Int
    var encounterID: UUID
    let profileGeneration: String
    let indexGeneration: String
    let titleBounds: CGRect
    let numberBounds: CGRect
    var language: MagicEncounterLanguage = .unknown
    var languageProvenance: String? = nil

    var permitsEnglishAcquisition: Bool {
        switch language {
        case .unknown, .conflictingOrNonEnglish: return false
        case .userConfirmedEnglish: return languageProvenance == "user:\(encounterID.uuidString)"
        case .corroboratedEnglish:
            // Reserved for reviewed independent OCR sources. Title/provider filters
            // cannot be encoded as a language corroboration source.
            return languageProvenance == "independent-rules-text:\(encounterID.uuidString)"
        }
    }

    func confirmedEnglish() throws -> Self {
        guard language != .conflictingOrNonEnglish else { throw CatalogLookupError.invalidPrintingChoice }
        var result = self
        result.language = .userConfirmedEnglish
        result.languageProvenance = "user:\(encounterID.uuidString)"
        return result
    }

    var hasValidGeometry: Bool {
        Self.valid(titleBounds, title: true) && Self.valid(numberBounds, title: false)
    }
    private static func valid(_ rect: CGRect, title: Bool) -> Bool {
        guard [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite),
              rect.width > 0, rect.height > 0, rect.minX >= 0, rect.maxX <= 1,
              rect.minY >= 0, rect.maxY <= 1 else { return false }
        return title ? rect.midY >= 0.82 && rect.midX < 0.8
            : rect.midY <= 0.12 && rect.midX < 0.79
    }

    func identifier() throws -> ScanIdentifier {
        let data = try JSONEncoder().encode(self)
        // Encounter separation keeps one person's printing/language answer from
        // being reused for the next card with the same name and number.
        return try ScanIdentifier(game: .magic, namespace: "historical",
            fields: [.init(key: "evidence", value: String(decoding: data, as: UTF8.self))],
            displayIdentifier: "\(title) · \(collectorNumber)/\(denominator)",
            suppressionIdentity: "magic-historical:\(profileGeneration):\(MagicHistoricalEvidenceKey.canonicalTitle(title)):\(collectorNumber)/\(denominator)",
            catalogGeneration: MagicCatalogAdapter.providerGeneration)
    }

    static func decode(_ identifier: ScanIdentifier) throws -> Self {
        guard identifier.game == .magic, identifier.namespace == "historical",
              identifier.fields.count == 1, identifier.fields[0].key == "evidence" else {
            throw CatalogLookupError.invalidAdapterOutcome
        }
        let data = Data(identifier.fields[0].value.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["title", "collectorNumber", "denominator", "encounterID",
                "profileGeneration", "indexGeneration", "titleBounds", "numberBounds", "language", "languageProvenance"]) else {
            throw CatalogLookupError.invalidAdapterOutcome
        }
        let evidence = try JSONDecoder().decode(Self.self, from: data)
        guard evidence.title.count >= 4, evidence.title.count <= 100,
              (1...9999).contains(evidence.denominator), !evidence.collectorNumber.isEmpty,
              evidence.collectorNumber.count <= 12, evidence.hasValidGeometry,
              !evidence.profileGeneration.isEmpty, !evidence.indexGeneration.isEmpty,
              (evidence.language == .unknown ? evidence.languageProvenance == nil : evidence.languageProvenance != nil) else {
            throw CatalogLookupError.invalidAdapterOutcome
        }
        return evidence
    }
}

extension ScanIdentifier {
    var needsMagicEnglishConfirmation: Bool {
        if namespace == "historical-live" {
            return (try? MagicHistoricalLiveEvidence.decode(self).englishConfirmed) != true
        }
        guard let evidence = try? MagicHistoricalScanEvidence.decode(self) else { return false }
        return !evidence.permitsEnglishAcquisition
    }
    func confirmingMagicEnglish() throws -> Self {
        if namespace == "historical-live" {
            var evidence = try MagicHistoricalLiveEvidence.decode(self)
            evidence.englishConfirmed = true
            return try evidence.identifier()
        }
        let evidence = try MagicHistoricalScanEvidence.decode(self).confirmedEnglish()
        let identifier = try evidence.identifier()
        return try .init(game: game, namespace: namespace, fields: identifier.fields,
            displayIdentifier: identifier.displayIdentifier, suppressionIdentity: suppressionIdentity,
            catalogGeneration: catalogGeneration)
    }
}

/// Initial reviewed EXO template. Geometry is card-relative in the same oriented
/// source frame. Copyright text can share a line with `1/143`; years, mana costs,
/// rules numerals and right-hand power/toughness cannot supply number evidence.
enum MagicHistoricalScanParser {
    private static let numberRegex = try! NSRegularExpression(pattern: #"(?<![0-9A-Za-z])([0-9]{1,3}[A-Za-z★]?)\s*/\s*([0-9]{1,4})(?![0-9A-Za-z])"#)

    static func plausibleNumber(_ lines: [RecognizedLine]) -> Bool {
        lines.contains { line in
            let text = line.text
            let matches = numberRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            guard matches.count == 1, let totalRange = Range(matches[0].range(at: 2), in: text) else { return false }
            return Int(text[totalRange]) == 143 && line.sourcePixelRect != nil
                && !text.uppercased().contains("HP") && !text.uppercased().hasPrefix("T ")
        }
    }

    static func parse(titleLines: [RecognizedLine], footerLines: [RecognizedLine], sourceSize: CGSize,
                      cardRect: CGRect, encounterID: UUID, snapshot: MagicHistoricalLocalSnapshot) -> MagicHistoricalScanEvidence? {
        guard sourceSize.width > 0, sourceSize.height > 0, cardRect.width > 0, cardRect.height > 0 else { return nil }
        func bounds(_ line: RecognizedLine) -> CGRect? {
            guard let pixels = line.sourcePixelRect else { return nil }
            return CGRect(x: (pixels.minX / sourceSize.width - cardRect.minX) / cardRect.width,
                          y: (pixels.minY / sourceSize.height - cardRect.minY) / cardRect.height,
                          width: pixels.width / sourceSize.width / cardRect.width,
                          height: pixels.height / sourceSize.height / cardRect.height)
        }
        var matches: [MagicHistoricalScanEvidence] = []
        for footer in footerLines {
            guard !footer.text.uppercased().hasPrefix("T "), !footer.text.uppercased().contains("HP"),
                  let numberBounds = bounds(footer) else { continue }
            let text = footer.text
            let readings = numberRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            guard readings.count == 1, let match = readings.first,
                  let numberRange = Range(match.range(at: 1), in: text),
                  let totalRange = Range(match.range(at: 2), in: text),
                  let total = Int(text[totalRange]), total == 143 else { continue }
            let number = String(text[numberRange]).lowercased()
            for title in titleLines {
                guard let titleBounds = bounds(title), title.text.count >= 4,
                      let query = try? snapshot.index.query(title: title.text, collectorNumber: number,
                          profiles: snapshot.profiles, currentSourceContext: nil),
                      query.matchingRecords.contains(where: { $0.setCode == "exo" && $0.visibleCollectorNumber == true }) else { continue }
                let evidence = MagicHistoricalScanEvidence(title: title.text, collectorNumber: number,
                    denominator: total, encounterID: encounterID, profileGeneration: snapshot.generation,
                    indexGeneration: snapshot.index.generation, titleBounds: titleBounds, numberBounds: numberBounds)
                if evidence.hasValidGeometry { matches.append(evidence) }
            }
        }
        // Different readings or spatial objects must never vote themselves unique.
        return matches.count == 1 ? matches.first : nil
    }
}

struct MagicHistoricalCaptureWindow {
    private(set) var encounterID = UUID()
    private var startedAt: TimeInterval?
    private var attempts = 0
    private var first: MagicHistoricalScanEvidence?
    private var consecutive = 0
    var hasPlausibleEvidence: Bool { first != nil }

    mutating func reset() { self = Self() }
    mutating func begin(at now: TimeInterval) -> Bool {
        if let startedAt, now - startedAt > 1.5 { reset() }
        if startedAt == nil { startedAt = now }
        guard attempts < 6 else { return false }
        attempts += 1
        return true
    }
    mutating func observe(_ evidence: MagicHistoricalScanEvidence?) -> ScanIdentifier? {
        guard var evidence else {
            if first != nil { encounterID = UUID() }
            first = nil; consecutive = 0; return nil
        }
        if let first, first.title == evidence.title, first.collectorNumber == evidence.collectorNumber,
           first.denominator == evidence.denominator,
           first.profileGeneration == evidence.profileGeneration,
           first.indexGeneration == evidence.indexGeneration { consecutive += 1 }
        else {
            if first != nil { encounterID = UUID() }
            evidence.encounterID = encounterID
            first = evidence; consecutive = 1
        }
        // Freeze the first same-frame geometry so normal motion cannot change
        // identifier equality while the shared latch confirms subsequent frames.
        return consecutive >= 2 ? try? first?.identifier() : nil
    }
}
