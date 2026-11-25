import Combine
import SwiftData
import SwiftUI
import XCTest
@testable import TradingCardScanner

@MainActor
final class AppOpeningTests: XCTestCase {
    func testUnavailableCatalogDismissalDoesNotChangeUnderlyingStatus() throws {
        let yuGiOh = try XCTUnwrap(CardGameRegistry.standard.descriptor(for: .yuGiOh))
        let unavailable = [yuGiOh]

        let acknowledged = CatalogRecoveryAcknowledgements.acknowledging("", unavailable: unavailable)
        XCTAssertEqual(acknowledged, "yu-gi-oh")
        XCTAssertTrue(CatalogRecoveryAcknowledgements.visible(unavailable, acknowledged: acknowledged).isEmpty)

        // The underlying unavailable descriptors are untouched by dismissal.
        XCTAssertEqual(unavailable.map(\.game), [.yuGiOh])
        XCTAssertEqual(CatalogRecoveryAcknowledgements.retaining(acknowledged, unavailable: unavailable), acknowledged)
    }

    func testNewCatalogFailureStillShowsAfterAnotherWasDismissed() throws {
        let yuGiOh = try XCTUnwrap(CardGameRegistry.standard.descriptor(for: .yuGiOh))
        let lorcana = try XCTUnwrap(CardGameRegistry.standard.descriptor(for: .lorcana))
        let acknowledged = CatalogRecoveryAcknowledgements.acknowledging("", unavailable: [yuGiOh])

        let visible = CatalogRecoveryAcknowledgements.visible([yuGiOh, lorcana], acknowledged: acknowledged)
        XCTAssertEqual(visible.map(\.game), [.lorcana])
        XCTAssertEqual(
            CatalogRecoveryAcknowledgements.acknowledging(acknowledged, unavailable: visible),
            "lorcana,yu-gi-oh"
        )
    }

    func testCatalogRecoveryClearsDismissalSoLaterFailureWarnsAgain() throws {
        let yuGiOh = try XCTUnwrap(CardGameRegistry.standard.descriptor(for: .yuGiOh))
        let acknowledged = CatalogRecoveryAcknowledgements.acknowledging("", unavailable: [yuGiOh])

        let afterRecovery = CatalogRecoveryAcknowledgements.retaining(acknowledged, unavailable: [])
        XCTAssertEqual(afterRecovery, "")
        XCTAssertEqual(
            CatalogRecoveryAcknowledgements.visible([yuGiOh], acknowledged: afterRecovery).map(\.game),
            [.yuGiOh]
        )
    }

    func testPartialCatalogRecoveryPreservesOnlyStillUnavailableAcknowledgements() throws {
        let yuGiOh = try XCTUnwrap(CardGameRegistry.standard.descriptor(for: .yuGiOh))
        let lorcana = try XCTUnwrap(CardGameRegistry.standard.descriptor(for: .lorcana))
        let acknowledged = CatalogRecoveryAcknowledgements.acknowledging(
            "", unavailable: [yuGiOh, lorcana]
        )

        let retained = CatalogRecoveryAcknowledgements.retaining(acknowledged, unavailable: [yuGiOh])
        XCTAssertEqual(retained, "yu-gi-oh")
        XCTAssertEqual(
            CatalogRecoveryAcknowledgements.visible([lorcana], acknowledged: retained).map(\.game),
            [.lorcana]
        )
    }

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

    func testRevealBudgetReportsReadyWithoutCountWhilePortfolioIsStillComputing() async throws {
        let opening = AppOpeningModel()
        let portfolio = PortfolioEngine()
        let ready = expectation(description: "Budget releases the opening")
        let observation = opening.$portfolioReady.filter { $0 != nil }.prefix(1).sink { _ in ready.fulfill() }
        defer { observation.cancel() }
        let window = host(AppOpeningReadinessReporter(portfolio: portfolio, skipsPortfolio: false,
                                                      holdsOpening: false, revealBudget: .milliseconds(50))
            .environmentObject(opening))
        defer { window.isHidden = true; window.rootViewController = nil }
        await fulfillment(of: [ready], timeout: 2)
        XCTAssertNil(portfolio.summary, "The fixture portfolio never computes")
        XCTAssertNil(opening.portfolioReady!, "A budget release has no copy count to report")
    }

