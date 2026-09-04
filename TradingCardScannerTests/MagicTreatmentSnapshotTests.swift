import Foundation
import XCTest
@testable import TradingCardScanner

final class MagicTreatmentSnapshotTests: XCTestCase {
    func testCollectorNumberAuditOnlyAcceptsLettersBoundToNumericStem() {
        XCTAssertEqual(
            MagicTreatmentSnapshotGenerator.collectorNumberSuffix(in: "523b"),
            "b"
        )
        XCTAssertEqual(
            MagicTreatmentSnapshotGenerator.collectorNumberSuffix(in: "0004c"),
            "c"
        )
        XCTAssertEqual(
            MagicTreatmentSnapshotGenerator.collectorNumberSuffix(in: "0078s"),
            "s"
        )
        XCTAssertEqual(
            MagicTreatmentSnapshotGenerator.collectorNumberSuffix(in: "0078p"),
            "p"
        )

        // These are OCR-style formatting or non-numeric schemes, not evidence
        // that the provider assigned a collector-number suffix.
        XCTAssertNil(
            MagicTreatmentSnapshotGenerator.collectorNumberSuffix(in: "523 B")
        )
        XCTAssertNil(
            MagicTreatmentSnapshotGenerator.collectorNumberSuffix(in: "0036 FFVII")
        )
        XCTAssertNil(
            MagicTreatmentSnapshotGenerator.collectorNumberSuffix(in: "1/2")
        )
        XCTAssertNil(
            MagicTreatmentSnapshotGenerator.collectorNumberSuffix(in: "★")
        )
    }

    func testBuilderPreservesSuffixAndTreatmentEvidenceWithoutGuessingRarity() throws {
        let cards = [
            MagicTreatmentSourceCard(
                id: "fin-523b",
                name: "Example Surge Foil",
                setCode: "fin",
                setName: "Final Fantasy",
                collectorNumber: "523b",
                rarity: "rare",
                finishes: ["foil"],
                frameEffects: ["surgefoil"]
            ),
            MagicTreatmentSourceCard(
                id: "neo-0004c",
                name: "Example Neon Ink",
                setCode: "neo",
                setName: "Kamigawa: Neon Dynasty",
                collectorNumber: "0004c",
                finishes: ["foil"],
                promoTypes: ["promo_pack"]
            ),
            MagicTreatmentSourceCard(
                id: "neo-0078s",
                name: "Example Prerelease",
                setCode: "neo",
                setName: "Kamigawa: Neon Dynasty",
                collectorNumber: "0078s",
                promoTypes: ["prerelease"]
            ),
            MagicTreatmentSourceCard(
                id: "neo-0078p",
                name: "Example Promo Pack",
                setCode: "neo",
                setName: "Kamigawa: Neon Dynasty",
                collectorNumber: "0078p",
                promoTypes: ["promo_pack"]
            ),
            MagicTreatmentSourceCard(
                id: "fin-523-space",
                name: "OCR Formatting Example",
                setCode: "fin",
                setName: "Final Fantasy",
                collectorNumber: "523 B"
            ),
            MagicTreatmentSourceCard(
                id: "fin-0036",
                name: "Plain Example",
                setCode: "fin",
                setName: "Final Fantasy",
                collectorNumber: "0036"
            )
        ]
        let source = MagicTreatmentSnapshotSource(
            bulkDataID: "fixture",
            bulkDataType: MagicTreatmentSnapshotVersion.sourceBulkDataType,
            downloadURI: "https://example.com/default-cards.json",
            updatedAt: "2026-09-03T00:00:00Z",
            contentSHA256: "fixture-sha256"
        )

        let snapshot = try MagicTreatmentSnapshotGenerator.makeSnapshot(
            from: cards,
            source: source,
            generatedAt: "2026-09-03T00:00:00Z"
        )

        XCTAssertEqual(snapshot.manifest.totalCardCount, 6)
        XCTAssertEqual(snapshot.manifest.auditedCardCount, 4)

        let fin: MagicTreatmentSnapshotSetEntry = try XCTUnwrap(
            snapshot.manifest.entries.first { $0.code.caseInsensitiveCompare("fin") == .orderedSame }
        )
        XCTAssertEqual(fin.totalCardCount, 3)
        XCTAssertEqual(fin.auditedCardCount, 1)
        XCTAssertEqual(fin.collectorNumberSuffixCounts, ["b": 1])
        XCTAssertEqual(fin.frameEffectCounts, ["surgefoil": 1])
        XCTAssertEqual(fin.promoTypeCounts, [String: Int]())

        let neo: MagicTreatmentSnapshotSetEntry = try XCTUnwrap(
            snapshot.manifest.entries.first { $0.code.caseInsensitiveCompare("neo") == .orderedSame }
        )
        XCTAssertEqual(neo.totalCardCount, 3)
        XCTAssertEqual(neo.auditedCardCount, 3)
        XCTAssertEqual(neo.collectorNumberSuffixCounts, ["c": 1, "p": 1, "s": 1])
        XCTAssertEqual(neo.promoTypeCounts, ["prerelease": 1, "promo_pack": 2])

        let auditedNumbers = snapshot.auditedCards.map { $0.collectorNumber }.sorted()
        XCTAssertEqual(auditedNumbers, ["0004c", "0078p", "0078s", "523b"])
    }

