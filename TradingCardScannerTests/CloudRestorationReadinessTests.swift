import Foundation
import SwiftData
import XCTest
@testable import TradingCardScanner

private actor CompletionFlag {
    private var completed = false

    func markCompleted() {
        completed = true
    }

    func isCompleted() -> Bool {
        completed
    }
}

@MainActor
final class CloudRestorationReadinessTests: XCTestCase {
    private let storeID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let requestGeneration: UInt = 7
    private let targetStoreIdentifier = "target-store"

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func makeRequest(
        generation: UInt? = nil,
        anchorGeneration: String = "generation-a"
    ) -> CloudRestorationRequest {
        CloudRestorationRequest(
            bootstrapGeneration: generation ?? requestGeneration,
            storeID: storeID,
            expectedAnchorGeneration: anchorGeneration,
            accountFingerprint: "account-a",
            anchorClaimedThisLaunch: false
        )
    }

    private func makeEvent(
        identifier: String,
        type: RedactedCloudKitEvent.EventType = .import,
        storeIdentifier: String = "target-store",
        startOffset: TimeInterval,
        endOffset: TimeInterval? = nil,
        succeeded: Bool,
        errorCategory: String = "none"
    ) -> RedactedCloudKitEvent {
        let startDate = Date(timeIntervalSinceReferenceDate: 10_000 + startOffset)
        let endDate = endOffset.map {
            Date(timeIntervalSinceReferenceDate: 10_000 + $0)
        }
        return RedactedCloudKitEvent(
            identifier: UUID(uuidString: identifier)!,
            type: type,
            storeIdentifier: storeIdentifier,
            startDate: startDate,
            endDate: endDate,
            succeeded: succeeded,
            errorCategory: errorCategory
        )
    }

    private func makeSource(
        notificationCenter: NotificationCenter = NotificationCenter(),
        visibleRowCount: Int = 1,
        visibilityCalls: (@MainActor () -> Void)? = nil,
        correlationTarget: String? = "target-store",
        allowReadyEmpty: Bool = false
    ) -> CloudKitEventReadinessSource {
        CloudKitEventReadinessSource(
            notificationCenter: notificationCenter,
            visibilityProvider: { _ in
                visibilityCalls?()
                return CloudRestorationVisibilitySnapshot(
                    visibleRowCount: visibleRowCount
                )
            },
            correlationTargetResolver: { _ in correlationTarget },
            allowReadyEmpty: allowReadyEmpty
        )
    }

    private func arm(
        source: CloudKitEventReadinessSource,
        generation: UInt? = nil
    ) -> CloudKitEventReadinessProbe {
        source.arm(makeRequest(generation: generation)) as! CloudKitEventReadinessProbe
    }

    private func makePreResolvedProbe(
        correlation: CloudKitEventReadinessCorrelation,
        visibleRowCount: Int = 1,
        notificationCenter: NotificationCenter = NotificationCenter(),
        isCurrent: @escaping @MainActor () -> Bool = { true }
    ) -> CloudKitEventReadinessProbe {
        CloudKitEventReadinessProbe(
            request: makeRequest(),
            notificationCenter: notificationCenter,
            visibilityProvider: { _ in
                CloudRestorationVisibilitySnapshot(visibleRowCount: visibleRowCount)
            },
            correlationTargetResolver: { _ in nil },
            allowReadyEmpty: false,
            isCurrent: isCurrent,
            preResolvedCorrelation: correlation
        )
    }

    func testUnprovenProductionSourceFailsClosed() async throws {
        let source = UnprovenCloudRestorationReadinessSource()
        let probe = source.arm(makeRequest())
        let result = await probe.awaitReadiness(container: try makeContainer())

        XCTAssertEqual(result, .failed(category: "restoration-readiness-not-proven"))
        XCTAssertFalse(result.isReady)
    }

    func testFixedSourcePreservesEmptyAndPopulatedEvidence() async throws {
        for expected in [
            CloudRestorationReadiness.readyEmpty,
            .readyPopulated
        ] {
            let source = FixedCloudRestorationReadinessSource(result: expected)
            let probe = source.arm(makeRequest(generation: 8))
            let result = await probe.awaitReadiness(container: try makeContainer())

            XCTAssertEqual(result, expected)
            XCTAssertTrue(result.isReady)
        }
    }

    func testImportingAndFailureStatesAreNeverReady() {
        let states: [CloudRestorationReadiness] = [
            .notApplicable,
            .checkingRemoteCollection,
            .importingRemoteCollection,
            .failed(category: "import-not-proven")
        ]
        for state in states {
            XCTAssertFalse(state.isReady)
        }
    }

    func testReadinessContractVersionIsThree() {
        XCTAssertEqual(CloudRestorationReadinessContract.currentMechanismVersion, 3)
    }