    func testRevealBudgetDoesNotOverrideStartupHold() async throws {
        let opening = AppOpeningModel()
        let window = host(AppOpeningReadinessReporter(portfolio: PortfolioEngine(), skipsPortfolio: false,
                                                      holdsOpening: true, revealBudget: .milliseconds(20))
            .environmentObject(opening))
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(opening.portfolioReady == nil)
    }

    func testDefaultRevealBudgetStaysShort() {
        XCTAssertLessThanOrEqual(AppOpeningModel.portfolioRevealBudget, .milliseconds(400))
    }

    private func host<V: View>(_ view: V) -> UIWindow {
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        return window
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

/// Launch opens on the last value Portfolio published instead of a blank
/// calculating screen, without letting that cached value stand in for truth.
@MainActor
final class PortfolioLaunchSnapshotTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PortfolioLaunchSnapshotTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testSnapshotIsScopedToItsStoreAndRecordsOnlyTrustedNonEmptySummaries() {
        let store = PortfolioLaunchSnapshotStore(defaults: defaults)
        let storeID = UUID()
        store.record(summary(value: 1_234_5600, copies: 12), storeID: storeID)
        XCTAssertEqual(store.load(storeID: storeID)?.valueTenThousandths, 1_234_5600)
        XCTAssertEqual(store.load(storeID: storeID)?.copyCount, 12)
        XCTAssertNil(store.load(storeID: UUID()), "Another store must never open on this value")
        XCTAssertNil(store.load(storeID: nil))

        var untrusted = summary(value: 9, copies: 1)
        untrusted.isAuthoritative = false
        store.record(untrusted, storeID: storeID)
        var defective = summary(value: 9, copies: 1)
        defective.defects = [LedgerIntegrityDefect(reason: .unreadableStore, collectionKey: "store:test",
                                                   detail: "Injected", canRepairQuantity: false)]
        store.record(defective, storeID: storeID)
        store.record(summary(value: 9, copies: 1), storeID: nil)
        XCTAssertEqual(store.load(storeID: storeID)?.valueTenThousandths, 1_234_5600,
                       "Only an authoritative, defect-free summary of a known store replaces the snapshot")

        store.record(summary(value: 0, copies: 0), storeID: storeID)
        XCTAssertNil(store.load(storeID: storeID), "An emptied collection clears its snapshot")
    }

    func testEngineOpensOnProvisionalValueAndKeepsItUntilReplayReplacesIt() async throws {
        let storeID = UUID()
        let store = PortfolioLaunchSnapshotStore(defaults: defaults)
        store.record(summary(value: 500_0000, copies: 7), storeID: storeID)
        let gate = LaunchReplayGate()
        let engine = PortfolioEngine(computationProvider: { _, epoch, through, zone in
            await gate.wait()
            return Self.computation(value: 612_5000, copies: 8, epoch: epoch, through: through, zone: zone)
        }, launchSnapshots: store, launchStoreID: storeID)

        let opened = try XCTUnwrap(engine.summary)
        XCTAssertEqual(opened.currentValue, Money(tenThousandths: 500_0000))
        XCTAssertEqual(opened.copyCount, 7)
        XCTAssertTrue(opened.isProvisional)
        XCTAssertFalse(opened.isAuthoritative, "History and closes must not render from a cached value")

        let context = try makeContext()
        engine.recompute(context: context)
        await Task.yield()
        XCTAssertTrue(engine.isRecomputing)
        XCTAssertEqual(engine.summary?.currentValue, Money(tenThousandths: 500_0000),
                       "The replay must not blank the last known value")
        XCTAssertEqual(engine.summary?.isProvisional, true)

        await gate.open()
        await engine.recomputeAndWait(context: context)
        let replayed = try XCTUnwrap(engine.summary)
        XCTAssertFalse(replayed.isProvisional)
        XCTAssertEqual(replayed.currentValue, Money(tenThousandths: 612_5000))
        XCTAssertEqual(replayed.copyCount, 8)
    }

    func testUnreadableFirstReplayDoesNotVouchForTheCachedValue() async throws {
        let storeID = UUID()
        let store = PortfolioLaunchSnapshotStore(defaults: defaults)
        store.record(summary(value: 500_0000, copies: 7), storeID: storeID)
        let engine = PortfolioEngine(computationProvider: { _, epoch, through, zone in
            var computation = Self.computation(value: 0, copies: 0, epoch: epoch, through: through, zone: zone)
            computation.defects = [LedgerIntegrityDefect(reason: .unreadableStore, collectionKey: "store:test",
                                                         detail: "Injected", canRepairQuantity: false)]
            computation.isAuthoritative = false
            return computation
        }, launchSnapshots: store, launchStoreID: storeID)
        XCTAssertNotNil(engine.summary)

        await engine.recomputeAndWait(context: try makeContext())
        XCTAssertNil(engine.summary, "A failed first read shows “Value unavailable”, not a stale number")
        XCTAssertEqual(engine.integrityDefects.first?.reason, .unreadableStore)
    }

    func testHeadlessReplayRecordsOnlyForItsCurrentStore() async throws {
        let context = try makeContext()
        let storeID = UUID()
        let snapshots = PortfolioLaunchSnapshotStore(defaults: defaults)
        let gate = LaunchReplayGate()
        let replayStarted = expectation(description: "Headless replay read the old session")
        let now = PortfolioEpoch.startedAt() ?? .now
        let generation = CollectionStorageGeneration()
        generation.installReady(session: CollectionStorageSession(
            container: context.container, storeID: storeID, mode: .onDevice, isAuthoritative: true
        ))
        let currentToken = try XCTUnwrap(generation.currentToken())
        let session = HeadlessCollectionStorageSession(
            container: context.container, storeID: storeID, mode: .onDevice, isAuthoritative: true,
            token: currentToken, continuation: generation.continuation(for: currentToken)
        )
        let firstEngine = PortfolioEngine(computationProvider: { _, epoch, through, zone in
            Self.computation(value: 612_5000, copies: 8, epoch: epoch, through: through, zone: zone)
        }, launchSnapshots: snapshots, headlessSession: session)
        await firstEngine.recomputeAndWait(context: context, now: now)
        XCTAssertEqual(snapshots.load(storeID: storeID)?.valueTenThousandths, 612_5000)
        XCTAssertNil(snapshots.load(storeID: UUID()))

        let lateEngine = PortfolioEngine(computationProvider: { _, epoch, through, zone in
            replayStarted.fulfill()
            await gate.wait()
            return Self.computation(value: 700_0000, copies: 8, epoch: epoch, through: through, zone: zone)
        }, launchSnapshots: snapshots, headlessSession: session)
        let replay = Task { await lateEngine.recomputeAndWait(context: context, now: now) }
        await fulfillment(of: [replayStarted], timeout: 2)
        generation.suspend()
        await gate.open()
        await replay.value
        XCTAssertEqual(snapshots.load(storeID: storeID)?.valueTenThousandths, 612_5000)
    }

    func testOpeningReleasesImmediatelyWithTheCachedCopyCount() async throws {
        let storeID = UUID()
        let store = PortfolioLaunchSnapshotStore(defaults: defaults)
        store.record(summary(value: 500_0000, copies: 312), storeID: storeID)
        let engine = PortfolioEngine(launchSnapshots: store, launchStoreID: storeID)
        let opening = AppOpeningModel()
        let ready = expectation(description: "Cached value releases the opening")
        let observation = opening.$portfolioReady.filter { $0 != nil }.prefix(1).sink { _ in ready.fulfill() }
        defer { observation.cancel() }
        let controller = UIHostingController(rootView: AppOpeningReadinessReporter(
            portfolio: engine, skipsPortfolio: false, holdsOpening: false, revealBudget: .seconds(30)
        ).environmentObject(opening))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        await fulfillment(of: [ready], timeout: 2)
        XCTAssertEqual(opening.portfolioReady, .some(312))
    }

    private func summary(value: Int64, copies: Int) -> PortfolioSummary {
        PortfolioSummary(currentValue: Money(tenThousandths: value), copyCount: copies)
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
                                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    nonisolated private static func computation(
        value: Int64, copies: Int, epoch: Date, through: Date, zone: String
    ) -> PortfolioReplaySnapshotBuilder.Computation {
        let replay = PortfolioReplayEngine.replay(PortfolioReplayInput(events: [], observations: [],
            epoch: epoch, through: through, timeZoneIdentifier: zone))
        return PortfolioReplaySnapshotBuilder.Computation(
            valuation: PortfolioEngine.CurrentValuation(value: Money(tenThousandths: value), copiesHeld: copies),
            defects: [], isAuthoritative: true, replay: replay, coverage: PortfolioCoverageIndex(), holdings: [])
    }
}

private actor LaunchReplayGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// Launch renders the whole dashboard from the previous launch's publication,
/// not just its headline, and hands every part back to this launch's replay.
@MainActor
final class PortfolioLaunchPresentationTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortfolioLaunchPresentationTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "PortfolioLaunchPresentationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testPresentationKeepsShowcaseAndNamedMoversAndRoundTrips() async throws {
        let storeID = UUID()
        let holdings = PortfolioHoldingSnapshot.rankedByUnitPrice(
            (0..<40).map { holding("card-\($0)", unit: $0 < 39 ? Int64(1_000_0000 - $0 * 1_0000) : nil) }
        )
        // Movement on 30 keys; only the 25 largest are worth naming.
        let contributions = Dictionary(uniqueKeysWithValues: (10..<40).map {
            ("card-\($0)", Money(tenThousandths: Int64($0) * ($0.isMultiple(of: 2) ? 1_0000 : -1_0000)))
        })
        let result = history(range: .oneMonth, contributions: contributions)
        let store = PortfolioLaunchPresentationStore(fileURL: directory.appendingPathComponent("p.json"))
        store.record(PortfolioLaunchPresentation(
            storeID: storeID, savedAt: .now, holdings: holdings, history: result
        ))
        await store.waitForPendingWrites()

        XCTAssertNil(store.load(storeID: UUID()), "Another store never opens on this dashboard")
        let loaded = try XCTUnwrap(store.load(storeID: storeID))
        let keys = loaded.holdingSnapshots.map(\.collectionKey)
        XCTAssertEqual(Array(keys.prefix(5)), (0..<5).map { "card-\($0)" },
                       "The Showcase opens in the order it was last ranked")
        let largestMovers = Set((15..<40).map { "card-\($0)" })
        XCTAssertEqual(Set(keys), Set((0..<5).map { "card-\($0)" }).union(largestMovers))
        XCTAssertEqual(Set(loaded.history.map { Array($0.contributions.keys) } ?? []), largestMovers)

        let restored = try XCTUnwrap(loaded.history?.result)
        XCTAssertEqual(restored.range, result.range)
        XCTAssertEqual(restored.points, result.points)
        XCTAssertEqual(restored.accounting, result.accounting)
        XCTAssertEqual(restored.accountingInterval, result.accountingInterval)
        XCTAssertEqual(restored.coverage, result.coverage)
        XCTAssertEqual(restored.contributions["card-39"], Money(tenThousandths: -39_0000))
        XCTAssertEqual(loaded.holdingSnapshots.first, holdings.first)
    }

