import Combine
import SwiftData
import SwiftUI
import XCTest
@testable import TradingCardScanner

@MainActor
final class AppOpeningTests: XCTestCase {
    func testHostedReadyHandoffDoesNotImposeAHoldForFastOrSlowLaunches() async throws {
        for (name, slow) in [("fast", false), ("slow", true)] {
            try await withOpeningHost { opening in
                if slow { try await Task.sleep(for: .milliseconds(200)) }
                XCTAssertFalse(opening.handoff, "Loading must keep content gated")
                let began = self.expectation(description: "Ready handoff: \(name)")
                let started = ContinuousClock.now
                var elapsed: Duration?
                let observation = opening.$handoff.filter { $0 }.prefix(1).sink { _ in
                    elapsed = started.duration(to: .now)
                    began.fulfill()
                }
                defer { observation.cancel() }
                opening.portfolioDidLoad(copies: 3)
                await self.fulfillment(of: [began], timeout: 2)
                let duration = try XCTUnwrap(elapsed)
                print("M05 hosted \(name) readiness-to-handoff: \(duration)")
                XCTAssertLessThan(duration, .milliseconds(100), "Readiness must begin the reveal without a presentation hold")
                XCTAssertEqual(opening.fastHandoff, !slow)
                let finished = self.expectation(description: "Reveal completes: \(name)")
                let completion = opening.$showsOpening.filter { !$0 }.prefix(1).sink { _ in finished.fulfill() }
                defer { completion.cancel() }
                await self.fulfillment(of: [finished], timeout: 2)
                XCTAssertTrue(opening.handoff)
                XCTAssertFalse(opening.showsOpening)
            }
        }
    }

    func testHostedPhaseResetCancelsSettlingAndBlockedOpeningExposesContent() async throws {
        try await withOpeningHost { opening in
            let began = self.expectation(description: "Initial handoff")
            let observation = opening.$handoff.filter { $0 }.prefix(1).sink { _ in began.fulfill() }
            defer { observation.cancel() }
            opening.portfolioDidLoad(copies: nil)
            await self.fulfillment(of: [began], timeout: 2)
            opening.reset()
            try await Task.sleep(for: .milliseconds(750))
            XCTAssertFalse(opening.handoff)
            XCTAssertTrue(opening.showsOpening, "The canceled settling task must not hide a new opening")

            let exposed = self.expectation(description: "Blocked startup reveals recovery content")
            let recovery = opening.$showsOpening.filter { !$0 }.prefix(1).sink { _ in exposed.fulfill() }
            defer { recovery.cancel() }
            opening.blocked = true
            await self.fulfillment(of: [exposed], timeout: 2)
            XCTAssertTrue(opening.handoff)
            XCTAssertFalse(opening.showsOpening)
        }
    }

    private func withOpeningHost(exercise: (AppOpeningModel) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("M05-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = CollectionStoragePaths(applicationSupportURL: directory,
            collectionStorageDirectoryURL: directory.appendingPathComponent("CollectionStorage"),
            structuredStoreURL: directory.appendingPathComponent("CollectionStorage/Collection.store"),
            portfolioStoreURL: directory.appendingPathComponent("CollectionStorage/Portfolio.store"))
        let manifest = CollectionStoreManifestStore(directoryURL: paths.collectionStorageDirectoryURL)
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let bootstrap = CollectionStorageBootstrap(dependencies: CollectionStorageBootstrapDependencies(
            paths: paths, manifestStore: manifest, accountAvailability: { .noAccount },
            claimAnchor: { _ in XCTFail("Local opening must not claim a cloud anchor"); return .temporarilyUnavailable },
            makeContainer: { _ in container },
            readinessSource: FixedCloudRestorationReadinessSource(result: .readyEmpty),
            structuredStoreFilePresent: { false }, structuredStoreBaseFilePresent: { false },
            localHasUserData: { false },
            storeFileIdentity: { try manifest.writeStoreFileIdentity("opening-fixture"); return "opening-fixture" },
            readStoreFileIdentity: { try manifest.readStoreFileIdentity() }, adoptLegacyStore: { nil },
            storageGeneration: CollectionStorageGeneration()))
        await bootstrap.start()
        guard case .ready = bootstrap.state else { return XCTFail("Expected isolated local storage") }
        let opening = AppOpeningModel()
        let mounted = expectation(description: "Opening content mounted")
        let controller = UIHostingController(rootView: AppOpeningContainer(bootstrap: bootstrap, opening: opening) {
            Button("Collection ready") { }
                .onAppear { mounted.fulfill() }
        })
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil }
        await fulfillment(of: [mounted], timeout: 2)
        // Let the initial phase/session observers settle before publishing readiness.
        await Task.yield()
        try await exercise(opening)
    }

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
