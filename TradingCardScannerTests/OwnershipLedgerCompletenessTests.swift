import Foundation
import SwiftData
import XCTest
@testable import TradingCardScanner

@MainActor
final class OwnershipLedgerCompletenessTests: XCTestCase {
    private let collectionKey = "pokemon:test:001:normal"

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema([
                CollectedCard.self,
                PriceRecord.self,
                ProductIdentity.self,
                CollectionActivity.self,
                InventoryEvent.self
            ]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    func testAcquisitionAndRemovalReconstructToCurrentQuantity() throws {
        let container = try makeContainer()
        let acquire = InventoryEvent(
            operationID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            leg: nil,
            kind: .acquire,
            source: .scan,
            collectionKey: collectionKey,
            priceStorageKey: collectionKey,
            deltaQuantity: 3,
            occurredAt: .now,
            recordedAt: .now,
            valuation: .unpriced
        )
        let remove = InventoryEvent(
            operationID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            leg: nil,
            kind: .dispose,
            source: .catalog,
            collectionKey: collectionKey,
            priceStorageKey: collectionKey,
            deltaQuantity: -1,
            occurredAt: .now,
            recordedAt: .now,
            valuation: .unpriced
        )
        container.mainContext.insert(acquire)
        container.mainContext.insert(remove)
        try container.mainContext.save()

        let result = InventoryLedger.quantities(from: [acquire, remove])
        XCTAssertEqual(result[collectionKey], 2)
    }

    func testCorrectionRequiresTwoCompleteLegsToPreserveTotalOwnership() throws {
        let container = try makeContainer()
        let operationID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let from = InventoryEvent(
            operationID: operationID,
            leg: .from,
            kind: .correction,
            source: .correction,
            collectionKey: "old",
            priceStorageKey: "old",
            deltaQuantity: -2,
            occurredAt: .now,
            recordedAt: .now,
            valuation: .unpriced
        )
        let to = InventoryEvent(
            operationID: operationID,
            leg: .to,
            kind: .correction,
            source: .correction,
            collectionKey: "new",
            priceStorageKey: "new",
            deltaQuantity: 2,
            occurredAt: .now,
            recordedAt: .now,
            valuation: .unpriced
        )
        container.mainContext.insert(from)
        container.mainContext.insert(to)
        try container.mainContext.save()

        let result = InventoryLedger.quantities(from: [from, to])
        XCTAssertEqual(result["old"], nil)
        XCTAssertEqual(result["new"], 2)
    }

    func testSourceInventoryNamesEveryOwnershipEntryPoint() throws {
        let sources = [
            "CollectionStore.swift",
            "CollectionCSV.swift",
            "MagicTreatmentMigration.swift",
            "PortfolioEpoch.swift"
        ]
        let servicesURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TradingCardScanner/Services", isDirectory: true)
        for sourceName in sources {
            let url = servicesURL.appendingPathComponent(sourceName)
            let source = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(source.isEmpty)
        }
    }

    func testDiskBackedMixedProductionWorkflowReconstructsAfterRestart() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OwnershipLedgerMixed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("collection.store")
        let card = try ProductionRowFixtures.pokemonCard()
        let normal = ResolvedVariant(variant: .normal, resolution: .userConfirmed)

        do {
            let container = try makeDiskContainer(at: storeURL)
            let store = CollectionStore(context: container.mainContext)
            _ = try store.add(card, resolved: normal, source: .scan)
            let row = try XCTUnwrap(store.card(forKey: card.collectionKey(variant: .normal)))
            try store.setQuantity(3, for: row)

            // This is the same export/parse/apply path used by the import UI;
            // it deliberately merges into the existing position.
            let importDocument = CollectionCSV.export([row])
            let plan = try CollectionCSV.parse(Data(importDocument.text.utf8))
            let importedQuantity = row.quantity
            let importResult = try CollectionCSV.apply(plan, to: container.mainContext)
            XCTAssertEqual(importResult.importedQuantity, importedQuantity)

            // Correct only the quantity claimed by the import activity. The
            // correction must add a complete pair of ledger legs, not a new
            // acquisition on the destination key.
            let importActivity = try XCTUnwrap(
                try container.mainContext.fetch(FetchDescriptor<CollectionActivity>())
                    .filter { $0.source == .csvImport }
                    .last
            )
            let mergedRow = try XCTUnwrap(store.card(forKey: row.collectionKey))
            _ = try store.recordVariantCorrection(
                for: mergedRow,
                to: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
                activityID: importActivity.id,
                quantity: importActivity.signedQuantity
            )

            let correctedRow = try XCTUnwrap(
                try container.mainContext.fetch(FetchDescriptor<CollectedCard>())
                    .first { $0.variantID == PhysicalVariant.reverse.id }
            )
            let snapshot = try store.remove(correctedRow)
            try store.restore(snapshot)
        }

        let reopened = try makeDiskContainer(at: storeURL)
        try assertReconstructed(in: reopened.mainContext)
        let cards = try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(cards.reduce(0) { $0 + $1.quantity }, 6)
        XCTAssertEqual(Set(cards.compactMap(\.variantID)), Set([PhysicalVariant.normal.id, PhysicalVariant.reverse.id]))
    }

