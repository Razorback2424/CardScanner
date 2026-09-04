import Darwin
import Foundation

@main
struct MagicTreatmentSnapshotGeneratorMain {
    static func main() {
        let environment = ProcessInfo.processInfo.environment

        func requiredEnvironmentValue(_ key: String) -> String {
            guard let value = environment[key], !value.isEmpty else {
                fputs("Missing required environment variable: \(key)\n", stderr)
                exit(EXIT_FAILURE)
            }
            return value
        }

        let inputFile = URL(
            fileURLWithPath: requiredEnvironmentValue("MAGIC_TREATMENT_SNAPSHOT_INPUT")
        )
        let outputDirectory = URL(
            fileURLWithPath: requiredEnvironmentValue("MAGIC_TREATMENT_SNAPSHOT_OUTPUT"),
            isDirectory: true
        )
        let source = MagicTreatmentSnapshotSource(
            bulkDataID: requiredEnvironmentValue("MAGIC_TREATMENT_SNAPSHOT_BULK_ID"),
            bulkDataType: environment["MAGIC_TREATMENT_SNAPSHOT_BULK_TYPE"]
                ?? MagicTreatmentSnapshotVersion.sourceBulkDataType,
            downloadURI: requiredEnvironmentValue("MAGIC_TREATMENT_SNAPSHOT_DOWNLOAD_URI"),
            updatedAt: environment["MAGIC_TREATMENT_SNAPSHOT_UPDATED_AT"],
            contentSHA256: requiredEnvironmentValue("MAGIC_TREATMENT_SNAPSHOT_SHA256")
        )

        do {
            try MagicTreatmentSnapshotGenerator.generate(
                inputFile: inputFile,
                outputDirectory: outputDirectory,
                source: source,
                generatedAt: environment["MAGIC_TREATMENT_SNAPSHOT_GENERATED_AT"]
                    ?? "2026-09-03T00:00:00Z"
            )
        } catch {
            fputs("Could not generate Magic treatment snapshot: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
