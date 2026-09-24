import SwiftData
import XCTest
@testable import TradingCardScanner

@MainActor
final class CSVImportResumeTests: XCTestCase {
    func testInterruptedImportResumesOnlyEntriesWithoutLedgerEvents() throws {
        let container = try makeContainer()
        let plan = try parsedPlan(rows: [
            "a,Card A,Set,SET,1,2",
            "b,Card B,Set,SET,2,3",
            "c,Card C,Set,SET,3,1"
        ])
        let stopFlag = CollectionCSVImportStopFlag()

        XCTAssertThrowsError(
            try CollectionCSV.apply(
                plan,
                to: ModelContext(container),
                batchSize: 1,
                progress: { completed, _ in
                    if completed == 1 { stopFlag.requestStop() }
                },
                shouldContinue: { stopFlag.shouldContinue }
            )
        ) { error in
            guard case let CollectionCSVError.importInterrupted(completedEntries, totalEntries) = error else {
                return XCTFail("Unexpected import error: \(error)")
            }
            XCTAssertEqual(completedEntries, 1)
            XCTAssertEqual(totalEntries, 3)
            XCTAssertTrue(error.localizedDescription.contains("Import the same file again"))
        }

        let resumed = try CollectionCSV.apply(plan, to: ModelContext(container))
        XCTAssertEqual(resumed.alreadyImportedEntries, 1)
        XCTAssertEqual(resumed.importedQuantity, 4)
        XCTAssertEqual(
            try storedQuantities(in: container),
            Dictionary(uniqueKeysWithValues: plan.entries.map { ($0.collectionKey, $0.quantity) })
        )
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<InventoryEvent>()).count, 3)
    }

    func testImportAgainUsesFreshSaltAndModifiedQuantityIsANewFile() throws {
        let container = try makeContainer()
        let original = try parsedPlan(rows: ["a,Card A,Set,SET,1,2"])
        let equivalent = try CollectionCSV.parse(Data(
            "provider_id,card_name,set_name,set_code,card_number,quantity\r\na, Card A, Set, SET, 1, 2\r\n".utf8
        ))
        XCTAssertEqual(original.effectiveFingerprint, equivalent.effectiveFingerprint)
        XCTAssertEqual(original.operationID(for: original.entries[0]), equivalent.operationID(for: equivalent.entries[0]))

        _ = try CollectionCSV.apply(original, to: ModelContext(container))
        let repeated = try CollectionCSV.apply(original, to: ModelContext(container))
        XCTAssertEqual(repeated.alreadyImportedEntries, 1)
        XCTAssertEqual(try storedQuantities(in: container).values.first, 2)

        let allAgain = original.importingAgainAsAdditionalCopies()
        XCTAssertNotEqual(original.operationID(for: original.entries[0]), allAgain.operationID(for: allAgain.entries[0]))
        _ = try CollectionCSV.apply(allAgain, to: ModelContext(container))
        XCTAssertEqual(try storedQuantities(in: container).values.first, 4)

        let changed = try parsedPlan(rows: ["a,Card A,Set,SET,1,3"])
        XCTAssertNotEqual(original.effectiveFingerprint, changed.effectiveFingerprint)
        _ = try CollectionCSV.apply(changed, to: ModelContext(container))
        XCTAssertEqual(try storedQuantities(in: container).values.first, 7)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<InventoryEvent>()).count, 3)
    }

    func testRemainingImportRecognizesAnEntryAfterItsKeyWasRewritten() throws {
        let container = try makeContainer()
        let plan = try parsedPlan(rows: ["a,Card A,Set,SET,1,2"])
        _ = try CollectionCSV.apply(plan, to: ModelContext(container))

        let context = ModelContext(container)
        let row = try XCTUnwrap(context.fetch(FetchDescriptor<CollectedCard>()).first)
        let oldKey = row.collectionKey
        let newKey = "pokemon:normalized:\(UUID().uuidString.lowercased())"
        _ = try CollectionStore(context: context).rekey(row, to: newKey)
        try context.save()
        let event = try XCTUnwrap(
            ModelContext(container).fetch(FetchDescriptor<InventoryEvent>()).first
        )
        XCTAssertEqual(event.collectionKey, newKey)
        XCTAssertNotEqual(event.collectionKey, oldKey)

        let resumed = try CollectionCSV.apply(plan, to: ModelContext(container))
        XCTAssertEqual(resumed.failedRows.count, 0)
        XCTAssertEqual(resumed.alreadyImportedEntries, 1)
        XCTAssertEqual(try storedQuantities(in: container).values.first, 2)
    }

    func testInterruptedImportAllAgainKeepsItsOperationSaltOnResume() throws {
        let container = try makeContainer()
        let original = try parsedPlan(rows: [
            "a,Card A,Set,SET,1,2",
            "b,Card B,Set,SET,2,3"
        ])
        _ = try CollectionCSV.apply(original, to: ModelContext(container))

        let firstAttempt = original.importingAgainAsAdditionalCopies()
        let stopFlag = CollectionCSVImportStopFlag()
        XCTAssertThrowsError(
            try CollectionCSV.apply(
                firstAttempt,
                to: ModelContext(container),
                batchSize: 1,
                progress: { completed, _ in
                    if completed == 1 { stopFlag.requestStop() }
                },
                shouldContinue: { stopFlag.shouldContinue }
            )
        )

        let resumedAttempt = original.importingAgainAsAdditionalCopies()
        XCTAssertEqual(
            firstAttempt.operationID(for: firstAttempt.entries[0]),
            resumedAttempt.operationID(for: resumedAttempt.entries[0])
        )
        let resumed = try CollectionCSV.apply(resumedAttempt, to: ModelContext(container))
        XCTAssertEqual(resumed.alreadyImportedEntries, 1)
        XCTAssertEqual(resumed.importedQuantity, 3)
        XCTAssertEqual(
            Set(try storedQuantities(in: container).values),
            Set([4, 6])
        )
        CollectionCSV.finishImportAgainRun(resumedAttempt)
    }

    func testStorageGenerationChangeStopsAtDurableRowBoundary() throws {
        let container = try makeContainer()
        let plan = try parsedPlan(rows: [
            "a,Card A,Set,SET,1,1",
            "b,Card B,Set,SET,2,1"
        ])
        let stopFlag = CollectionCSVImportStopFlag()
        // Flip the flag after entry one's save, exactly like the storage
        // generation continuation changing while a multi-row import runs.
        XCTAssertThrowsError(
            try CollectionCSV.apply(
                plan,
                to: ModelContext(container),
                batchSize: 1,
                progress: { completed, _ in
                    if completed == 1 { stopFlag.requestStop() }
                },
                shouldContinue: { stopFlag.shouldContinue }
            )
        ) { error in
            guard case let CollectionCSVError.importInterrupted(completedEntries, _) = error else {
                return XCTFail("Unexpected import error: \(error)")
            }
            XCTAssertEqual(completedEntries, 1)
        }
        let resumed = try CollectionCSV.apply(plan, to: ModelContext(container))
        XCTAssertEqual(resumed.alreadyImportedEntries, 1)
        XCTAssertEqual(resumed.importedQuantity, 1)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<InventoryEvent>()).count, 2)
    }

    private func parsedPlan(rows: [String]) throws -> CollectionCSVImportPlan {
        let csv = (["provider_id,card_name,set_name,set_code,card_number,quantity"] + rows)
            .joined(separator: "\n") + "\n"
        return try CollectionCSV.parse(Data(csv.utf8))
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func storedQuantities(in container: ModelContainer) throws -> [String: Int] {
        Dictionary(
            uniqueKeysWithValues: try ModelContext(container)
                .fetch(FetchDescriptor<CollectedCard>())
                .map { ($0.collectionKey, $0.quantity) }
        )
    }
}
