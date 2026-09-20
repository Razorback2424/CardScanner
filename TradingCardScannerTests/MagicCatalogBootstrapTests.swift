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
        XCTAssertEqual(registry.scannerDefinitions.count, 353)
        XCTAssertEqual(registry.browseSets.count, 662)
        XCTAssertEqual(
            registry.childSetsByParentCode.values.reduce(0) { $0 + $1.count },
            247
        )
        XCTAssertNotNil(registry.descriptor(forCode: "SLZ"))
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
