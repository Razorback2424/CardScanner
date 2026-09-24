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

    func pauseUntilCancelled(for duration: Duration = .seconds(30)) async throws {
        didStart = true
        startWaiter?.resume()
        startWaiter = nil
        try await Task.sleep(for: duration)
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

private actor PriceRefreshAttemptCounter {
    private var attempts = 0

    func next() -> Int {
        attempts += 1
        return attempts
    }

    func value() -> Int { attempts }
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

    func testNewSuspensionKeepsResumedRequestWhenGateWaitIsCancelled() async throws {
        let container = try makeContainer(withCard: true)
        let controller = PriceRefreshController()
        let counter = PriceRefreshAttemptCounter()
        controller.setPokemonFetchOverrideForTesting { printing in
            _ = await counter.next()
            return .pokemon(Self.card(id: printing.printingID), setCode: "LIF")
        }

        // Hold the migration gate while a queued request is resumed. Its
        // withPriceRefresh call will wait on this gate before it can start.
        let migration = MagicTreatmentMigrationCoordinator.shared
        let migrationToken = await migration.acquireExclusive()
        let initialSuspension = await controller.suspendPasses()
        let queued = await controller.refresh(Self.request, container: container)
        XCTAssertFalse(queued.didRun)
        controller.resume(initialSuspension)
        for _ in 0..<100 where !controller.isPassInFlight {
            await Task.yield()
        }
        XCTAssertTrue(controller.isPassInFlight)

        // A second writer cancels the resumed task while it is waiting for the
        // gate. Releasing the first writer must not clear this newer request.
        let nextSuspension = Task { await controller.suspendPasses() }
        for _ in 0..<100 where !controller.isSuspendedForWrite {
            await Task.yield()
        }
        XCTAssertTrue(controller.isSuspendedForWrite)
        migration.releaseExclusive(migrationToken)
        let nextToken = await nextSuspension.value
        controller.resume(nextToken)

        for _ in 0..<300 where controller.isPassInFlight {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(controller.isPassInFlight)
        let attempts = await counter.value()
        XCTAssertEqual(attempts, 1, "The retained request must run after the later suspension resumes.")
    }

    func testCancellingSuspensionUpgradesAnExistingNonCancellingWait() async throws {
        let container = try makeContainer(withCard: true)
        let controller = PriceRefreshController()
        let gate = PriceRefreshTestGate()
        let counter = PriceRefreshAttemptCounter()
        controller.setPokemonFetchOverrideForTesting { printing in
            if await counter.next() == 1 {
                try await gate.pauseUntilCancelled(for: .seconds(2))
            }
            return .pokemon(Self.card(id: printing.printingID), setCode: "LIF")
        }

        let active = Task {
            await controller.refresh(Self.request, container: container)
        }
        await gate.waitUntilStarted()

        // A binding starts a non-cancelling suspension and waits for the
        // provider. A structural writer arriving afterward must be able to
        // upgrade that wait and cancel the request.
        let nonCancellingSuspension = Task {
            await controller.suspendPasses(cancelActivePass: false)
        }
        for _ in 0..<100 where !controller.isSuspendedForWrite {
            await Task.yield()
        }
        XCTAssertTrue(controller.isSuspendedForWrite)

        let cancellingToken = await controller.suspendPasses()
        controller.resume(cancellingToken)
        let nonCancellingToken = await nonCancellingSuspension.value
        controller.resume(nonCancellingToken)
        _ = await active.value

        for _ in 0..<300 where controller.isPassInFlight {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(controller.isPassInFlight)
        let attempts = await counter.value()
        XCTAssertEqual(attempts, 2, "The cancelled request should be retained and replayed once.")
    }

    func testQueuedRefreshCanBeAwaitedAfterTheWriterReleasesTheGate() async throws {
        let container = try makeContainer(withCard: true)
        let controller = PriceRefreshController()
        let counter = PriceRefreshAttemptCounter()
        controller.setPokemonFetchOverrideForTesting { printing in
            _ = await counter.next()
            return .pokemon(Self.card(id: printing.printingID), setCode: "LIF")
        }

        let suspension = await controller.suspendPasses(cancelActivePass: false)
        let queued = await controller.refresh(Self.request, container: container)
        XCTAssertFalse(queued.didRun)
        XCTAssertTrue(queued.wasQueuedDuringSuspension)

        let waiter = Task {
            await controller.waitForQueuedRefreshesToFinish()
        }
        await Task.yield()
        controller.resume(suspension)

        let completed = await waiter.value
        let attempts = await counter.value()
        XCTAssertEqual(completed?.didRun, true)
        XCTAssertEqual(attempts, 1)
    }

    func testStaleIdentityPreflightRetriesOnceInsideAuthorizedGate() async throws {
        let wasEnforced = CollectionWriteSerializer.enforcesOwnershipRule
        CollectionWriteSerializer.enforcesOwnershipRule = true
        defer { CollectionWriteSerializer.enforcesOwnershipRule = wasEnforced }

        let container = try ModelContainer(
            for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let seedContext = ModelContext(container)
        let row = CollectedCard(
            collectionKey: "graded:permit-card#psa-10",
            game: .pokemon,
            providerID: "permit-card",
            name: "Permit Card",
            setName: "Permit Set",
            setCode: "PRM",
            cardNumber: "1",
            rarity: "Rare",
            imageURL: nil,
            thumbnailURL: nil,
            variant: nil,
            variantResolution: .userConfirmed
        )
        row.itemKindRaw = CollectionItemKind.gradedCard.rawValue
        row.gradingCompanyRaw = GradingCompany.psa.rawValue
        row.gradeRaw = "10"
        seedContext.insert(row)
        try seedContext.save()

        var attempts = 0
        var successfulSaves = 0
        try await CollectionExclusiveWrites.retryingIfRequired {
            attempts += 1
            if attempts == 2 {
                let childWasRejected = await Task { @MainActor in
                    do {
                        try CollectionWriteSerializer.perform(
                            container: container,
                            timeout: .mainThread
                        ) { context in
                            let key = "graded:permit-card#psa-10"
                            var descriptor = FetchDescriptor<CollectedCard>(
                                predicate: #Predicate { $0.collectionKey == key }
                            )
                            descriptor.fetchLimit = 1
                            let current = try XCTUnwrap(context.fetch(descriptor).first)
                            try PriceIdentityLineageMigration.promoteUnboundPriceIdentity(
                                for: current,
                                toMarketVariantID: "child-task-variant",
                                apiVersion: "v2",
                                in: context
                            )
                            throw CancellationError()
                        }
                        return false
                    } catch CollectionStoreError.priceIdentityExclusivityRequired {
                        return true
                    } catch {
                        return false
                    }
                }.value
                XCTAssertTrue(
                    childWasRejected,
                    "An unstructured child task must not inherit the parent's rewrite permit."
                )
            }
            try CollectionWriteSerializer.perform(
                container: container,
                timeout: .mainThread
            ) { context in
                let key = "graded:permit-card#psa-10"
                var descriptor = FetchDescriptor<CollectedCard>(
                    predicate: #Predicate { $0.collectionKey == key }
                )
                descriptor.fetchLimit = 1
                let current = try XCTUnwrap(context.fetch(descriptor).first)
                try PriceIdentityLineageMigration.promoteUnboundPriceIdentity(
                    for: current,
                    toMarketVariantID: "permit-market-variant",
                    apiVersion: "v2",
                    in: context
                )
                current.justTCGCardID = "permit-market-card"
                current.justTCGVariantID = "permit-market-variant"
                current.justTCGAPIVersion = "v2"
                try context.save()
                successfulSaves += 1
            }
        }

        XCTAssertEqual(attempts, 2, "The first unguarded attempt must be retried once under the gate.")
        XCTAssertEqual(successfulSaves, 1, "The ownership write must commit exactly once.")
        let verify = ModelContext(container)
        let saved = try XCTUnwrap(verify.fetch(FetchDescriptor<CollectedCard>()).first)
        XCTAssertEqual(saved.justTCGVariantID, "permit-market-variant")
    }

    func testAddGradedUsesPermitForUnboundSlabIdentityRewrite() async throws {
        let container = try makeContainer(withCard: false)
        let card = try ProductionRowFixtures.pokemonCard()
        let grade = CardGrade(value: "10", label: "Gem Mint")
        let certificationNumber = "permit-add-graded"
        _ = try CollectionWriteSerializer.perform(
            container: container,
            timeout: .wait
        ) { context in
            try CollectionStore(context: context).addScannedGraded(
                underlying: card,
                company: .psa,
                grade: grade,
                certificationNumber: certificationNumber
            )
        }
        let variant = GradedVariant(
            id: "permit-add-graded-variant",
            cardID: "permit-add-graded-card",
            company: .psa,
            grade: grade,
            marketPriceUSD: nil,
            updatedAt: nil
        )

        try await assertIdentityRewriteRequiresPermit(container: container) { context in
            _ = try CollectionStore(context: context).addGraded(
                underlying: card,
                variant: variant,
                certificationNumber: certificationNumber,
                resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed)
            )
        }
    }

    func testAddScannedGradedUsesPermitForVariantIdentityRewrite() async throws {
        let container = try makeContainer(withCard: false)
        let card = try ProductionRowFixtures.pokemonCard()
        let grade = CardGrade(value: "9", label: "Mint")
        let certificationNumber = "permit-add-scanned-graded"
        _ = try CollectionWriteSerializer.perform(
            container: container,
            timeout: .wait
        ) { context in
            try CollectionStore(context: context).addScannedGraded(
                underlying: card,
                company: .psa,
                grade: grade,
                certificationNumber: certificationNumber
            )
        }

        try await assertIdentityRewriteRequiresPermit(container: container) { context in
            _ = try CollectionStore(context: context).addScannedGraded(
                underlying: card,
                company: .psa,
                grade: grade,
                certificationNumber: certificationNumber,
                resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed)
            )
        }
    }

    func testAddSealedUsesPermitForUnboundIdentityPromotion() async throws {
        let container = try makeContainer(withCard: false)
        let product = SealedProductSummary(
            id: "permit-sealed-product",
            name: "Permit Test Box",
            setName: "Permit Set",
            variantID: "permit-sealed-variant",
            marketPriceUSD: nil,
            updatedAt: nil,
            imageURL: nil
        )
        let seed = try CollectionWriteSerializer.perform(
            container: container,
            timeout: .wait
        ) { context in
            try CollectionStore(context: context).addSealed(product, game: .pokemon)
        }
        try CollectionWriteSerializer.perform(
            container: container,
            timeout: .wait
        ) { context in
            let key = seed.collectionKey
            let row = try XCTUnwrap(
                context.fetch(
                    FetchDescriptor<CollectedCard>(
                        predicate: #Predicate { $0.collectionKey == key }
                    )
                ).first
            )
            row.justTCGVariantID = nil
            try context.save()
        }

        try await assertIdentityRewriteRequiresPermit(container: container) { context in
            _ = try CollectionStore(context: context).addSealed(product, game: .pokemon)
        }
    }

    func testRecordVariantCorrectionUsesPermitForGradedIdentityRewrite() async throws {
        let container = try makeContainer(withCard: false)
        let card = try ProductionRowFixtures.pokemonCard()
        let grade = CardGrade(value: "10", label: "Gem Mint")
        let seed = try CollectionWriteSerializer.perform(
            container: container,
            timeout: .wait
        ) { context in
            try CollectionStore(context: context).addScannedGraded(
                underlying: card,
                company: .psa,
                grade: grade,
                certificationNumber: "permit-record-correction"
            )
        }
        let activityID = try XCTUnwrap(seed.activityID)

        try await assertIdentityRewriteRequiresPermit(container: container) { context in
            _ = try CollectionStore(context: context).recordVariantCorrection(
                forCollectionKey: seed.collectionKey,
                to: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
                activityID: activityID,
                quantity: 1
            )
        }
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

    private func assertIdentityRewriteRequiresPermit(
        container: ModelContainer,
        operation: (ModelContext) throws -> Void
    ) async throws {
        let wasEnforced = CollectionWriteSerializer.enforcesOwnershipRule
        CollectionWriteSerializer.enforcesOwnershipRule = true
        defer { CollectionWriteSerializer.enforcesOwnershipRule = wasEnforced }

        do {
            try CollectionWriteSerializer.perform(
                container: container,
                timeout: .wait,
                operation
            )
            XCTFail("The ownership write should require the identity gate.")
        } catch CollectionStoreError.priceIdentityExclusivityRequired {
            // Expected: the first transaction has no gate permit.
        }

        try await CollectionExclusiveWrites.withPriceIdentityExclusivity {
            try CollectionWriteSerializer.perform(
                container: container,
                timeout: .wait,
                operation
            )
        }
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
