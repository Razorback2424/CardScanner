import XCTest
@testable import TradingCardScanner

@MainActor
final class AppOpeningTests: XCTestCase {
    func testCaptionsDistinguishCopiesFromEmptyOrUnknownCollection() {
        XCTAssertEqual(AppOpeningPhase.opening.caption, "Opening your collection…")
        XCTAssertEqual(AppOpeningPhase.restoringFromCloud.caption, "Restoring collection from iCloud…")
        XCTAssertEqual(AppOpeningPhase.ready(copies: 1).caption, "1 copy ready")
        XCTAssertEqual(AppOpeningPhase.ready(copies: 312).caption, "312 copies ready")
        XCTAssertEqual(AppOpeningPhase.ready(copies: 0).caption, "Collection ready")
        XCTAssertEqual(AppOpeningPhase.ready(copies: nil).caption, "Collection ready")
    }

    func testStoragePhaseKeepsRestorationDistinctAndExposesFailures() {
        XCTAssertEqual(CollectionStorageBootstrap.State.loading.openingPhase(portfolioReady: nil), .opening)
        for readiness in [CloudRestorationReadiness.checkingRemoteCollection, .importingRemoteCollection] {
            XCTAssertEqual(CollectionStorageBootstrap.State.restoringFromCloud(readiness)
                .openingPhase(portfolioReady: nil), .restoringFromCloud)
        }
        for readiness in [CloudRestorationReadiness.readyEmpty, .readyPopulated] {
            XCTAssertEqual(CollectionStorageBootstrap.State.restoringFromCloud(readiness)
                .openingPhase(portfolioReady: nil), .opening)
        }
        XCTAssertNil(CollectionStorageBootstrap.State.restoringFromCloud(.failed(category: "test"))
            .openingPhase(portfolioReady: nil))
        XCTAssertNil(CollectionStorageBootstrap.State.restoringFromCloud(.notApplicable)
            .openingPhase(portfolioReady: nil))
        XCTAssertNil(CollectionStorageBootstrap.State.recoveryRequired("test").openingPhase(portfolioReady: nil))
        XCTAssertNil(CollectionStorageBootstrap.State.temporarilyUnavailable("test").openingPhase(portfolioReady: nil))
    }

    func testReadyWithoutCountLatchesAcrossCatalogRebind() {
        let opening = AppOpeningModel()
        opening.portfolioDidLoad(copies: nil)
        XCTAssertNotNil(opening.portfolioReady as Any?)
        XCTAssertNil(opening.portfolioReady!)
        opening.beginHandoff(fast: true)
        opening.finishHandoff()
        opening.portfolioDidLoad(copies: 312)
        XCTAssertNil(opening.portfolioReady!)
        XCTAssertTrue(opening.handoff)
        XCTAssertFalse(opening.showsOpening)
    }

    func testResetAndStorageReplacementOpenAgain() {
        let opening = AppOpeningModel()
        let first = NSObject()
        let second = NSObject()
        opening.bindSession(ObjectIdentifier(first))
        opening.portfolioDidLoad(copies: 3)
        opening.beginHandoff(fast: false)
        opening.finishHandoff()
        opening.bindSession(ObjectIdentifier(first))
        XCTAssertFalse(opening.showsOpening)
        opening.bindSession(ObjectIdentifier(second))
        XCTAssertTrue(opening.showsOpening)
        XCTAssertFalse(opening.handoff)
        XCTAssertTrue(opening.portfolioReady == nil)
        opening.blocked = true
        opening.revealProblem()
        XCTAssertFalse(opening.showsOpening)
        opening.reset()
        XCTAssertFalse(opening.blocked)
        XCTAssertTrue(opening.showsOpening)
    }

    private func projection(quantities: [Int]) -> LogicalCollectionProjection {
        let positions = quantities.enumerated().map { index, quantity in
            let key = "opening-test-\(index)"
            let card = CollectedCard(collectionKey: key, game: .pokemon, providerID: key,
                name: "Opening Test", setName: "Test", setCode: "TST", cardNumber: "1",
                rarity: nil, imageURL: nil, thumbnailURL: nil, variant: nil,
                variantResolution: .imported)
            return LogicalCollectedPosition(collectionKey: key, quantity: quantity,
                representative: card, priceStorageKey: key, dateAdded: .now, physicalRowCount: 1)
        }
        return LogicalCollectionProjection(positions: positions,
            byKey: Dictionary(uniqueKeysWithValues: positions.map { ($0.collectionKey, $0) }), defects: [])
    }

    func testCopyCountIncludesUnpricedCopiesAndIgnoresZeroAndNegativePositions() {
        let result = PortfolioEngine.currentValuation(projection: projection(quantities: [3, 2, 0, -1]),
            valuations: InstrumentValuationIndex(byInstrument: [:]), otherCurrencyInstruments: [])
        XCTAssertEqual(result.copiesHeld, 5)
        XCTAssertFalse(result.hasArithmeticOverflow)
    }

    func testEmptyCollectionHasZeroCopies() {
        let result = PortfolioEngine.currentValuation(projection: projection(quantities: []),
            valuations: InstrumentValuationIndex(byInstrument: [:]), otherCurrencyInstruments: [])
        XCTAssertEqual(result.copiesHeld, 0)
    }

    func testCopyOverflowReportsNoCountInsteadOfTrapping() {
        let result = PortfolioEngine.currentValuation(projection: projection(quantities: [Int.max, 1]),
            valuations: InstrumentValuationIndex(byInstrument: [:]), otherCurrencyInstruments: [])
        XCTAssertNil(result.copiesHeld)
        // The unpriced tally overflows too and is reported, not wrapped.
        XCTAssertTrue(result.hasArithmeticOverflow)
        XCTAssertEqual(result.unpricedCount, Int.max)
    }
}
