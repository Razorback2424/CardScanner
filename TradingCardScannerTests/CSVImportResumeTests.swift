import SwiftData
import XCTest
@testable import TradingCardScanner

@MainActor
final class CSVImportResumeTests: XCTestCase {
    func testCertifiedImportsShareOneOwnerAcrossBoundAndUnboundKeys() throws {
        for boundFirst in [true, false] {
            let container = try makeContainer()
            let bound = try certifiedEntry(marketVariant: "market-slab")
            let unbound = try certifiedEntry()
            let entries = boundFirst ? [bound, unbound] : [unbound, bound]
            for entry in entries {
                let result = try CollectionCSV.apply(.init(entries: [entry], skippedRows: 0,
                    skippedCSVText: nil), to: ModelContext(container))
                XCTAssertTrue(result.failedRows.isEmpty)
            }
            let context = ModelContext(container)
            let rows = try context.fetch(FetchDescriptor<CollectedCard>())
            XCTAssertEqual(rows.count, 1)
            let owner = try XCTUnwrap(rows.first)
            XCTAssertEqual(owner.quantity, 1)
            XCTAssertEqual(owner.collectionKey, entries[0].collectionKey)
            XCTAssertEqual(owner.justTCGVariantID, "market-slab")
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<InventoryEvent>()), 1)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectionActivity>()), 1)

            let repeated = try CollectionCSV.apply(.init(entries: entries, skippedRows: 0,
                skippedCSVText: nil), to: ModelContext(container))
            XCTAssertTrue(repeated.failedRows.isEmpty)
            XCTAssertEqual(try storedQuantities(in: container), [owner.collectionKey: 1])
            XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<InventoryEvent>()), 1)
        }
    }

    func testConflictingCertifiedImportsDoNotChangeOwnerOrHistory() throws {
        for conflict in ["printing", "grade", "variant", "finish", "run", "occupied-key"] {
            let container = try makeContainer()
            let original = try certifiedEntry(marketVariant: "market-slab")
            _ = try CollectionCSV.apply(.init(entries: [original], skippedRows: 0,
                skippedCSVText: nil), to: ModelContext(container))
            var incoming = try certifiedEntry()
            switch conflict {
            case "printing": incoming.catalogProviderID = "base1-2"
            case "grade": incoming.grade = CardGrade(value: "9")
            case "variant": incoming.justTCGVariantID = "different-market-slab"
            case "finish": incoming = try certifiedEntry(finish: .reverse)
            case "run": incoming.pokemonPrintRun = .firstEdition
            default:
                incoming = try certifiedEntry(certificate: "OTHER", key: original.collectionKey)
            }
            let result = try CollectionCSV.apply(.init(entries: [incoming], skippedRows: 0,
                skippedCSVText: nil), to: ModelContext(container))
            XCTAssertEqual(result.failedRows.count, 1, conflict)
            XCTAssertEqual(try storedQuantities(in: container), [original.collectionKey: 1], conflict)
            let context = ModelContext(container)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<InventoryEvent>()), 1, conflict)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectionActivity>()), 1, conflict)
            XCTAssertEqual(try context.fetch(FetchDescriptor<CollectedCard>()).first?.justTCGVariantID,
                "market-slab", conflict)
        }
    }

    func testDifferentCertificatesAndGradersRemainSeparatePhysicalOwners() throws {
        let container = try makeContainer()
        let entries = try [certifiedEntry(), certifiedEntry(certificate: "OTHER"),
            certifiedEntry(company: .cgc)]
        let result = try CollectionCSV.apply(.init(entries: entries, skippedRows: 0,
            skippedCSVText: nil), to: ModelContext(container))
        XCTAssertTrue(result.failedRows.isEmpty)
        XCTAssertEqual(result.insertedEntries, 3)
        XCTAssertEqual(try storedQuantities(in: container).count, 3)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<InventoryEvent>()), 3)
    }

    func testCommittedTreatmentAliasSurvivesAFailedRowAndResume() throws {
        let container = try makeContainer()
        let canonical = CollectedCard(collectionKey: "magic:printing#foil#treatment=neonink", game: .magic,
            providerID: "printing", name: "Fixture", setName: "Fixture Set", setCode: "FIX", cardNumber: "1",
            rarity: nil, imageURL: nil, thumbnailURL: nil, variant: .foil, variantResolution: .userConfirmed,
            quantity: 2, magicTreatments: [.neonInk])
        let legacy = CollectedCard(collectionKey: "magic:printing#foil", game: .magic,
            providerID: "printing", name: "Fixture", setName: "Fixture Set", setCode: "FIX", cardNumber: "1",
            rarity: nil, imageURL: nil, thumbnailURL: nil, variant: .foil, variantResolution: .userConfirmed,
            quantity: 3)
        let entries = try CollectionCSV.parse(Data(CollectionCSV.export([canonical, legacy]).text.utf8)).entries
        let canonicalEntry = try XCTUnwrap(entries.first { !$0.magicTreatmentIDsRaw.isEmpty })
        let legacyEntry = try XCTUnwrap(entries.first { $0.magicTreatmentIDsRaw.isEmpty })
        var invalid = try XCTUnwrap(parsedPlan(rows: ["bad,Invalid,Set,SET,2,1"]).entries.first)
        invalid.quantity = 0
        let plan = CollectionCSVImportPlan(entries: [canonicalEntry, invalid, legacyEntry],
            skippedRows: 0, skippedCSVText: nil)

        let result = try CollectionCSV.apply(plan, to: ModelContext(container))
        XCTAssertEqual(result.insertedEntries, 1)
        XCTAssertEqual(result.mergedEntries, 1)
        XCTAssertEqual(result.failedRows.map(\.collectionKey), [invalid.collectionKey])
        XCTAssertEqual(result.importedQuantity, 5)
        XCTAssertEqual(try storedQuantities(in: container), [canonicalEntry.collectionKey: 5])

        let resumed = try CollectionCSV.apply(plan, to: ModelContext(container))
        XCTAssertEqual(resumed.alreadyImportedEntries, 2)
        XCTAssertEqual(resumed.failedRows.count, 1)
        XCTAssertEqual(try storedQuantities(in: container), [canonicalEntry.collectionKey: 5])
        let events = try ModelContext(container).fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.reduce(0) { $0 + $1.deltaQuantity }, 5)
    }

    func testNativeImportAllowsAnExtraCategoryColumn() throws {
        let csv = "provider_id,card_name,quantity,category\nbase1-4,Charizard,2,Pokemon\n"
        let plan = try CollectionCSV.parse(Data(csv.utf8))

        XCTAssertEqual(plan.entries.first?.providerID, "base1-4")
        XCTAssertEqual(plan.totalQuantity, 2)
    }

    func testDelimiterDetectionIgnoresQuotedHeaderPunctuation() throws {
        for delimiter in [",", ";", "\t"] {
            let other = delimiter == ";" ? "," : ";"
            let noteHeader = "\"notes\(String(repeating: other, count: 8))\""
            let csv = ["provider_id", "card_name", "quantity", noteHeader].joined(separator: delimiter)
                + "\n" + ["base1-4", "Charizard", "2", "note"].joined(separator: delimiter) + "\n"
            let plan = try CollectionCSV.parse(Data(csv.utf8))

            XCTAssertEqual(plan.totalQuantity, 2, "delimiter: \(delimiter)")
        }
    }

    func testUnterminatedQuotedCellRejectsTheImport() {
        let csv = "provider_id,card_name,quantity\nbase1-4,Charizard,1\nbase1-2,\"Blastoise,2\n"

        XCTAssertThrowsError(try CollectionCSV.parse(Data(csv.utf8))) { error in
            guard case CollectionCSVError.unreadableFile = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testQuotedNamesKeepEscapedQuotesAndEmbeddedNewlines() throws {
        let csv = "provider_id,card_name,quantity\nbase1-4,\"Charizard \"\"special\"\"\nprinting\",2\n"
        let plan = try CollectionCSV.parse(Data(csv.utf8))

        XCTAssertEqual(plan.entries.first?.name, "Charizard \"special\"\nprinting")
        XCTAssertEqual(plan.totalQuantity, 2)
    }

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

        // File preparation must restore the pending run before counting ledger
        // entries or offering "Import remaining" after a relaunch.
        let resumedAttempt = try parsedPlan(rows: [
            "a,Card A,Set,SET,1,2",
            "b,Card B,Set,SET,2,3"
        ]).resumingAdditionalCopyRunIfNeeded()
        XCTAssertEqual(
            try CollectionCSV.alreadyImportedEntryCount(for: resumedAttempt, in: ModelContext(container)),
            1
        )
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

    private func certifiedEntry(marketVariant: String? = nil, certificate: String = "CERT123",
                                company: GradingCompany = .psa, finish: PhysicalVariant = .holo,
                                key: String? = nil) throws -> CollectionCSVEntry {
        let identity = key ?? "graded:base1-4#\(marketVariant ?? company.rawValue + "|10"):\(certificate)"
        let card = CollectedCard(collectionKey: identity, game: .pokemon, providerID: "base1-4",
            name: "Charizard", setName: "Base Set", setCode: "BS", cardNumber: "4", rarity: nil,
            imageURL: nil, thumbnailURL: nil, variant: finish, variantResolution: .imported,
            quantity: 1, dateAdded: Date(timeIntervalSince1970: 1_700_000_000))
        card.itemKindRaw = CollectionItemKind.gradedCard.rawValue
        card.catalogProviderID = "base1-4"
        card.gradingCompanyRaw = company.rawValue
        card.gradeRaw = "10"
        card.certificationNumber = certificate
        card.justTCGVariantID = marketVariant
        if marketVariant != nil {
            card.justTCGCardID = "market-card"
            card.justTCGAPIVersion = JustTCGV2GradedClient.apiVersion
        }
        return try XCTUnwrap(CollectionCSV.parse(Data(CollectionCSV.export([card]).text.utf8)).entries.first)
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