    func testSnapshotRoundTripsThroughManifestAndSetResources() throws {
        let cards = [
            MagicTreatmentSourceCard(
                id: "neo-0004c",
                name: "Example Neon Ink",
                setCode: "neo",
                setName: "Kamigawa: Neon Dynasty",
                collectorNumber: "0004c",
                frameEffects: ["neonink"]
            )
        ]
        let source = MagicTreatmentSnapshotSource(
            bulkDataID: "fixture",
            bulkDataType: MagicTreatmentSnapshotVersion.sourceBulkDataType,
            downloadURI: "fixture",
            updatedAt: nil,
            contentSHA256: "fixture"
        )
        let snapshot = try MagicTreatmentSnapshotGenerator.makeSnapshot(
            from: cards,
            source: source,
            generatedAt: "2026-09-03T00:00:00Z"
        )
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try MagicTreatmentSnapshotGenerator.write(snapshot, to: root)
        let loaded = try MagicTreatmentSnapshotStore.load(from: root)

        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(loaded.cards(forSetCode: "NEO").first?.collectorNumberSuffix, "c")
        XCTAssertEqual(loaded.manifest.source.bulkDataType, "default_cards")
    }

    func testGeneratorReadsScryfallJSONLines() throws {
        let cards = [
            MagicTreatmentSourceCard(
                id: "neo-0004c",
                name: "Example Neon Ink",
                setCode: "neo",
                setName: "Kamigawa: Neon Dynasty",
                collectorNumber: "0004c",
                frameEffects: ["neonink"]
            ),
            MagicTreatmentSourceCard(
                id: "neo-0005",
                name: "Plain Example",
                setCode: "neo",
                setName: "Kamigawa: Neon Dynasty",
                collectorNumber: "0005"
            )
        ]
        var jsonLines = Data()
        let encoder = JSONEncoder()
        for card in cards {
            jsonLines.append(try encoder.encode(card))
            jsonLines.append(0x0A)
        }

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("default-cards.jsonl")
        let output = root.appendingPathComponent("snapshot", isDirectory: true)
        try jsonLines.write(to: input)
        let source = MagicTreatmentSnapshotSource(
            bulkDataID: "fixture",
            bulkDataType: MagicTreatmentSnapshotVersion.sourceBulkDataType,
            downloadURI: "fixture",
            updatedAt: nil,
            contentSHA256: "fixture"
        )

        try MagicTreatmentSnapshotGenerator.generate(
            inputFile: input,
            outputDirectory: output,
            source: source,
            generatedAt: "2026-09-03T00:00:00Z",
            manualMappings: []
        )
        let loaded = try MagicTreatmentSnapshotStore.load(from: output)

        XCTAssertEqual(loaded.manifest.totalCardCount, 2)
        XCTAssertEqual(loaded.manifest.auditedCardCount, 1)
        XCTAssertEqual(loaded.cards(forSetCode: "neo").map(\.id), ["neo-0004c"])
    }

    func testGeneratorReadsLegacyJSONArray() throws {
        let cards = [
            MagicTreatmentSourceCard(
                id: "fin-523b",
                name: "Example Surge Foil",
                setCode: "fin",
                setName: "Final Fantasy",
                collectorNumber: "523b",
                frameEffects: ["surgefoil"]
            )
        ]
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("default-cards.json")
        let output = root.appendingPathComponent("snapshot", isDirectory: true)
        try JSONEncoder().encode(cards).write(to: input)
        let source = MagicTreatmentSnapshotSource(
            bulkDataID: "fixture",
            bulkDataType: MagicTreatmentSnapshotVersion.sourceBulkDataType,
            downloadURI: "fixture",
            updatedAt: nil,
            contentSHA256: "fixture"
        )

        try MagicTreatmentSnapshotGenerator.generate(
            inputFile: input,
            outputDirectory: output,
            source: source,
            generatedAt: "2026-09-03T00:00:00Z",
            manualMappings: []
        )
        let loaded = try MagicTreatmentSnapshotStore.load(from: output)

        XCTAssertEqual(loaded.cards(forSetCode: "FIN").first?.collectorNumber, "523b")
    }

