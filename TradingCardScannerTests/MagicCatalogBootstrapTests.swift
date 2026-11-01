import XCTest
@testable import TradingCardScanner

final class MagicCatalogBootstrapTests: XCTestCase {
    func testBundledSeedPreservesLegacyScannerVocabulary() {
        let registry = MagicCatalogRegistry.bundledSeed
        let actual = Dictionary(
            registry.scannerDefinitions.map { ($0.code.lowercased(), $0.printedSize) },
            uniquingKeysWith: { first, _ in first }
        )

        for definition in MagicSetSnapshot.definitions {
            XCTAssertEqual(
                actual[definition.code.lowercased()],
                definition.printedSize,
                "Legacy scanner definition (definition.code) drifted in Magic rev1 seed"
            )
        }
        XCTAssertEqual(Set(MagicSetSnapshot.definitions.map { $0.code.lowercased() }), Set(actual.keys),
            "A scan-enabled seed release must also be available before the live refresh")
        XCTAssertEqual(registry.scannerDefinitions.count, 353)
        XCTAssertEqual(registry.browseSets.count, 662)
        XCTAssertEqual(
            registry.childSetsByParentCode.values.reduce(0) { $0 + $1.count },
            247
        )
        XCTAssertNotNil(registry.descriptor(forCode: "SLZ"))
    }

    func testCompiledVocabularyRecognizesTheReviewedZetaFooter() throws {
        let definition = try XCTUnwrap(MagicSetSnapshot.definitions.first { $0.code == "SLZ" })
        XCTAssertNil(definition.printedSize, "The provider's card count is not a printed denominator")
        let profile = MagicScanProfile(definitions: MagicSetSnapshot.definitions)
        XCTAssertEqual(profile.parse(["C 0001", "SLZ • EN"]),
            .magic(setCode: "SLZ", collectorNumber: "1", language: "en"))
        XCTAssertNil(profile.parse(["C 0001", "SLZ FR"]))
    }

    func testBundledSeedRoutesTokenAndArtCardChildrenFromOneRegistry() {
        let registry = MagicCatalogRegistry.bundledSeed

        XCTAssertEqual(
            registry.child(for: .token, parentCode: "TRK")?.code,
            "TTRK"
        )
        XCTAssertEqual(
            registry.child(for: .artCard, parentCode: "MSH")?.code,
            "AMSH"
        )
    }
}