    func testEngineOpensOnCachedDashboardOnlyBesideItsSnapshot() async throws {
        let storeID = UUID()
        let snapshots = PortfolioLaunchSnapshotStore(defaults: defaults)
        let presentations = PortfolioLaunchPresentationStore(fileURL: directory.appendingPathComponent("p.json"))
        let holdings = [holding("a", unit: 10_0000), holding("b", unit: 5_0000)]
        let result = history(range: .oneWeek, contributions: ["a": Money(tenThousandths: 1_0000)])
        presentations.record(PortfolioLaunchPresentation(
            storeID: storeID, savedAt: .now, holdings: holdings, history: result
        ))
        await presentations.waitForPendingWrites()

        let withoutValue = PortfolioEngine(
            launchSnapshots: snapshots, launchPresentations: presentations, launchStoreID: storeID
        )
        XCTAssertTrue(withoutValue.holdings.isEmpty, "No dashboard opens without the value it belongs to")
        XCTAssertNil(withoutValue.launchHistory)

        snapshots.record(PortfolioSummary(currentValue: Money(tenThousandths: 15_0000), copyCount: 2),
                         storeID: storeID)
        let engine = PortfolioEngine(
            launchSnapshots: snapshots, launchPresentations: presentations, launchStoreID: storeID
        )
        XCTAssertEqual(engine.summary?.isProvisional, true)
        XCTAssertEqual(engine.holdings, holdings)
        XCTAssertEqual(engine.launchHistory?.points, result.points)
    }

