import Foundation
import UIKit

struct REQ050ParameterPoint: Codable {
    let id: String
    let parameters: CardCenteringAnalyzer.NumericalParameters
}

struct REQ050FixtureSensitivityRecord: Codable {
    let fixture: String
    let sampleCount: Int
    let confidentCount: Int
    let declinedCount: Int
    let failedCount: Int
    let lrMean: Double?
    let lrSigma: Double?
    let lrMinimum: Double?
    let lrMaximum: Double?
    let lrRange: Double?
    let tbMean: Double?
    let tbSigma: Double?
    let tbMinimum: Double?
    let tbMaximum: Double?
    let tbRange: Double?
}

struct REQ050SensitivityArtifact: Codable {
    let schema: Int
    let analyzer: String
    let workingMaxDimension: Int
    let parameterGrid: [REQ050ParameterPoint]
    let records: [REQ050FixtureSensitivityRecord]
}

guard let fixtureDirectoryPath = CommandLine.arguments.dropFirst().first else {
    fatalError("usage: centering-sensitivity <fixture-directory> [output-directory]")
}

let fixtureDirectory = URL(fileURLWithPath: fixtureDirectoryPath, isDirectory: true)
let outputDirectory: URL = {
    if let path = CommandLine.arguments.dropFirst(2).first {
        return URL(fileURLWithPath: path, isDirectory: true)
    }
    return fixtureDirectory
        .deletingLastPathComponent()
        .appendingPathComponent("REQ-050", isDirectory: true)
}()
try! FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let base = CardCenteringAnalyzer.NumericalParameters.productionDefaults
let scalarSmoothingRadii = [1, 3]
let scalarPeakThresholdFractions = [0.08, 0.20]
let profileRadii = [0.0010, 0.0020]
let profileThresholdFloors = [2.0, 3.0]
var parameterGrid = [REQ050ParameterPoint(id: "baseline", parameters: base)]
for smoothingRadius in scalarSmoothingRadii {
    for peakThresholdFraction in scalarPeakThresholdFractions {
        for profileRadius in profileRadii {
            for profileThresholdFloor in profileThresholdFloors {
                let id = String(
                    format: "smooth-%d_peak-%.2f_radius-%.4f_floor-%.1f",
                    smoothingRadius,
                    peakThresholdFraction,
                    profileRadius,
                    profileThresholdFloor
                )
                parameterGrid.append(
                    REQ050ParameterPoint(
                        id: id,
                        parameters: base.replacing(
                            scalarSmoothingRadius: smoothingRadius,
                            scalarPeakThresholdFraction: peakThresholdFraction,
                            profileRadiusNormalized: profileRadius,
                            profileThresholdFloor: profileThresholdFloor
                        )
                    )
                )
            }
        }
    }
}

func ratioValues(_ measurement: CardCenteringMeasurement) -> (lr: Double, tb: Double)? {
    guard measurement.geometryInnerQuad != nil else { return nil }
    let left = measurement.leftBorderDistance
    let right = measurement.rightBorderDistance
    let top = measurement.topBorderDistance
    let bottom = measurement.bottomBorderDistance
    let horizontalTotal = left + right
    let verticalTotal = top + bottom
    guard [left, right, top, bottom, horizontalTotal, verticalTotal].allSatisfy(\.isFinite),
          horizontalTotal > .ulpOfOne,
          verticalTotal > .ulpOfOne else {
        return nil
    }
    return (
        lr: 100 * left / horizontalTotal,
        tb: 100 * top / verticalTotal
    )
}

func statistics(_ values: [Double]) -> (mean: Double, sigma: Double, minimum: Double, maximum: Double, range: Double)? {
    guard !values.isEmpty,
          let minimum = values.min(),
          let maximum = values.max() else {
        return nil
    }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.reduce(0) { total, value in
        let delta = value - mean
        return total + delta * delta
    } / Double(values.count)
    return (mean, sqrt(variance), minimum, maximum, maximum - minimum)
}

let imageExtensions = Set(["heic", "png", "jpg", "jpeg"])
let files = try! FileManager.default.contentsOfDirectory(
    at: fixtureDirectory,
    includingPropertiesForKeys: nil,
    options: [.skipsHiddenFiles]
).filter { imageExtensions.contains($0.pathExtension.lowercased()) }
.sorted { $0.lastPathComponent < $1.lastPathComponent }

