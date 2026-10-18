import Foundation
import XCTest
@testable import TradingCardScanner

#if LOCAL_ONLY_SIGNING
/// Keep this file independent of Debug-only test helpers so the same regression
/// can exercise the optimized ReleaseLocal app used by the ProfileLocal scheme.
final class OnePieceAvailabilityTests: XCTestCase {
    func testLocalBuildRetainsOnePieceAcrossFreshLaunches() throws {
        let suite = "OnePieceAvailability-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }

        for _ in 0..<2 {
            let runtime = try XCTUnwrap(OnePieceCatalogBootstrap.ownerRuntime(preferences: preferences))
            XCTAssertNotNil(runtime.catalog)
            XCTAssertNotNil(runtime.recognizer)
            XCTAssertFalse(preferences.bool(forKey: "onePieceOwnerCatalogEnabled"))

            let games = CardGameRuntimeContainer.appDefaults().registry
            for capability: CardGameCapabilities in [.scan, .browse, .collectionWrite, .pricing, .sealed] {
                XCTAssertTrue(games.supports(.onePiece, capability))
            }
            XCTAssertTrue(games.variantLockMenu.contains { $0.game == .onePiece && !$0.options.isEmpty })
            XCTAssertFalse(OnePieceCatalogBootstrap.isLocalReviewLaunch)
        }
    }
}
#endif