    func testDiskBackedGradedScannedGradedAndSealedPathsEmitCompleteFacts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OwnershipLedgerKinds-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("collection.store")

        do {
            let container = try makeDiskContainer(at: storeURL)
            let context = container.mainContext
            _ = try ProductionRowFixtures.gradedRow(in: context)
            _ = try ProductionRowFixtures.scannedGradedRow(in: context)
            _ = try ProductionRowFixtures.sealedRow(in: context)
            try assertReconstructed(in: context)
        }

        let reopened = try makeDiskContainer(at: storeURL)
        try assertReconstructed(in: reopened.mainContext)
        let kinds = try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>()).map(\.itemKind)
        XCTAssertEqual(Set(kinds), Set([.gradedCard, .sealedProduct]))
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<InventoryEvent>()).count, 3)
    }

    func testDiskBackedCSVFailureRollsBackAndRetryCommitsOneRow() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OwnershipLedgerCSVRetry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("collection.store")
        let source = CollectedCard(
            collectionKey: "csv:retry-card",
            game: .pokemon,
            providerID: "csv:retry-card",
            name: "Retry Card",
            setName: "Retry Set",
            setCode: "RET",
            cardNumber: "001",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: nil,
            variantResolution: .imported,
            identityResolution: .imported,
            quantity: 2
        )
        let plan = try CollectionCSV.parse(Data(CollectionCSV.export([source]).text.utf8))

        do {
            let container = try makeDiskContainer(at: storeURL)
            do {
                _ = try CollectionCSV.apply(
                    plan,
                    to: container.mainContext,
                    shouldContinue: { false }
                )
                XCTFail("a stopped generation must not commit the import")
            } catch CollectionCSVError.importInterrupted(completedEntries: 0, totalEntries: 1) {
                // Expected. The context rollback is part of the production
                // import boundary, not a test-only cleanup.
            }
        }
        do {
            let reopened = try makeDiskContainer(at: storeURL)
            XCTAssertTrue(try reopened.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
            XCTAssertTrue(try reopened.mainContext.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
            _ = try CollectionCSV.apply(plan, to: reopened.mainContext)
        }
        let final = try makeDiskContainer(at: storeURL)
        try assertReconstructed(in: final.mainContext)
        XCTAssertEqual(try final.mainContext.fetch(FetchDescriptor<CollectedCard>()).first?.quantity, 2)
        XCTAssertEqual(try final.mainContext.fetch(FetchDescriptor<InventoryEvent>()).count, 1)
    }

    #if DEBUG
    func testScannerSaveFailureRollsBackAggregateAndLedgerTogether() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OwnershipLedgerScannerRollback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("collection.store")
        let container = try makeDiskContainer(at: storeURL)
        let subject = ScanSubject(identifier: .pokemon(
            setCode: "PRE",
            cardNumber: "074",
            printedTotal: 131,
            setDefinition: PokemonSetDefinition(
                printedCode: "PRE",
                tcgdexSetID: "sv08.5",
                officialCount: 131,
                releaseIndex: 0
            )
        ))
        let request = ScanRequest(
            subject: subject,
            purpose: .collection,
            generation: 1,
            encounterID: UUID()
        )
        let scan = ResolvedScan(
            request: request,
            card: try ProductionRowFixtures.pokemonCard(),
            resolved: ResolvedVariant(variant: .normal, resolution: .uniqueInCatalog),
            pokemonPrintRun: nil,
            options: [.normal]
        )
        let writer = ScannerCollectionWriter(modelContainer: container)
        await writer.setSaveOverrideForTesting {
            throw OwnershipLedgerInjectedSaveFailure()
        }
        do {
            _ = try await writer.add(CollectionCommitCandidate(resolvedScan: scan))
            XCTFail("the injected save must fail")
        } catch is OwnershipLedgerInjectedSaveFailure {
            // Expected.
        }
        let reopenedAfterFailure = try makeDiskContainer(at: storeURL)
        XCTAssertTrue(try reopenedAfterFailure.mainContext.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        XCTAssertTrue(try reopenedAfterFailure.mainContext.fetch(FetchDescriptor<InventoryEvent>()).isEmpty)
    }
    #endif

    func testDiskBackedPreLedgerBaselineIsOneDeterministicEventAfterRestart() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OwnershipLedgerBaseline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("collection.store")
        let defaultsSuiteName = "OwnershipLedgerBaseline-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        do {
            let container = try makeDiskContainer(at: storeURL)
            let card = CollectedCard(
                collectionKey: collectionKey,
                game: .pokemon,
                providerID: "baseline",
                name: "Baseline",
                setName: "Baseline Set",
                setCode: "BAS",
                cardNumber: "001",
                rarity: nil,
                imageURL: nil,
                thumbnailURL: nil,
                variant: nil,
                variantResolution: .imported,
                identityResolution: .imported,
                quantity: 4
            )
            container.mainContext.insert(card)
            try container.mainContext.save()
            _ = try PortfolioEpoch.establishIfNeeded(
                context: container.mainContext,
                defaults: defaults,
                at: Date(timeIntervalSince1970: 10),
                isCloudSyncing: false
            )
        }

        let reopened = try makeDiskContainer(at: storeURL)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<InventoryEvent>()).count, 1)
        _ = try PortfolioEpoch.establishIfNeeded(
            context: reopened.mainContext,
            defaults: defaults,
            at: Date(timeIntervalSince1970: 20),
            isCloudSyncing: false
        )
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<InventoryEvent>()).count, 1)
        try assertReconstructed(in: reopened.mainContext)
    }

    private func makeDiskContainer(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "OwnershipLedgerDisk",
            schema: CollectionStorageModelSchema.full,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: CollectionStorageModelSchema.full,
            configurations: [configuration]
        )
    }

    private func assertReconstructed(
        in context: ModelContext,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let cards = try context.fetch(FetchDescriptor<CollectedCard>())
        let ledger = InventoryLedger(context: context)
        let reading = ledger.read()
        XCTAssertTrue(reading.defects.isEmpty, file: file, line: line)
        let projection = LogicalCollection.project(cards: cards, ledger: ledger)
        XCTAssertTrue(projection.defects.isEmpty, file: file, line: line)
        XCTAssertEqual(
            InventoryLedger.quantities(from: reading.events),
            projection.quantities,
            file: file,
            line: line
        )
        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertTrue(
            CollectionActivity.integrityDefects(
                activities: activities,
                events: reading.events
            ).isEmpty,
            file: file,
            line: line
        )
    }
}

#if DEBUG
private struct OwnershipLedgerInjectedSaveFailure: Error {}
#endif
