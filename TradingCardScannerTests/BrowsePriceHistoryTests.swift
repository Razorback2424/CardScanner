import Foundation
import XCTest
@testable import TradingCardScanner

final class BrowsePriceObservationDayResolverTests: XCTestCase {
    func testPokemonSlashDateUsesUTCProviderDay() throws {
        let resolved = BrowsePriceObservationDayResolver.pokemonTCGIO(updatedAt: "2025/02/03")
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-02-03T00:00:00Z"))
        XCTAssertEqual(resolved, expected)
    }

    func testInvalidTimestampDoesNotFallBackToFetchTime() {
        for value: String? in [nil, "not-a-date", "2025/02/30", "2025/13/01", "2025/02/29"] {
            XCTAssertNil(BrowsePriceObservationDayResolver.pokemonTCGIO(updatedAt: value))
        }
        XCTAssertNotNil(BrowsePriceObservationDayResolver.pokemonTCGIO(updatedAt: "2024/02/29"))
    }

    func testProviderTimestampPreservesItsOriginalInstant() throws {
        let resolved = BrowsePriceObservationDayResolver.pokemonTCGIO(updatedAt: "2025-02-03T12:34:56Z")
        XCTAssertEqual(resolved, ISO8601DateFormatter().date(from: "2025-02-03T12:34:56Z"))
        XCTAssertNotNil(resolved)
    }

    func testLegacyBulkCacheIsIncompatibleWithStage4A() throws {
        let data = Data(#"{"valuesByCardID":{"sv01|1":{"normal":4.0}}}"#.utf8)
        let map = try JSONDecoder().decode(PokemonBulkPriceMap.self, from: data)
        XCTAssertFalse(map.isStage4Compatible)
        XCTAssertNil(map.providerUpdatedAt(for: "sv01-1"))
        XCTAssertEqual(map.price(for: "sv01-1", variant: .normal), 4)
    }

}
