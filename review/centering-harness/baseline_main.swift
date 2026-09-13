import Foundation
import UIKit

let dir = "/Users/seankeller/Documents/TradingCardScannerMVP_fixed_v4/TestFixtures/TradingCards/HEIC"
let outDir = ProcessInfo.processInfo.environment["OUT_DIR"] ?? "/tmp/centering-baseline"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

struct Row: Codable {
    var file: String
    var ok: Bool
    var error: String?
    var imageW: Int?
    var imageH: Int?
    var outerL: Int?; var outerT: Int?; var outerR: Int?; var outerB: Int?
    var innerL: Int?; var innerT: Int?; var innerR: Int?; var innerB: Int?
    var lB: Int?; var rB: Int?; var tB: Int?; var bB: Int?
    var lr: String?; var tb: String?
    var appliedRotation: Double?
    var notes: [String]?
    var warnings: [String]?
    var elapsedMs: Double?
}

var rows: [Row] = []
let files = (try! FileManager.default.contentsOfDirectory(atPath: dir)).filter { $0.hasSuffix(".HEIC") }.sorted()
for f in files {
    let url = URL(fileURLWithPath: dir).appendingPathComponent(f)
    let data = try! Data(contentsOf: url)
    var row = Row(file: f, ok: false)
    let t0 = Date()
    do {
        let r = try CardCenteringAnalyzer.analyze(data)
        let m = r.measurement
        row.ok = true
        row.imageW = m.imageWidth; row.imageH = m.imageHeight
        row.outerL = m.outer.left; row.outerT = m.outer.top; row.outerR = m.outer.right; row.outerB = m.outer.bottom
        row.innerL = m.inner.left; row.innerT = m.inner.top; row.innerR = m.inner.right; row.innerB = m.inner.bottom
        row.lB = m.leftBorder; row.rB = m.rightBorder; row.tB = m.topBorder; row.bB = m.bottomBorder
        row.lr = m.leftRightCentering; row.tb = m.topBottomCentering
        row.appliedRotation = r.appliedRotationDegrees
        row.notes = m.detectionNotes; row.warnings = m.warnings
        // dump the prepared image with guides for visual review
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = true
        let annotated = UIGraphicsImageRenderer(size: r.image.size, format: fmt).image { ctx in
            r.image.draw(at: .zero)
            let cg = ctx.cgContext
            cg.setLineWidth(2)
            cg.setStrokeColor(UIColor.red.cgColor)
            cg.stroke(CGRect(x: m.outer.left, y: m.outer.top, width: m.outer.right - m.outer.left, height: m.outer.bottom - m.outer.top))
            cg.setStrokeColor(UIColor.cyan.cgColor)
            cg.stroke(CGRect(x: m.inner.left, y: m.inner.top, width: m.inner.right - m.inner.left, height: m.inner.bottom - m.inner.top))
        }
        try? annotated.pngData()?.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(f.replacingOccurrences(of: ".HEIC", with: "_annotated.png")))
        try? r.image.pngData()?.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(f.replacingOccurrences(of: ".HEIC", with: "_prepared.png")))
    } catch {
        row.error = "\(error)"
    }
    row.elapsedMs = Date().timeIntervalSince(t0) * 1000
    rows.append(row)
    print("\(f) ok=\(row.ok) outer=(\(row.outerL ?? -1),\(row.outerT ?? -1),\(row.outerR ?? -1),\(row.outerB ?? -1)) img=\(row.imageW ?? -1)x\(row.imageH ?? -1) rot=\(row.appliedRotation ?? -999) LR=\(row.lr ?? "-") TB=\(row.tb ?? "-") ms=\(Int(row.elapsedMs ?? 0))")
    if let n = row.notes, !n.isEmpty { print("   notes: \(n)") }
}
let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
try! enc.encode(rows).write(to: URL(fileURLWithPath: outDir).appendingPathComponent("baseline.json"))
print("WROTE \(outDir)/baseline.json")