var records: [REQ050FixtureSensitivityRecord] = []
for file in files {
    let data = try! Data(contentsOf: file)
    var lrValues: [Double] = []
    var tbValues: [Double] = []
    var confidentCount = 0
    var declinedCount = 0
    var failedCount = 0

    for point in parameterGrid {
        do {
            let analysis = try CardCenteringAnalyzer.analyzeForSensitivity(
                data,
                parameters: point.parameters
            )
            if analysis.measurement.confidence.state == .confident {
                confidentCount += 1
            } else {
                declinedCount += 1
            }
            if let ratios = ratioValues(analysis.measurement) {
                lrValues.append(ratios.lr)
                tbValues.append(ratios.tb)
            }
        } catch {
            failedCount += 1
        }
    }

    let lr = statistics(lrValues)
    let tb = statistics(tbValues)
    records.append(
        REQ050FixtureSensitivityRecord(
            fixture: file.lastPathComponent,
            sampleCount: parameterGrid.count,
            confidentCount: confidentCount,
            declinedCount: declinedCount,
            failedCount: failedCount,
            lrMean: lr?.mean,
            lrSigma: lr?.sigma,
            lrMinimum: lr?.minimum,
            lrMaximum: lr?.maximum,
            lrRange: lr?.range,
            tbMean: tb?.mean,
            tbSigma: tb?.sigma,
            tbMinimum: tb?.minimum,
            tbMaximum: tb?.maximum,
            tbRange: tb?.range
        )
    )
    print(
        "REQ-050 fixture=\(file.lastPathComponent) samples=\(parameterGrid.count) "
            + "confident=\(confidentCount) declined=\(declinedCount) failed=\(failedCount) "
            + String(format: "LRσ=%.5f TBσ=%.5f", lr?.sigma ?? .nan, tb?.sigma ?? .nan)
    )
}

let artifact = REQ050SensitivityArtifact(
    schema: 1,
    analyzer: "CardCenteringAnalyzer.analyzeForSensitivity",
    workingMaxDimension: 1_200,
    parameterGrid: parameterGrid,
    records: records
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try! encoder.encode(artifact).write(
    to: outputDirectory.appendingPathComponent("numerical-sensitivity.json"),
    options: .atomic
)

func formatted(_ value: Double?) -> String {
    value.map { String(format: "%.5f", $0) } ?? "—"
}

var markdown = [
    "# REQ-050 numerical-parameter sensitivity",
    "",
    "The analyzer ran at the production 1200-pixel working cap for every image in the supplied corpus directory.",
    "The parameter grid is injected through `NumericalParameters`; production defaults are not edited.",
    "σ is the population standard deviation across numerical perturbations, not an accuracy estimate.",
    "",
    "## Parameter grid",
    "",
    "| ID | Smoothing radius | Scalar peak fraction | Profile radius | Profile threshold floor |",
    "|---|---:|---:|---:|---:|"
]
for point in parameterGrid {
    let p = point.parameters
    markdown.append(
        String(
            format: "| `%@` | %d | %.3f | %.4f | %.2f |",
            point.id,
            p.scalarSmoothingRadius,
            p.scalarPeakThresholdFraction,
            p.profileRadiusNormalized,
            p.profileThresholdFloor
        )
    )
}
markdown.append(contentsOf: [
    "",
    "## Per-fixture statistics",
    "",
    "| Fixture | Samples | Confident | Declined | Failed | LR mean | LR σ | LR range | TB mean | TB σ | TB range |",
    "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"
])
for record in records {
    markdown.append(
        "| `\(record.fixture)` | \(record.sampleCount) | \(record.confidentCount) | \(record.declinedCount) | \(record.failedCount) | "
            + "\(formatted(record.lrMean)) | \(formatted(record.lrSigma)) | \(formatted(record.lrRange)) | "
            + "\(formatted(record.tbMean)) | \(formatted(record.tbSigma)) | \(formatted(record.tbRange)) |"
    )
}
try! Data((markdown.joined(separator: "\n") + "\n").utf8).write(
    to: outputDirectory.appendingPathComponent("numerical-sensitivity.md"),
    options: .atomic
)
