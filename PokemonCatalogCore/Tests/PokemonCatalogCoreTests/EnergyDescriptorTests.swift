import Foundation
import XCTest
@testable import PokemonCatalogCore

final class EnergyDescriptorTests: XCTestCase {
    func testExplicitMEEOverrideBuildsAndRefreshesEnergyAuthority() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        struct Primary: Decodable { let set: PokemonCatalogProviderSet; let cards: [PokemonCatalogProviderCard] }
        let fixture = try JSONDecoder().decode(Primary.self, from: Data(contentsOf:
            root.appendingPathComponent("publisher/fixtures/mee-primary.json")))
        let inputs = try JSONDecoder().decode(PokemonCatalogHumanInputFile.self, from: Data(contentsOf:
            root.appendingPathComponent("publisher/catalog-input.json")))
        let input = try XCTUnwrap(inputs.sets.first { $0.providerSetID == "mee" })
        let row = PokemonCatalogProviderDirectoryRow(id: "mee", name: fixture.set.name,
            cardCount: fixture.set.cardCount, releaseDate: fixture.set.releaseDate)
        let evidence = PokemonCatalogProviderFixture(directory: [row], sets: [fixture.set], cards: fixture.cards)
        let first = try PokemonCatalogBuilder().build(.init(fixture: evidence,
            humanInputs: [input], revision: 1, generatedAt: Date(timeIntervalSince1970: 1_792_368_000)))
        let descriptor = try XCTUnwrap(first.release.sets.first)
        XCTAssertEqual(descriptor.recognitionKind, .energy)
        XCTAssertEqual(descriptor.printedPrefix, "MEE")
        XCTAssertNil(descriptor.officialCount)
        XCTAssertEqual(descriptor.rulesVersion, 2)
        XCTAssertTrue(descriptor.scanEnabled)
        let refreshed = try PokemonCatalogBuilder().build(.init(fixture: evidence,
            activeRelease: first.release, humanInputs: [input], revision: 2,
            generatedAt: Date(timeIntervalSince1970: 1_792_454_400)))
        XCTAssertEqual(refreshed.release.sets, first.release.sets)
        XCTAssertThrowsError(try PokemonCatalogReleaseValidator.validate(first.release,
            configuration: .init(supportedRulesVersion: 1)))
        let policy = try JSONDecoder().decode(PokemonCatalogDiscoveryPolicy.self, from: Data(contentsOf:
            root.appendingPathComponent("publisher/discovery-policy.json")))
        XCTAssertTrue(policy.ignoredHistoricalIDs.contains("mee"), "Explicit override, not wider historical discovery")
    }
}
