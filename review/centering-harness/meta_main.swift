import Foundation
import UIKit

guard let dir = CommandLine.arguments.dropFirst().first else {
    fatalError("usage: meta <fixture-directory>")
}

func render(_ img: UIImage, rotateDeg: Double, mirror: Bool) -> Data {
    let size = img.size
    let rad = CGFloat(rotateDeg * .pi / 180)
    let bounds = CGRect(origin: .zero, size: size).applying(CGAffineTransform(rotationAngle: rad)).standardized
    let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = true
    return UIGraphicsImageRenderer(size: bounds.size, format: fmt).image { ctx in
        UIColor(white: 0.93, alpha: 1).setFill()
        ctx.fill(CGRect(origin: .zero, size: bounds.size))
        let cg = ctx.cgContext
        cg.translateBy(x: bounds.width/2, y: bounds.height/2)
        cg.rotate(by: rad)
        if mirror { cg.scaleBy(x: -1, y: 1) }
        img.draw(in: CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height))
    }.pngData()!
}

func ratios(_ d: Data) -> (Double, Double, String, Double, [Int])? {
    guard let r = try? CardCenteringAnalyzer.analyze(d) else { return nil }
    let m = r.measurement
    let lr = Double(m.leftBorder) / Double(max(1, m.leftBorder + m.rightBorder)) * 100
    let tb = Double(m.topBorder) / Double(max(1, m.topBorder + m.bottomBorder)) * 100
    return (lr, tb, m.detectionNotes.isEmpty ? "clean" : "NOTE", r.appliedRotationDegrees,
            [m.leftBorder, m.rightBorder, m.topBorder, m.bottomBorder])
}

let files = (try! FileManager.default.contentsOfDirectory(atPath: dir)).filter { $0.hasSuffix(".HEIC") }.sorted()
print("file,variant,LR%,TB%,L,R,T,B,autoRot,flag")
for f in files {
    let data = try! Data(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent(f))
    guard let img = UIImage(data: data) else { continue }
    let cases: [(String, Double, Bool)] = [
        ("base", 0, false), ("rot+3", 3, false), ("rot-3", -3, false),
        ("rot+90", 90, false), ("rot+180", 180, false), ("mirrorX", 0, true)
    ]
    for (name, deg, mir) in cases {
        let d = name == "base" ? data : render(img, rotateDeg: deg, mirror: mir)
        if let (lr, tb, flag, rot, b) = ratios(d) {
            print(String(format: "%@,%@,%.1f,%.1f,%d,%d,%d,%d,%.2f,%@", f, name, lr, tb, b[0], b[1], b[2], b[3], rot, flag))
        } else {
            print("\(f),\(name),ERROR,,,,,,,")
        }
    }
}
