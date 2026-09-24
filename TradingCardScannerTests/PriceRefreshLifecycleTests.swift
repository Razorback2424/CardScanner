import SwiftData
import XCTest
@testable import TradingCardScanner

private actor PriceRefreshTestGate {
    private var didStart = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var released = false

    func pauseUntilReleased() async {
        didStart = true
        startWaiter?.resume()
        startWaiter = nil
        if released { return }
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func pauseUntilCancelled() async throws {
        didStart = true
        startWaiter?.resume()
        startWaiter = nil
        try await Task.sleep(for: .seconds(30))
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

@MainActor
final class PriceRefreshLifecycleTests: XCTestCase {
    func testForegroundJoinPromotesQueueAndBackgroundCancelIsScoped() async throws {
        let container = try makeContainer(withCard: true)
        let controller = PriceRefreshController()
        let gate = PriceRefreshTestGate()
        controller.setPokemonFetchOverrideForTesting { printing in
            await gate.pauseUntilReleased()
            return .pokemon(Self.card(id: printing.printingID), setCode: "LIF")
        }

        let backgroundPass = Task {
            await controller.refresh(
                Self.request,
                container: container,
                owner: .background
            )
        }
        await gate.waitUntilStarted()

        let foregroundJoin = Task {
            await controller.refresh(
                Self.request,
                container: container,
                owner: .foreground
            )
        }
        for _ in 0..<20 where controller.activeRefreshOwner != .foreground {
            await Task.yield()
        }
        XCTAssertEqual(controller.activeRefreshOwner, .foreground)
        XCTAssertFalse(controller.cancelRefresh(onlyIfOwnedBy: .background))

        await gate.release()
        let foregroundResult = await foregroundJoin.value
        let backgroundResult = await backgroundPass.value
        XCTAssertFalse(foregroundResult.wasPreempted)
        XCTAssertFalse(backgroundResult.wasPreempted)
    }

    func testForegroundStartupPreemptsBackgroundQueueAndSignalsCompletion() async throws {
        let container = try makeContainer(withCard: true)
        let controller = PriceRefreshController()
        let signal = PriceRefreshCompletionSignal()
        controller.registerCompletionSignal(signal)
        let gate = PriceRefreshTestGate()
        controller.setPokemonFetchOverrideForTesting { printing in
            try await gate.pauseUntilCancelled()
            return .pokemon(Self.card(id: printing.printingID), setCode: "LIF")
        }

        let backgroundPass = Task {
            await controller.refresh(
                Self.request,
                container: container,
                owner: .background
            )
        }
        await gate.waitUntilStarted()

        let preempted = await controller.preemptBackgroundPass()
        XCTAssertTrue(preempted)
        let result = await backgroundPass.value
        XCTAssertTrue(result.wasPreempted)
        XCTAssertEqual(signal.generation, 1)
    }

    func testForegroundPreemptionStopsTheUnstructuredBackgroundQueueBeforeJoiningRun() async throws {
        let container = try makeContainer(withCard: true)
        let controller = PriceRefreshController()
        let gate = PriceRefreshTestGate()
        controller.setPokemonFetchOverrideForTesting { printing in
            try await gate.pauseUntilCancelled()
            return .pokemon(Self.card(id: printing.printingID), setCode: "LIF")
        }

        let backgroundRun = Task {
            let result = await controller.refresh(
                Self.request,
                container: container,
                owner: .background
            )
            return result.wasPreempted
        }
        await gate.waitUntilStarted()

        await BackgroundPriceRefresh.preemptBackgroundRunForForeground(
            task: backgroundRun,
            refreshController: controller
        )

        let wasPreempted = await backgroundRun.value
        XCTAssertTrue(wasPreempted)
        XCTAssertFalse(controller.isPassInFlight)
    }

    func testRefreshArrivingDuringSuspensionQueuesWithoutWaitingForResume() async throws {
        let container = try makeContainer(withCard: true)
        let controller = PriceRefreshController()
        let suspension = await controller.suspendPasses()

        let queued = await controller.refresh(Self.request, container: container)
        XCTAssertFalse(queued.didRun)
        XCTAssertTrue(controller.isPassInFlight == false)

        controller.resume(suspension)
        for _ in 0..<100 where controller.isPassInFlight {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(controller.isPassInFlight)
    }

    func testQueuedRefreshReleasesMigrationGateForWaitingIdentityWriter() async throws {
        let container = try makeContainer(withCard: false)
        let controller = PriceRefreshController()
        let migration = MagicTreatmentMigrationCoordinator.shared
        let operationBarrier = PriceRefreshTestGate()

        let refreshInsideGate = Task {
            let token = await migration.acquireExclusive()
            await operationBarrier.pauseUntilReleased()
            let result = await controller.refresh(Self.request, container: container)
            migration.releaseExclusive(token)
            return result
        }
        await operationBarrier.waitUntilStarted()

        let suspension = await controller.suspendPasses()
        let identityWriter = Task { await migration.acquireExclusive() }
        // Give the writer task a turn to wait for the migration gate before
        // the gate-owning refresh reaches the paused controller.
        for _ in 0..<10 { await Task.yield() }
        await operationBarrier.release()

        let queuedResult = await refreshInsideGate.value
        let writerToken = await identityWriter.value
        migration.releaseExclusive(writerToken)
        controller.cancelRefresh()
        controller.resume(suspension)

        XCTAssertFalse(queuedResult.didRun)
        XCTAssertEqual(controller.status, .idle)
    }

    func testResumeAfterQueueIsCancelledDuringSuspensionReturnsToIdle() async throws {
        let container = try makeContainer(withCard: true)
        let controller = PriceRefreshController()
        let gate = PriceRefreshTestGate()
        controller.setPokemonFetchOverrideForTesting { printing in
            try await gate.pauseUntilCancelled()
            return .pokemon(Self.card(id: printing.printingID), setCode: "LIF")
        }

        let active = Task {
            await controller.refresh(Self.request, container: container)
        }
        await gate.waitUntilStarted()
        let suspension = await controller.suspendPasses()
        _ = await active.value
        controller.cancelRefresh()
        controller.resume(suspension)

        XCTAssertEqual(controller.status, .idle)
        XCTAssertFalse(controller.isPassInFlight)
    }

    private static let request = PriceRefreshRequest(
        usesPriceFallback: false,
        includeImported: true,
        forceUnsupportedRetry: false,
        sortOldestFirst: true,
        maximumTargetCount: nil,
        markRecentlyCheckedIfEmpty: false
    )

    private func makeContainer(withCard: Bool) throws -> ModelContainer {
        let container = try ModelContainer(
            for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        if withCard {
            let context = container.mainContext
            context.insert(
                CollectedCard(
                    collectionKey: "lifecycle-card#normal",
                    game: .pokemon,
                    providerID: "lifecycle-card",
                    name: "Lifecycle Card",
                    setName: "Lifecycle Set",
                    setCode: "LIF",
                    cardNumber: "1",
                    rarity: "Common",
                    imageURL: nil,
                    thumbnailURL: nil,
                    variant: .normal,
                    variantResolution: .uniqueInCatalog
                )
            )
            try context.save()
        }
        return container
    }

    nonisolated private static func card(id: String) -> TCGdexCard {
        TCGdexCard(
            id: id,
            localId: "1",
            name: "Lifecycle Card",
            image: nil,
            rarity: "Common",
            set: TCGdexSetBrief(
                id: "LIF",
                name: "Lifecycle Set",
                cardCount: TCGdexCardCount(total: 1, official: 1)
            ),
            variants: TCGdexVariants(
                firstEdition: false,
                holo: false,
                normal: true,
                reverse: false,
                wPromo: false
            ),
            pricing: nil,
            variantsDetailed: nil
        )
    }
}
