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

    func testCatalogAuthorityWithdrawalKeepsMainActorResponsiveAndPreservesUnmanagedPrices() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        for (id, source) in [("managed", PriceSource.tcgCSV), ("imported", .importedCSV)] {
            let record = PriceRecord(key: id, game: .onePiece, printingID: id, variantID: "foil")
            record.sourceRaw = source.rawValue
            record.unitMarketPriceUSD = 12
            record.fetchedAt = .now
            container.mainContext.insert(record)
            let quote = ReferenceQuote(key: id, game: .onePiece, printingID: id, variantID: "foil")
            quote.sourceRaw = source.rawValue
            quote.amount = 12
            container.mainContext.insert(quote)
        }
        try container.mainContext.save()
        let installer = await CatalogPriceAuthorityInstaller.makeBackground(modelContainer: container)
        let locked = expectation(description: "Serialized write held")
        let heartbeat = DispatchSemaphore(value: 0)
        let holder = Task.detached {
            try CollectionWriteSerializer.perform(container: container, timeout: .wait) { _ in
                locked.fulfill()
                return heartbeat.wait(timeout: .now() + 2) == .success
            }
        }
        await fulfillment(of: [locked], timeout: 3)
        DispatchQueue.main.async { heartbeat.signal() }
        try await installer.install(.init(game: .onePiece, managedSources: [.tcgCSV], identityByPriceKey: [:]),
                                    shouldContinue: { true })
        let responsive = try await holder.value
        XCTAssertTrue(responsive, "Authority installation must not block the main queue waiting for a writer")
        let fresh = ModelContext(container)
        let records = try fresh.fetch(FetchDescriptor<PriceRecord>())
        let quotes = try fresh.fetch(FetchDescriptor<ReferenceQuote>())
        XCTAssertNotNil(records.first { $0.key == "managed" }?.invalidatedAt)
        XCTAssertNotNil(quotes.first { $0.key == "managed" }?.invalidatedAt)
        XCTAssertNil(records.first { $0.key == "imported" }?.invalidatedAt)
        XCTAssertNil(quotes.first { $0.key == "imported" }?.invalidatedAt)
        XCTAssertEqual(records.first { $0.key == "imported" }?.unitMarketPriceUSD, 12)
    }

    func testCatalogAuthorityInstallerRejectsObsoleteStorageAndCancelledTask() async throws {
        let container = try ModelContainer(for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let record = PriceRecord(key: "managed", game: .onePiece, printingID: "managed", variantID: "foil")
        record.sourceRaw = PriceSource.tcgCSV.rawValue
        record.unitMarketPriceUSD = 12
        container.mainContext.insert(record)
        try container.mainContext.save()
        let installer = await CatalogPriceAuthorityInstaller.makeBackground(modelContainer: container)
        let authority = GameCatalogPriceAuthority(game: .onePiece, managedSources: [.tcgCSV], identityByPriceKey: [:])
        do {
            try await installer.install(authority, shouldContinue: { false })
            XCTFail("Obsolete storage may not be mutated")
        } catch is CancellationError {}
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await installer.install(authority, shouldContinue: { true })
        }
        do { try await cancelled.value; XCTFail("Cancelled installation must fail") }
        catch is CancellationError {}
        let fresh = ModelContext(container)
        XCTAssertNil(try fresh.fetch(FetchDescriptor<PriceRecord>()).first?.invalidatedAt)
        XCTAssertTrue(try fresh.fetch(FetchDescriptor<PriceObservation>()).isEmpty)
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
        try await assertBackground(await CatalogPriceAuthorityInstaller.makeBackground(modelContainer: container))
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
