import Foundation
import SwiftData
import XCTest
@testable import TradingCardScanner

@MainActor
final class LaunchModelActorTests: XCTestCase {
    /// Probe the actor's executor, after a real database read. Checking only
    /// the thread that creates the task misses a main-queue model context.
    func testLaunchDatabaseWorkersDoNotExecuteOnMainThread() async throws {
        try await assertWorkers(configuration: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func testDiskBackedLaunchWorkersDoNotExecuteOnMainThread() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchModelActorTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await assertWorkers(configuration: ModelConfiguration(
            url: directory.appendingPathComponent("fixture.store"), cloudKitDatabase: .none
        ))
    }

    private func assertWorkers(configuration: ModelConfiguration) async throws {
        let container = try ModelContainer(
            for: CollectionStorageModelSchema.full,
            configurations: [configuration]
        )
        let card = CollectedCard(
            collectionKey: "launch-fixture#normal", game: .pokemon,
            providerID: "launch-fixture", name: "Launch Fixture",
            setName: "Fixture", setCode: "FIX", cardNumber: "1",
            rarity: nil, imageURL: nil, thumbnailURL: nil, variant: .normal,
            variantResolution: .userConfirmed
        )
        container.mainContext.insert(card)
        try container.mainContext.save()

        try await assertBackground(await PortfolioComputationActor.makeBackground(modelContainer: container))
        try await assertBackground(await CollectionProjectionActor.makeBackground(modelContainer: container))
        try await assertBackground(await PriceSnapshotModelActor.makeBackground(modelContainer: container))
        try await assertBackground(await StoreRevisionModelActor.makeBackground(modelContainer: container))
        try await assertBackground(await PriceRefreshTargetModelActor.makeBackground(modelContainer: container))
        try await assertBackground(await PriceRefreshModelActor.makeBackground(modelContainer: container))
        try await assertBackground(await ScannerCollectionWriter.makeBackground(modelContainer: container))
        try await assertBackground(await CollectionDetailQuantityReader.makeBackground(modelContainer: container))
        try await assertBackground(await CollectionDetailWriter.makeBackground(modelContainer: container))
        try await assertBackground(await CollectionActivityWriter.makeBackground(modelContainer: container))
        try await assertBackground(await CollectionDeletionModelActor.makeBackground(modelContainer: container))
        try await assertBackground(await CollectionCSVExportActor.makeBackground(modelContainer: container))
        try await assertBackground(await CollectionCSVImportActor.makeBackground(modelContainer: container))
        try await assertBackground(await CollectionStoreDigestActor.makeBackground(modelContainer: container))
        try await assertBackground(await CollectionCatalogNormalizationInputActor.makeBackground(modelContainer: container))
    }

    private func assertBackground<T: ModelActor>(
        _ worker: T, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        XCTAssertTrue(worker.modelExecutor is BackgroundSerialModelExecutor,
                      "\(T.self) must use the dedicated background executor", file: file, line: line)
        let probe = try await worker.launchExecutionProbe()
        XCTAssertEqual(probe.names, ["Launch Fixture"], file: file, line: line)
        XCTAssertFalse(probe.isMainThread, "\(T.self) uses the UI thread", file: file, line: line)
    }
}

private extension ModelActor {
    func launchExecutionProbe() throws -> (names: [String], isMainThread: Bool) {
        let names = try modelContext.fetch(FetchDescriptor<CollectedCard>()).map(\.name)
        return (names, Thread.isMainThread)
    }
}