    func testBundledSnapshotIsPresentAndSelfConsistent() throws {
        let bundles = [Bundle.main, Bundle(for: MagicTreatmentSnapshotTests.self)]
        let snapshot = bundles.lazy.compactMap { bundle -> MagicTreatmentSnapshot? in
            try? MagicTreatmentSnapshotStore.bundled(bundle: bundle)
        }.first
        let loaded = try XCTUnwrap(snapshot)

        XCTAssertTrue(loaded.manifest.isSupported)
        XCTAssertGreaterThan(loaded.manifest.totalCardCount, 0)
        XCTAssertGreaterThan(loaded.manifest.entries.count, 100)
        XCTAssertEqual(
            loaded.manifest.source.bulkDataType,
            MagicTreatmentSnapshotVersion.sourceBulkDataType
        )
        XCTAssertFalse(loaded.manifest.source.contentSHA256.isEmpty)
        XCTAssertTrue(
            loaded.manifest.entries.contains {
                $0.code.caseInsensitiveCompare("neo") == .orderedSame
                    && ($0.promoTypeCounts["neonink"] ?? 0) > 0
            }
        )
        XCTAssertTrue(
            loaded.manifest.entries.contains {
                $0.code.caseInsensitiveCompare("fin") == .orderedSame
                    && ($0.promoTypeCounts["surgefoil"] ?? 0) > 0
                    && ($0.collectorNumberSuffixCounts["b"] ?? 0) > 0
            }
        )

        let neonInkCards = loaded.cards(forSetCode: "neo").filter {
            $0.promoTypes.contains("neonink")
        }
        XCTAssertEqual(
            Set(neonInkCards.map { $0.collectorNumber }),
            Set(["429", "430", "431", "432"])
        )
        XCTAssertEqual(Set(neonInkCards.map { $0.id }).count, 4)

        let neonInkMapping = try XCTUnwrap(
            loaded.manifest.manualMappings.first {
                $0.id == "neo-neonink-color"
            }
        )
        XCTAssertEqual(neonInkMapping.setCode, "neo")
        XCTAssertEqual(neonInkMapping.treatment, "neonink")
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: neonInkMapping.cards.map {
                ($0.collectorNumber, $0.value)
            }),
            [
                "429": "red",
                "430": "green",
                "431": "blue",
                "432": "yellow"
            ]
        )
        XCTAssertEqual(
            Set(neonInkMapping.cards.map(\.cardID)),
            Set(neonInkCards.map(\.id))
        )
        XCTAssertEqual(
            neonInkMapping.provenanceURLs,
            [
                "https://media.wizards.com/2022/downloads/card-sets/NEO_Cardlist_02092022.pdf",
                "https://magic.wizards.com/en/news/feature/collecting-kamigawa-neon-dynasty-2022-01-27"
            ]
        )

        let surgeFoilCards = loaded.cards(forSetCode: "fin").filter {
            $0.promoTypes.contains("surgefoil")
        }
        XCTAssertTrue(surgeFoilCards.contains { $0.collectorNumber == "523" })
        XCTAssertTrue(surgeFoilCards.allSatisfy { $0.finishes.contains("foil") })
        XCTAssertGreaterThan(
            loaded.manifest.entries.reduce(0) {
                $0 + ($1.collectorNumberSuffixCounts["s"] ?? 0)
            },
            0
        )
        XCTAssertGreaterThan(
            loaded.manifest.entries.reduce(0) {
                $0 + ($1.collectorNumberSuffixCounts["p"] ?? 0)
            },
            0
        )
    }

#if DEBUG
    /// Developer-only release step. The shell wrapper supplies all metadata;
    /// normal unit-test runs have no input path and remain fully offline.
    func testGenerateMagicTreatmentSnapshotWhenRequested() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let inputPath = environment["MAGIC_TREATMENT_SNAPSHOT_INPUT"],
              !inputPath.isEmpty else { return }
        guard let outputPath = environment["MAGIC_TREATMENT_SNAPSHOT_OUTPUT"],
              !outputPath.isEmpty else {
            return XCTFail("MAGIC_TREATMENT_SNAPSHOT_OUTPUT is required with an input")
        }

        let source = MagicTreatmentSnapshotSource(
            bulkDataID: environment["MAGIC_TREATMENT_SNAPSHOT_BULK_ID"] ?? "unknown",
            bulkDataType: environment["MAGIC_TREATMENT_SNAPSHOT_BULK_TYPE"]
                ?? MagicTreatmentSnapshotVersion.sourceBulkDataType,
            downloadURI: environment["MAGIC_TREATMENT_SNAPSHOT_DOWNLOAD_URI"] ?? "unknown",
            updatedAt: environment["MAGIC_TREATMENT_SNAPSHOT_UPDATED_AT"],
            contentSHA256: environment["MAGIC_TREATMENT_SNAPSHOT_SHA256"] ?? "unknown"
        )
        try MagicTreatmentSnapshotGenerator.generate(
            inputFile: URL(fileURLWithPath: inputPath),
            outputDirectory: URL(fileURLWithPath: outputPath, isDirectory: true),
            source: source,
            generatedAt: environment["MAGIC_TREATMENT_SNAPSHOT_GENERATED_AT"]
                ?? "2026-09-03T00:00:00Z"
        )

        let generated = try MagicTreatmentSnapshotStore.load(
            from: URL(fileURLWithPath: outputPath, isDirectory: true)
        )
        XCTAssertEqual(generated.manifest.source, source)
        XCTAssertGreaterThan(generated.manifest.totalCardCount, 0)
        XCTAssertFalse(generated.manifest.entries.isEmpty)
    }
#endif

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
