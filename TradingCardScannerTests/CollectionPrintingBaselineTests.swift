import Foundation
import OnePieceCatalogCore
import XCTest
@testable import TradingCardScanner

/// A saved collection row is keyed by its printing ID. Any catalog change,
/// including a delivery-format migration, must keep every printing that a
/// collection could already hold resolvable, or that row is orphaned.
///
/// The baseline files list every holdable printing at the time they were
/// recorded. Additions are fine; a missing ID fails. To record a reviewed
/// baseline after an intended change, run this class with
/// `RECORD_COLLECTION_PRINTING_BASELINE=1` in the scheme's test environment,
/// and pair it with a `scripts/catalog_parity.py` approval.
@MainActor
final class CollectionPrintingBaselineTests: XCTestCase {
    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("TestFixtures/CollectionPrintingBaseline", isDirectory: true)

    func testEveryYuGiOhPrintingACollectionCouldHoldStillResolves() throws {
        let catalog = YuGiOhCatalog.bundledHandle
        let adapter = YuGiOhCatalogAdapter(catalog: catalog)
        try check("yugioh", ids: catalog.printingByID.keys) { try adapter.resolution(forPrintingID: $0) }
    }

    func testEveryLorcanaPrintingACollectionCouldHoldStillResolves() throws {
        let registry = try LorcanaDiscoveryCatalog.bundledMarket.get().registry
        let physical = try XCTUnwrap(registry.physicalCatalog)
        let adapter = LorcanaCatalogAdapter(registry: registry)
        try check("lorcana", ids: physical.printingByID.keys) { try adapter.resolution(forPrintingID: $0) }
    }

    func testEveryOnePiecePrintingACollectionCouldHoldStillResolves() throws {
        let configuration = try OnePieceCatalogBootstrapConfiguration.configured(bundle: .main)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "one-piece-catalog-release", withExtension: "json"))
        let envelope = try JSONDecoder().decode(OnePieceCatalogReleaseEnvelope.self, from: Data(contentsOf: url))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnePieceBaseline-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try OnePieceCatalogReleaseStore(root: root, keys: configuration.keys, bundledEnvelope: envelope)
        let registry = try XCTUnwrap(store.bundledRegistry)
        let adapter = OnePieceCatalogAdapter(registry: registry)
        try check("one-piece", ids: registry.printingByID.keys) { try adapter.resolution(forPrintingID: $0) }
    }

    /// Resolves through the same entry point stored-printing refresh and
    /// Browse/import use, so "holdable" means what the collection relies on.
    private func check(_ game: String, ids: some Collection<UUID>,
                       resolve: (UUID) throws -> CardCatalog.CatalogResolution) throws {
        let holdable = Set(ids.filter { (try? resolve($0)) != nil }.map { $0.uuidString.lowercased() })
        XCTAssertFalse(holdable.isEmpty, "\(game): no printing resolves")
        let file = Self.directory.appendingPathComponent("\(game).txt.zlib")
        if ProcessInfo.processInfo.environment["RECORD_COLLECTION_PRINTING_BASELINE"] == "1" {
            let text = Data((holdable.sorted().joined(separator: "\n") + "\n").utf8)
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try (text as NSData).compressed(using: .zlib).write(to: file, options: .atomic)
            return
        }
        let compressed = try Data(contentsOf: file)
        let text = try String(decoding: (compressed as NSData).decompressed(using: .zlib) as Data, as: UTF8.self)
        let baseline = Set(text.split(separator: "\n").map(String.init))
        XCTAssertFalse(baseline.isEmpty, "\(game): empty baseline")
        let orphaned = baseline.subtracting(holdable).sorted()
        XCTAssertTrue(orphaned.isEmpty, """
            \(game): \(orphaned.count) of \(baseline.count) previously holdable printings no longer resolve, \
            which would orphan saved collection rows. First: \(orphaned.prefix(10).joined(separator: ", "))
            """)
    }
}