    func testSetupCompletionIsInsufficient() async throws {
        var visibilityCallCount = 0
        let source = makeSource(
            visibleRowCount: 10,
            visibilityCalls: { visibilityCallCount += 1 }
        )
        let probe = arm(source: source)
        defer { probe.cancel() }
        probe.ingest(makeEvent(
            identifier: "00000000-0000-0000-0000-000000000001",
            type: .setup,
            startOffset: 1,
            endOffset: 2,
            succeeded: true
        ))

        let result = await probe.awaitReadiness(container: try makeContainer())

        XCTAssertEqual(result, .checkingRemoteCollection)
        XCTAssertEqual(visibilityCallCount, 0)
    }

    func testExportCompletionIsInsufficient() async throws {
        let source = makeSource(visibleRowCount: 10)
        let probe = arm(source: source)
        defer { probe.cancel() }
        probe.ingest(makeEvent(
            identifier: "00000000-0000-0000-0000-000000000002",
            type: .export,
            startOffset: 1,
            endOffset: 2,
            succeeded: true
        ))

        let result = await probe.awaitReadiness(container: try makeContainer())

        XCTAssertEqual(result, .checkingRemoteCollection)
    }

    func testSuccessfulImportForAnotherStoreIsIgnored() async throws {
        var visibilityCallCount = 0
        let source = makeSource(
            visibilityCalls: { visibilityCallCount += 1 }
        )
        let probe = arm(source: source)
        defer { probe.cancel() }
        probe.ingest(makeEvent(
            identifier: "00000000-0000-0000-0000-000000000003",
            storeIdentifier: "other-store",
            startOffset: 1,
            endOffset: 2,
            succeeded: true
        ))

        let firstResult = await probe.awaitReadiness(container: try makeContainer())
        XCTAssertEqual(firstResult, .checkingRemoteCollection)
        XCTAssertEqual(visibilityCallCount, 0)

        probe.ingest(makeEvent(
            identifier: "00000000-0000-0000-0000-000000000004",
            startOffset: 3,
            endOffset: 4,
            succeeded: true
        ))
        let secondResult = await probe.awaitReadiness(container: try makeContainer())
        XCTAssertEqual(secondResult, .readyPopulated)
        XCTAssertEqual(visibilityCallCount, 1)
    }

    func testSecondDistinctStoreIdentifierFailsClosedForSingletonCorrelation() async throws {
        let probe = makePreResolvedProbe(correlation: .singleton)
        defer { probe.cancel() }
        probe.ingest(makeEvent(
            identifier: "00000000-0000-0000-0000-000000000005",
            storeIdentifier: "store-a",
            startOffset: 1,
            endOffset: 2,
            succeeded: true
        ))
        probe.ingest(makeEvent(
            identifier: "00000000-0000-0000-0000-000000000006",
            storeIdentifier: "store-b",
            startOffset: 3,
            endOffset: 4,
            succeeded: true
        ))

        let result = await probe.awaitReadiness(container: try makeContainer())

        XCTAssertEqual(
            result,
            .failed(category: "restoration-readiness-multiple-store-identifiers")
        )
    }

    func testFailedImportNeverBecomesReady() async throws {
        let source = makeSource(visibleRowCount: 10)
        let probe = arm(source: source)
        defer { probe.cancel() }
        probe.ingest(makeEvent(
            identifier: "00000000-0000-0000-0000-000000000007",
            startOffset: 1,
            endOffset: 2,
            succeeded: false,
            errorCategory: "network"
        ))

        let result = await probe.awaitReadiness(container: try makeContainer())

        XCTAssertEqual(result, .failed(category: "network"))
        XCTAssertFalse(result.isReady)
    }

