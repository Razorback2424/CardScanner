import Foundation
import CryptoKit
import UIKit

// Production entry point, native-coordinate outputs, no supplied reference or
// annotation. Interim holdouts stay excluded until the candidate is frozen.
struct CorpusManifest: Decodable {
    struct Entry: Decodable { let file: String; let split: String; let sha256: String }
    let entries: [Entry]
}
struct CorpusRow: Codable {
    let fixture: String
    let file: String
    let split: String
    let inputSHA256: String
    var error: String?
    var actualOuter: CardCenteringQuad?
    var actualInner: CardCenteringQuad?
    var width: Double?
    var height: Double?
    var leftShare: Double?
    var topShare: Double?
    var canReportRatios: Bool?
    var notes: [String]?
    var elapsedSeconds: Double?
}
guard CommandLine.arguments.count == 4 else {
    fatalError("usage: corpus MANIFEST_JSON IMAGE_DIRECTORY OUTPUT_DIRECTORY")
}
let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1])
let imageDirectory = URL(fileURLWithPath: CommandLine.arguments[2])
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[3])
let manifest = try JSONDecoder().decode(CorpusManifest.self, from: Data(contentsOf: manifestURL))
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let outputURL = outputDirectory.appendingPathComponent("production-corpus.json")
guard !FileManager.default.fileExists(atPath: outputURL.path) else {
    fatalError("Refusing to overwrite an existing corpus receipt")
}
let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
var rows: [CorpusRow] = []
for entry in manifest.entries.filter({ $0.split.hasPrefix("DEV") }) {
    try autoreleasepool {
        let inputURL = imageDirectory.appendingPathComponent(entry.file)
        let data = try Data(contentsOf: inputURL)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hash == entry.sha256 else { fatalError("Input hash mismatch: \(entry.file)") }
        var row = CorpusRow(fixture: inputURL.deletingPathExtension().lastPathComponent,
                            file: entry.file, split: entry.split, inputSHA256: hash)
        let started = Date()
        do {
            let result = try CardCenteringAnalyzer.analyze(data)
            let m = result.measurement
            if let mapping = result.coordinateMapping {
                row.actualOuter = mapping.nativeQuad(fromWorking: m.geometryOuterQuad)
                row.actualInner = m.geometryInnerQuad.map(mapping.nativeQuad(fromWorking:))
                row.width = mapping.orientedSourceSize.width
                row.height = mapping.orientedSourceSize.height
            } else { row.error = "missing native coordinate mapping" }
            if m.geometryInnerQuad != nil {
                row.leftShare = 100 * m.leftBorderDistance / (m.leftBorderDistance + m.rightBorderDistance)
                row.topShare = 100 * m.topBorderDistance / (m.topBorderDistance + m.bottomBorderDistance)
            }
            row.canReportRatios = m.canReportRatios
            row.notes = m.detectionNotes
        } catch { row.error = String(describing: error) }
        row.elapsedSeconds = Date().timeIntervalSince(started)
        rows.append(row)
        try encoder.encode(rows).write(to: outputURL, options: .atomic)
        print("\(entry.file): error=\(row.error ?? "none") inner=\(row.actualInner != nil) LR=\(row.leftShare ?? -1) TB=\(row.topShare ?? -1)")
        fflush(stdout)
    }
}
print("Saved \(rows.count) production results; accuracy remains unscored without reviewed references.")
