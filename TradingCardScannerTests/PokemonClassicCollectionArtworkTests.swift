import Foundation
import XCTest
@testable import TradingCardScanner

@MainActor
final class PokemonClassicCollectionArtworkTests: XCTestCase {
    func testClassicCollectionRebuildPreservesAllProviderNumbersAndArtworkAfterReload() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClassicCollectionArtwork-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Use all 25 retained identities, including Birthday Pikachu. The
        // historical scanner's 24 reviewed fractions are not the Browse list.
        let bundled = PokemonChecklistStore(root: root.appendingPathComponent("empty"), bundle: .main)
        let entries = await bundled.mergedEntries()
        let recorded = try XCTUnwrap(entries.first { $0.providerID == "cel25cc" })
        let loaded = await bundled.mergedChecklist(for: recorded.set.catalogID)
        let retained = try XCTUnwrap(loaded)
        let expectedNumbers = Set((1...25).map { String(format: "CC%03d", $0) })
        XCTAssertEqual(retained.count, 25)
        XCTAssertEqual(Set(retained.map(\.collectorNumber)), expectedNumbers)
        XCTAssertEqual(recorded.set.code, "CEL")

        let count: [String: Int] = ["total": 25, "official": 25, "normal": 0, "holo": 25, "reverse": 0]
        let directoryRow: TCGdexBrowseSet = try decode([
            "id": "cel25cc", "name": recorded.set.name,
            "tcgOnline": recorded.set.code, "cardCount": count
        ])
        let base = try XCTUnwrap(PokemonMasterSetChecklistBuilder.baseSets(
            from: [directoryRow], registry: .bundledSeed
        ).first)
        let provider: TCGdexSetCatalog = try decode([
            "id": "cel25cc", "name": recorded.set.name,
            "tcgOnline": recorded.set.code, "cardCount": count,
            "cards": retained.map {
                ["id": $0.providerID, "localId": $0.collectorNumber, "name": $0.name]
            }
        ])
        var details: [String: TCGdexCard] = [:]
        for summary in retained {
            XCTAssertEqual(summary.masterSetVariant, .holo)
            let card: TCGdexCard = try decode([
                "id": summary.providerID, "localId": summary.collectorNumber, "name": summary.name,
                "set": ["id": "cel25cc", "name": recorded.set.name, "cardCount": count],
                "variants": ["firstEdition": false, "normal": false, "holo": true,
                    "reverse": false, "wPromo": false]
            ])
            XCTAssertNil(card.image)
            XCTAssertNil(card.recoveredArtwork)
            XCTAssertNil(card.highImageURL)
            details[card.id] = card
        }

        let rebuilt = try PokemonMasterSetChecklistBuilder.build(
            providerSet: provider, baseSet: base, cardDetails: details
        )
        XCTAssertEqual(rebuilt.count, 1)
        let built = try XCTUnwrap(rebuilt.first)
        XCTAssertEqual(built.standardSlotCount, 25)
        XCTAssertEqual(built.expandedSlotCount, 25)
        try assertClassicArtwork(cards: built.cards, set: built.set)

        let downloadedRoot = root.appendingPathComponent("downloaded", isDirectory: true)
        let writer = PokemonChecklistStore(root: downloadedRoot, bundle: nil)
        try await writer.publish(.from(builtSets: rebuilt))

        // A fresh store, without the bundled fallback, must retain both the
        // provider's CC### numbering and the artwork authorization on disk.
        let reader = PokemonChecklistStore(root: downloadedRoot, bundle: nil)
        let downloaded = await reader.downloadedSnapshot()
        let reloaded = try XCTUnwrap(downloaded)
        XCTAssertEqual(reloaded.manifest.entries.count, 1)
        let entry = try XCTUnwrap(reloaded.entry(forProviderID: "cel25cc"))
        XCTAssertEqual(entry.officialCount, 25)
        XCTAssertEqual(entry.standardSlotCount, 25)
        XCTAssertEqual(entry.expandedSlotCount, 25)
        let cards = try XCTUnwrap(reloaded.checklist(for: entry.set.catalogID))
        XCTAssertEqual(cards, built.cards)
        try assertClassicArtwork(cards: cards, set: entry.set)
    }

    func testClassicCollectionFallbackRespectsExplicitArtworkDenial() {
        for prefersFullSize in [false, true] {
            let source = CatalogCardArtworkSource(
                game: .pokemon, setCode: "CEL", collectorNumber: "CC001",
                thumbnailURL: nil, imageURL: nil, prefersFullSize: prefersFullSize,
                limitlessArtworkAuthorized: false, providerID: "cel25cc-CC001", providerSetID: "cel25cc"
            )
            XCTAssertNil(source.primaryURL)
            XCTAssertTrue(source.fallbacks.isEmpty)
        }
    }

    private func assertClassicArtwork(cards: [CatalogCardSummary], set: CatalogSet,
                                      file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(set.providerID, "cel25cc", file: file, line: line)
        XCTAssertEqual(set.code, "CEL", file: file, line: line)
        XCTAssertEqual(set.cardCount, 25, file: file, line: line)
        XCTAssertEqual(set.limitlessArtworkAuthorized, true, file: file, line: line)
        XCTAssertNil(set.cardArtwork, file: file, line: line)
        XCTAssertNil(set.artworkFallbackURLs, file: file, line: line)
        XCTAssertEqual(cards.count, 25, file: file, line: line)
        XCTAssertEqual(Set(cards.map(\.providerID)).count, 25, file: file, line: line)
        for number in 1...25 {
            let collector = String(format: "CC%03d", number)
            let card = try XCTUnwrap(cards.first { $0.collectorNumber == collector }, file: file, line: line)
            XCTAssertEqual(card.providerID, "cel25cc-" + collector, file: file, line: line)
            XCTAssertEqual(card.setID.providerID, "cel25cc", file: file, line: line)
            XCTAssertEqual(card.setCode, "CEL", file: file, line: line)
            XCTAssertEqual(card.limitlessArtworkAuthorized, true, file: file, line: line)
            XCTAssertNil(card.thumbnailURL, file: file, line: line)
            XCTAssertNil(card.imageURL, file: file, line: line)
            for prefersFullSize in [false, true] {
                let source = CatalogCardArtworkSource(
                    game: card.game, setCode: card.setCode, collectorNumber: card.collectorNumber,
                    thumbnailURL: card.thumbnailURL, imageURL: card.imageURL, prefersFullSize: prefersFullSize,
                    limitlessArtworkAuthorized: card.limitlessArtworkAuthorized,
                    providerID: card.providerID, providerSetID: card.setID.providerID
                )
                let suffix = prefersFullSize ? ".png" : "_XS.png"
                XCTAssertEqual(source.primaryURL?.absoluteString,
                    "https://limitlesstcg.nyc3.cdn.digitaloceanspaces.com/tpci/CEL/CEL_CC\(number)_R_EN" + suffix,
                    file: file, line: line)
            }
        }
    }

    private func decode<Value: Decodable>(_ object: [String: Any]) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