    func testIncompleteImportRemainsImportingWithoutAClockOrTimer() async throws {
        let source = makeSource(visibleRowCount: 10)
        let probe = arm(source: source)
        defer { probe.cancel() }
        probe.ingest(makeEvent(
            identifier: "00000000-0000-0000-0000-000000000008",
            startOffset: 1,
            succeeded: false
        ))
        let firstResult = await probe.awaitReadiness(container: try makeContainer())
        XCTAssertEqual(firstResult, .importingRemoteCollection)

        let flag = CompletionFlag()
        let container = try makeContainer()
        let task = Task {
            let result = await probe.awaitReadiness(container: container)
            await flag.markCompleted()
            return result
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        let completedDuringWallClockPassage = await flag.isCompleted()
        XCTAssertFalse(completedDuringWallClockPassage)

        probe.cancel()
        let cancelledResult = await task.value
        XCTAssertEqual(cancelledResult, .failed(category: "restoration-readiness-cancelled"))
    }

    func testRowsAreQueriedOnlyAfterImportCompletionBoundary() async throws {
        var visibilityCallCount = 0
        let source = makeSource(
            visibleRowCount: 3,
            visibilityCalls: { visibilityCallCount += 1 }
        )
        let probe = arm(source: source)
        defer { probe.cancel() }
        probe.ingest(makeEvent(
            identifier: "00000000-0000-0000-0000-000000000009",
            type: .setup,
            startOffset: 1,
            endOffset: 2,
            succeeded: true
        ))
        let beforeImport = await probe.awaitReadiness(container: try makeContainer())
        XCTAssertEqual(beforeImport, .checkingRemoteCollection)
        XCTAssertEqual(visibilityCallCount, 0)

        probe.ingest(makeEvent(
            identifier: "00000000-0000-0000-0000-00000000000A",
            startOffset: 3,
            endOffset: 4,
            succeeded: true
        ))
        let afterImport = await probe.awaitReadiness(container: try makeContainer())
        XCTAssertEqual(afterImport, .readyPopulated)
        XCTAssertEqual(visibilityCallCount, 1)
    }

    func testPopulatedRowsYieldReadyPopulated() async throws {
        let source = makeSource(visibleRowCount: 1)
        let probe = arm(source: source)
        defer { probe.cancel() }
        probe.ingest(makeEvent(
            identifier: "00000000-0000-0000-0000-00000000000B",
            startOffset: 1,
            endOffset: 2,
            succeeded: true
        ))

        let result = await probe.awaitReadiness(container: try makeContainer())
        XCTAssertEqual(result, .readyPopulated)
    }

    func testZeroRowsDoNotYieldReadyEmptyByDefault() async throws {
        let source = makeSource(visibleRowCount: 0)
        let probe = arm(source: source)
        defer { probe.cancel() }
        probe.ingest(makeEvent(
            identifier: "00000000-0000-0000-0000-00000000000C",
            startOffset: 1,
            endOffset: 2,
            succeeded: true
        ))

        let result = await probe.awaitReadiness(container: try makeContainer())
        XCTAssertEqual(result, .importingRemoteCollection)
    }

    func testEntitledEmptyProofCanBeExplicitlyEnabled() async throws {
        let source = makeSource(visibleRowCount: 0, allowReadyEmpty: true)
        let probe = arm(source: source)
        defer { probe.cancel() }
        probe.ingest(makeEvent(
            identifier: "00000000-0000-0000-0000-00000000000D",
            startOffset: 1,
            endOffset: 2,
            succeeded: true
        ))

        let result = await probe.awaitReadiness(container: try makeContainer())
        XCTAssertEqual(result, .readyEmpty)
    }

    func testNewerInProgressImportPreventsReady() async throws {
        let source = makeSource(visibleRowCount: 10)
        let probe = arm(source: source)
        defer { probe.cancel() }
        probe.ingest(makeEvent(
            identifier: "00000000-0000-0000-0000-00000000000E",
            startOffset: 1,
            endOffset: 2,
            succeeded: true
        ))
        probe.ingest(makeEvent(
            identifier: "00000000-0000-0000-0000-00000000000F",
            startOffset: 3,
            succeeded: false
        ))

        let result = await probe.awaitReadiness(container: try makeContainer())
        XCTAssertEqual(result, .importingRemoteCollection)
    }

    func testNewerFailedImportPreventsReady() async throws {
        let source = makeSource(visibleRowCount: 10)
        let probe = arm(source: source)
        defer { probe.cancel() }
        probe.ingest(makeEvent(
            identifier: "00000000-0000-0000-0000-000000000010",
            startOffset: 1,
            endOffset: 2,
            succeeded: true
        ))
        probe.ingest(makeEvent(
            identifier: "00000000-0000-0000-0000-000000000011",
            startOffset: 3,
            endOffset: 4,
            succeeded: false,
            errorCategory: "service"
        ))

        let result = await probe.awaitReadiness(container: try makeContainer())
        XCTAssertEqual(result, .failed(category: "service"))
    }

    func testStaleBootstrapGenerationIsDiscarded() async throws {
        let probe = makePreResolvedProbe(
            correlation: .explicit(targetStoreIdentifier),
            isCurrent: { false }
        )
        defer { probe.cancel() }
        probe.ingest(makeEvent(
            identifier: "00000000-0000-0000-0000-000000000012",
            startOffset: 1,
            endOffset: 2,
            succeeded: true
        ))

        let result = await probe.awaitReadiness(container: try makeContainer())
        XCTAssertEqual(result, .failed(category: "restoration-readiness-stale-generation"))
    }

    func testAccountChangeTerminatesProbe() async throws {
        let notificationCenter = NotificationCenter()
        let source = makeSource(notificationCenter: notificationCenter)
        let probe = arm(source: source)
        let task = Task {
            await probe.awaitReadiness(container: try! makeContainer())
        }
        try await Task.sleep(nanoseconds: 20_000_000)

        notificationCenter.post(name: .CKAccountChanged, object: nil)
        let result = await task.value

        XCTAssertEqual(result, .failed(category: "restoration-readiness-account-changed"))
        XCTAssertEqual(probe.registeredObserverCount, 0)
    }

    func testCancelIsIdempotentAndDeregistersBothObservers() async throws {
        let source = makeSource()
        let probe = arm(source: source)
        XCTAssertEqual(probe.registeredObserverCount, 2)

        probe.cancel()
        probe.cancel()

        XCTAssertEqual(probe.registeredObserverCount, 0)
        let result = await probe.awaitReadiness(container: try makeContainer())
        XCTAssertEqual(result, .failed(category: "restoration-readiness-cancelled"))
    }
}