    func testLaunchSnapshotsOmitValuesAndHistoryAheadOfTheClock() async throws {
        let storeID = UUID()
        let snapshots = PortfolioLaunchSnapshotStore(defaults: defaults)
        let presentations = PortfolioLaunchPresentationStore(fileURL: directory.appendingPathComponent("p.json"))
        let result = history(range: .oneWeek, contributions: [:])
        let endpoint = try XCTUnwrap(result.points.last?.instant)
        let now = endpoint.addingTimeInterval(-60)

        snapshots.record(PortfolioSummary(currentValue: Money(tenThousandths: 15_0000), copyCount: 2),
                         storeID: storeID, now: endpoint)
        presentations.record(PortfolioLaunchPresentation(
            storeID: storeID, savedAt: now, holdings: [], history: result
        ))
        await presentations.waitForPendingWrites()

        XCTAssertNil(snapshots.load(storeID: storeID, now: now))
        XCTAssertNil(presentations.load(storeID: storeID, now: now))
        XCTAssertNotNil(snapshots.load(storeID: storeID, now: endpoint))
        XCTAssertEqual(presentations.load(storeID: storeID, now: endpoint)?.history?.result.points, result.points)
    }

    func testHistoryStoreKeepsLaunchChartUntilThisLaunchHasHistory() throws {
        let selected = PortfolioHistoryStore().range
        let other = PortfolioHistoryRange.allCases.first { $0 != selected }!

        let mismatched = PortfolioHistoryStore(launchResult: history(range: other, contributions: [:]))
        XCTAssertNil(mismatched.result, "A cached chart never opens under a different period chip")

        let store = PortfolioHistoryStore(launchResult: history(range: selected, contributions: [:]))
        XCTAssertTrue(store.isShowingLaunchResult)
        XCTAssertEqual(store.result?.range, selected)

        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
                                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        // Launch asks for history before its first replay has published.
        store.recompute(context: ModelContext(container), summary: nil,
                        factors: PortfolioPerformanceFactors(), contributions: PortfolioContributionIndex())
        XCTAssertNotNil(store.result, "The cached chart stays up until this launch replaces it")
        XCTAssertTrue(store.isShowingLaunchResult)
    }

    private func holding(_ key: String, unit: Int64?) -> PortfolioHoldingSnapshot {
        PortfolioHoldingSnapshot(
            collectionKey: key, name: key, detail: "Set · Holo",
            artworkURL: URL(string: "https://example.com/\(key).png"),
            quantity: 2,
            unitPrice: unit.map { Money(tenThousandths: $0) },
            holdingValue: unit.map { Money(tenThousandths: $0 * 2) },
            priceStorageKey: "price:\(key)",
            artworkGame: .pokemon, artworkSetCode: "sv1", artworkCollectorNumber: "1"
        )
    }

    private func history(
        range: PortfolioHistoryRange, contributions: [String: Money]
    ) -> PortfolioHistoryResult {
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        return PortfolioHistoryResult(
            range: range,
            points: [
                PortfolioHistoryPoint(displayDay: day, instant: day.addingTimeInterval(86_400),
                                      value: Money(tenThousandths: 100_0000), isLive: false),
                PortfolioHistoryPoint(displayDay: day.addingTimeInterval(86_400),
                                      instant: day.addingTimeInterval(90_000),
                                      value: Money(tenThousandths: 112_5000),
                                      cumulativeMarketMovement: Money(tenThousandths: 12_5000),
                                      performanceFactor: Decimal(string: "1.125"), isLive: true),
            ],
            accounting: PortfolioHistoryAccounting(
                anchorValue: Money(tenThousandths: 100_0000), endValue: Money(tenThousandths: 112_5000),
                market: Money(tenThousandths: 12_5000), added: .zero, removed: .zero, corrections: .zero,
                pricingAdjustments: .zero, unexplained: .zero
            ),
            performanceFactor: Decimal(string: "1.125"),
            performanceAvailable: true,
            coverage: PortfolioHistoryCoverage(
                completeDays: 1, live: PortfolioCoverage(refreshed: 3, carriedForward: 1, state: .partial)
            ),
            revisions: [],
            trackingBeganDate: nil,
            hasTwoPublishedPoints: true,
            accountingInterval: PortfolioAccountingInterval(
                anchorDate: day, includedClosedDays: [], includesLiveDay: true,
                liveDay: day.addingTimeInterval(86_400)
            ),
            contributions: contributions,
            hasEligibleMarketMovement: true
        )
    }
}
