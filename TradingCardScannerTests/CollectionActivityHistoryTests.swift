import SwiftData
import XCTest
@testable import TradingCardScanner

@MainActor
final class CollectionActivityHistoryTests: XCTestCase {
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    func testAddRemoveRestoreKeepsCollectionLedgerAndHistoryInAgreement() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let card = try identifiedCard()

        _ = try store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )
        let stored = try XCTUnwrap(store.card(forKey: card.collectionKey(variant: .normal)))
        let snapshot = try store.remove(stored)
        try store.restore(snapshot)

        let restored = try XCTUnwrap(store.card(forKey: snapshot.collectionKey))
        XCTAssertEqual(restored.quantity, snapshot.quantity)

        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertEqual(activities.count, 3)
        XCTAssertEqual(activities.filter { $0.kind == .added }.count, 1)
        XCTAssertEqual(activities.filter { $0.kind == .removed }.count, 1)
        XCTAssertEqual(activities.filter { $0.kind == .restored }.count, 1)

        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(
            InventoryLedger.quantities(from: events),
            [snapshot.collectionKey: snapshot.quantity]
        )
        XCTAssertTrue(CollectionActivity.integrityDefects(activities: activities, events: events).isEmpty)
    }

    func testLegacyAliasCacheIsSharedAndInvalidatedAfterCollectionMutation() throws {
        let context = try makeContext()
        let legacyStore = CollectionStore(context: context)
        let mutationStore = CollectionStore(context: context)
        let card = try magicIdentifiedCard()
        let canonicalKey = card.collectionKey(variant: .foil)
        let legacyKey = try XCTUnwrap(
            MagicTreatmentKeyCodec.legacyCollectionKeys(for: canonicalKey).first
        )

        XCTAssertNil(try legacyStore.card(forAnyKey: legacyKey))

        _ = try mutationStore.add(
            card,
            resolved: ResolvedVariant(variant: .foil, resolution: .userConfirmed),
            source: .scan
        )

        let resolved = try XCTUnwrap(try legacyStore.card(forAnyKey: legacyKey))
        XCTAssertEqual(resolved.collectionKey, canonicalKey)
        XCTAssertEqual(resolved.quantity, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectedCard>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectionActivity>()).count, 1)
    }

    func testUndoLeavesOriginalActivityAndAppendsAnUndoneEntry() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let mutation = try store.add(
            identifiedCard(),
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )

        try store.undo(mutation)

        XCTAssertNil(store.card(forKey: mutation.collectionKey))
        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertEqual(activities.count, 2)
        XCTAssertEqual(activities.filter { $0.kind == .added }.count, 1)
        XCTAssertEqual(activities.filter { $0.kind == .undone }.count, 1)
        XCTAssertEqual(
            activities.first { $0.id == mutation.activityID }?.resolvedQuantity,
            1
        )

        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertTrue(InventoryLedger.quantities(from: events).isEmpty)
        XCTAssertTrue(CollectionActivity.integrityDefects(activities: activities, events: events).isEmpty)
    }

    func testCorrectingOneEntryLeavesSiblingEntriesUntouched() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let card = try identifiedCard()
        let normalKey = card.collectionKey(variant: .normal)
        var mutations: [CollectionMutation] = []

        for _ in 0..<3 {
            mutations.append(
                try store.add(
                    card,
                    resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
                    source: .scan
                )
            )
        }

        let targetID = try XCTUnwrap(mutations[1].activityID)
        let target = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CollectionActivity>()).first { $0.id == targetID }
        )
        let normalRow = try XCTUnwrap(store.card(forKey: normalKey))
        let correction = try XCTUnwrap(
            try store.recordVariantCorrection(
                for: normalRow,
                to: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
                activityID: target.id,
                quantity: 1
            )
        )

        let correctedKey = correction.collectionKey
        XCTAssertEqual(store.card(forKey: normalKey)?.quantity, 2)
        XCTAssertEqual(store.card(forKey: correctedKey)?.quantity, 1)

        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertEqual(activities.count, 4)
        let siblingKeys = activities
            .filter { $0.kind == .added && $0.id != target.id }
            .map(\.collectionKey)
        XCTAssertEqual(siblingKeys.count, 2)
        XCTAssertEqual(Set(siblingKeys), Set([normalKey]))
        XCTAssertEqual(target.collectionKey, correctedKey)
        XCTAssertEqual(activities.filter { $0.kind == .corrected }.count, 1)

        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(
            InventoryLedger.quantities(from: events),
            [normalKey: 2, correctedKey: 1]
        )
        XCTAssertTrue(CollectionActivity.integrityDefects(activities: activities, events: events).isEmpty)
    }

    func testRepeatingCorrectionTapDoesNotAppendAnotherMutation() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let card = try identifiedCard()
        let mutation = try store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )
        let activityID = try XCTUnwrap(mutation.activityID)
        let normalRow = try XCTUnwrap(store.card(forKey: mutation.collectionKey))
        let corrected = try XCTUnwrap(
            try store.recordVariantCorrection(
                for: normalRow,
                to: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
                activityID: activityID,
                quantity: 1
            )
        )
        let activityCount = try context.fetch(FetchDescriptor<CollectionActivity>()).count
        let eventCount = try context.fetch(FetchDescriptor<InventoryEvent>()).count
        let reverseRow = try XCTUnwrap(store.card(forKey: corrected.collectionKey))

        let repeated = try store.recordVariantCorrection(
            for: reverseRow,
            to: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
            activityID: activityID,
            quantity: 1
        )
        XCTAssertNil(repeated)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectionActivity>()).count, activityCount)
        XCTAssertEqual(try context.fetch(FetchDescriptor<InventoryEvent>()).count, eventCount)
    }

    func testDeleteAllRecordsOneRemovalEntryPerPosition() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let card = try identifiedCard()

        // Seeded through the store rather than inserted directly: a position
        // with no acquisition behind it leaves the ledger permanently negative
        // once it is disposed of, which is a broken fixture rather than
        // anything `deleteAll` did.
        for _ in 0..<2 {
            _ = try store.add(
                card,
                resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
                source: .scan
            )
        }
        _ = try store.add(
            card,
            resolved: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
            source: .scan
        )

        try store.deleteAll()

        XCTAssertTrue(try context.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertEqual(activities.filter { $0.kind == .removed }.count, 2)
        XCTAssertEqual(
            activities.filter { $0.kind == .removed }.reduce(0) { $0 + $1.signedQuantity },
            -3
        )
        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(InventoryLedger.quantities(from: events), [:])
        XCTAssertTrue(CollectionActivity.integrityDefects(activities: activities, events: events).isEmpty)
    }

    func testRestoreIsBlockedAfterThePositionIsReacquired() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let card = try identifiedCard()
        _ = try store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )
        let original = try XCTUnwrap(store.card(forKey: card.collectionKey(variant: .normal)))
        let snapshot = try store.remove(original)
        _ = try store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )
        let removal = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CollectionActivity>()).first { $0.kind == .removed }
        )

        XCTAssertThrowsError(try store.restore(removal))
        XCTAssertEqual(store.card(forKey: snapshot.collectionKey)?.quantity, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectionActivity>()).count, 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<InventoryEvent>()).count, 3)
    }

    func testRestoreMergesBackIntoSurvivingSiblingCopies() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let card = try identifiedCard()
        let first = try store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )
        _ = try store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )
        let firstActivityID = try XCTUnwrap(first.activityID)
        let firstActivity = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CollectionActivity>()).first { $0.id == firstActivityID }
        )

        _ = try store.remove(firstActivity)
        let removal = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CollectionActivity>()).first { $0.kind == .removed }
        )
        try store.restore(removal)

        XCTAssertEqual(store.card(forKey: first.collectionKey)?.quantity, 2)
        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertEqual(activities.filter { $0.kind == .restored }.count, 1)
        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(InventoryLedger.quantities(from: events)[first.collectionKey], 2)
        XCTAssertTrue(CollectionActivity.integrityDefects(activities: activities, events: events).isEmpty)
    }

    func testRestoreIsBlockedOutsideTheRecentRemovalWindow() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let card = try identifiedCard()
        _ = try store.add(
            card,
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )
        let stored = try XCTUnwrap(store.card(forKey: card.collectionKey(variant: .normal)))
        _ = try store.remove(stored)
        let removal = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CollectionActivity>()).first { $0.kind == .removed }
        )
        removal.occurredAt = Date(timeIntervalSinceNow: -CollectionActivity.restoreWindow - 1)
        try context.save()

        XCTAssertThrowsError(try store.restore(removal))
        XCTAssertNil(store.card(forKey: removal.collectionKey))
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectionActivity>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<InventoryEvent>()).count, 2)
    }

    func testRepeatedUndoAndRemovalActionsDoNotAppendSecondMutations() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let mutation = try store.add(
            identifiedCard(),
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )
        try store.undo(mutation)
        XCTAssertThrowsError(try store.undo(mutation))
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectionActivity>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<InventoryEvent>()).count, 2)

        let secondMutation = try store.add(
            identifiedCard(),
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )
        _ = try XCTUnwrap(store.card(forKey: secondMutation.collectionKey))
        let source = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CollectionActivity>()).first { $0.id == secondMutation.activityID }
        )
        let snapshot = try store.remove(source)
        XCTAssertThrowsError(try store.remove(source))
        let removal = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CollectionActivity>()).first { $0.kind == .removed && $0.removalSnapshotData != nil }
        )
        try store.restore(removal)
        XCTAssertThrowsError(try store.restore(removal))
        XCTAssertEqual(store.card(forKey: snapshot.collectionKey)?.quantity, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectionActivity>()).count, 5)
        XCTAssertEqual(try context.fetch(FetchDescriptor<InventoryEvent>()).count, 5)
    }

    func testQuantityAdjustmentsAlsoAppearInTheActivityProjection() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let mutation = try store.add(
            identifiedCard(),
            resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
            source: .scan
        )
        let row = try XCTUnwrap(store.card(forKey: mutation.collectionKey))

        try store.setQuantity(3, for: row)

        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertEqual(activities.filter { $0.kind == .quantityAdjusted }.count, 1)
        XCTAssertEqual(activities.reduce(0) { $0 + $1.signedQuantity }, 3)
        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(InventoryLedger.quantities(from: events)[mutation.collectionKey], 3)
        XCTAssertTrue(CollectionActivity.integrityDefects(activities: activities, events: events).isEmpty)
    }

    func testExistingActivityRowsBackfillToAddedWithTheirLegacyQuantity() throws {
        let context = try makeContext()
        let card = makeCollectedCard(quantity: 4)
        context.insert(card)
        let activity = CollectionActivity(card: card, source: .scan, quantity: 4)
        activity.kindRaw = ""
        activity.deltaQuantity = 0
        context.insert(activity)
        try context.save()

        try CollectionStore(context: context).backfillExistingCollectionIfNeeded()

        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<CollectionActivity>()).first)
        XCTAssertEqual(stored.kind, .added)
        XCTAssertEqual(stored.signedQuantity, 4)
        XCTAssertEqual(stored.deltaQuantity, 4)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectionActivity>()).count, 1)
    }

    func testActivityProjectionMismatchIsDiagnosticOnly() throws {
        let context = try makeContext()
        let card = makeCollectedCard(quantity: 1)
        context.insert(card)
        let ledger = InventoryLedger(context: context)
        _ = ledger.record(
            card,
            kind: .acquire,
            source: .scan,
            deltaQuantity: 1,
            operationID: UUID()
        )
        let activity = CollectionActivity(card: card, source: .scan, quantity: 2)
        context.insert(activity)
        try context.save()

        let defects = CollectionActivity.integrityDefects(
            activities: [activity],
            events: try ledger.allEventsThrowing()
        )
        XCTAssertEqual(defects.count, 1)
        XCTAssertFalse(defects[0].canRepairQuantity)
    }

    func testMagicTreatmentIdentityFollowsActivityAndRemovalSnapshot() throws {
        let card = CollectedCard(
            collectionKey: "magic:printing#foil#treatment=surgefoil",
            game: .magic,
            providerID: "printing",
            name: "Fixture",
            setName: "Fixture Set",
            setCode: "FIC",
            cardNumber: "10",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .foil,
            variantResolution: .userConfirmed,
            magicTreatments: [.surgeFoil]
        )
        let activity = CollectionActivity(card: card, source: .scan)
        let snapshot = RemovedCardSnapshot(card: card)
        let restored = try JSONDecoder().decode(
            RemovedCardSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        XCTAssertEqual(activity.magicTreatmentIDsRaw, ["surgefoil"])
        XCTAssertEqual(snapshot.magicTreatmentIDsRaw, ["surgefoil"])
        XCTAssertEqual(restored.magicTreatmentIDsRaw, ["surgefoil"])
        XCTAssertEqual(restored.collectionKey, card.collectionKey)
    }

    func testAddingTreatedPrintingRekeysLegacyCollectionHistoryWithoutDuplicate() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let card = try magicIdentifiedCard()
        let canonicalKey = card.collectionKey(variant: .foil)
        let legacyKey = "magic:\(card.providerID)#foil"
        XCTAssertEqual(
            canonicalKey,
            "magic:\(card.providerID)#foil#treatment=surgefoil"
        )

        let legacyRow = CollectedCard(
            collectionKey: legacyKey,
            game: .magic,
            providerID: card.providerID,
            name: card.name,
            setName: card.setName,
            setCode: card.setCode,
            cardNumber: card.cardNumber,
            rarity: card.rarity,
            imageURL: card.displayImageURL?.absoluteString,
            thumbnailURL: card.thumbnailImageURL?.absoluteString,
            variant: .foil,
            variantResolution: .userConfirmed,
            quantity: 1
        )
        context.insert(legacyRow)

        let acquisitionOperationID = UUID()
        let ledger = InventoryLedger(context: context)
        guard case .appended = ledger.record(
            legacyRow,
            kind: .acquire,
            source: .scan,
            deltaQuantity: 1,
            operationID: acquisitionOperationID
        ) else {
            return XCTFail("Expected the legacy acquisition event to be appended")
        }
        context.insert(
            CollectionActivity(
                card: legacyRow,
                source: .scan,
                quantity: 1,
                ledgerOperationIDs: [acquisitionOperationID]
            )
        )

        let disposalOperationID = UUID()
        guard case .appended = ledger.record(
            legacyRow,
            kind: .dispose,
            source: .correction,
            deltaQuantity: -1,
            operationID: disposalOperationID
        ) else {
            return XCTFail("Expected the legacy disposal event to be appended")
        }
        var snapshot = RemovedCardSnapshot(card: legacyRow)
        snapshot.operationID = disposalOperationID
        context.insert(
            CollectionActivity(
                card: legacyRow,
                source: .correction,
                quantity: 1,
                kind: .removed,
                deltaQuantity: -1,
                ledgerOperationIDs: [disposalOperationID],
                removalSnapshotData: try JSONEncoder().encode(snapshot)
            )
        )
        try context.save()

        let mutation = try store.add(
            card,
            resolved: ResolvedVariant(variant: .foil, resolution: .userConfirmed),
            source: .scan
        )

        XCTAssertFalse(mutation.didInsert)
        XCTAssertEqual(mutation.collectionKey, canonicalKey)
        let cards = try context.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(cards.count, 1)
        let stored = try XCTUnwrap(cards.first)
        XCTAssertEqual(stored.collectionKey, canonicalKey)
        XCTAssertEqual(stored.quantity, 2)
        XCTAssertEqual(stored.magicTreatmentIDsRaw, ["surgefoil"])

        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertEqual(activities.count, 3)
        XCTAssertTrue(activities.allSatisfy { $0.collectionKey == canonicalKey })
        let rewrittenSnapshotData = try XCTUnwrap(
            activities.first(where: { $0.kind == .removed })?.removalSnapshotData
        )
        let rewrittenSnapshot = try JSONDecoder().decode(
            RemovedCardSnapshot.self,
            from: rewrittenSnapshotData
        )
        XCTAssertEqual(rewrittenSnapshot.collectionKey, canonicalKey)
        XCTAssertEqual(rewrittenSnapshot.magicTreatmentIDsRaw, ["surgefoil"])

        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(events.count, 3)
        XCTAssertTrue(events.allSatisfy { $0.collectionKey == canonicalKey })
        let genericPriceKey = PriceRecord.key(
            game: .magic,
            printingID: card.providerID,
            variantID: PhysicalVariant.foil.id
        )
        let treatedPriceKey = PriceRecord.key(
            game: .magic,
            printingID: card.providerID,
            variantID: PhysicalVariant.foil.id,
            treatmentIDs: ["surgefoil"]
        )
        XCTAssertEqual(Set(events.map(\.priceStorageKey)), [genericPriceKey, treatedPriceKey])
        XCTAssertTrue(CollectionActivity.integrityDefects(activities: activities, events: events).isEmpty)
    }

    func testCollectionReadThroughMergesCanonicalAndLegacyCollision() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let providerID = "collision-printing"
        let legacyKey = "magic:\(providerID)#foil"
        let canonicalKey = "magic:\(providerID)#foil#treatment=surgefoil"

        func row(key: String) -> CollectedCard {
            CollectedCard(
                collectionKey: key,
                game: .magic,
                providerID: providerID,
                name: "Fixture",
                setName: "Fixture Set",
                setCode: "FIC",
                cardNumber: "10",
                rarity: nil,
                imageURL: nil,
                thumbnailURL: nil,
                variant: .foil,
                variantResolution: .userConfirmed
            )
        }

        context.insert(row(key: legacyKey))
        context.insert(row(key: canonicalKey))
        try context.save()

        let resolved = try XCTUnwrap(
            try store.card(
                forAnyKey: canonicalKey,
                magicTreatmentIDsRaw: ["surgefoil"]
            )
        )
        XCTAssertEqual(resolved.collectionKey, canonicalKey)
        XCTAssertEqual(resolved.quantity, 2)
        XCTAssertEqual(resolved.magicTreatmentIDsRaw, ["surgefoil"])
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CollectedCard>()).map(\.collectionKey).sorted(),
            [canonicalKey]
        )
    }

    func testLegacyRowRepairsToARekeyedCanonicalLedgerBeforeWriting() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let card = try magicIdentifiedCard()
        let legacyKey = "magic:\(card.providerID)#foil"
        let canonicalKey = card.collectionKey(variant: .foil)
        let legacyRow = CollectedCard(
            collectionKey: legacyKey,
            game: .magic,
            providerID: card.providerID,
            name: card.name,
            setName: card.setName,
            setCode: card.setCode,
            cardNumber: card.cardNumber,
            rarity: card.rarity,
            imageURL: card.displayImageURL?.absoluteString,
            thumbnailURL: card.thumbnailImageURL?.absoluteString,
            variant: .foil,
            variantResolution: .userConfirmed,
            quantity: 1
        )
        context.insert(legacyRow)
        let operationID = UUID()
        guard case .appended = InventoryLedger(context: context).record(
            legacyRow,
            kind: .acquire,
            source: .scan,
            deltaQuantity: 1,
            operationID: operationID
        ) else {
            return XCTFail("Expected the legacy acquisition event to be appended")
        }
        context.insert(
            CollectionActivity(
                card: legacyRow,
                source: .scan,
                quantity: 1,
                ledgerOperationIDs: [operationID]
            )
        )
        try context.save()

        let event = try XCTUnwrap(
            try context.fetch(FetchDescriptor<InventoryEvent>()).first
        )
        event.collectionKey = canonicalKey
        try context.save()

        let staleRow = try XCTUnwrap(store.card(forKey: legacyKey))
        try store.setQuantity(2, for: staleRow)

        let rows = try context.fetch(FetchDescriptor<CollectedCard>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.collectionKey, canonicalKey)
        XCTAssertEqual(rows.first?.quantity, 2)

        let events = try context.fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertEqual(Set(events.map(\.collectionKey)), [canonicalKey])
        XCTAssertEqual(InventoryLedger.quantities(from: events), [canonicalKey: 2])
        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertTrue(activities.allSatisfy { $0.collectionKey == canonicalKey })
        XCTAssertTrue(CollectionActivity.integrityDefects(activities: activities, events: events).isEmpty)

        // The point of adopting the canonical key: ledger and collection agree
        // on one identity, so the position reconciles instead of reporting a
        // quantity mismatch against both keys and pausing portfolio history.
        XCTAssertTrue(
            PortfolioEngine.reconcile(
                projection: LogicalCollection.project(
                    cards: rows,
                    ledger: InventoryLedger(context: context)
                ),
                events: events.map { PortfolioEngine.entry(from: $0) }
            ).isEmpty
        )
    }

    func testLegacyLookupFindsCanonicalRowWhenLegacyRowIsAbsent() throws {
        let context = try makeContext()
        let store = CollectionStore(context: context)
        let card = try magicIdentifiedCard()
        let legacyKey = "magic:\(card.providerID)#foil"
        let canonicalKey = card.collectionKey(variant: .foil)
        let canonicalRow = CollectedCard(
            collectionKey: canonicalKey,
            game: .magic,
            providerID: card.providerID,
            name: card.name,
            setName: card.setName,
            setCode: card.setCode,
            cardNumber: card.cardNumber,
            rarity: card.rarity,
            imageURL: card.displayImageURL?.absoluteString,
            thumbnailURL: card.thumbnailImageURL?.absoluteString,
            variant: .foil,
            variantResolution: .userConfirmed,
            quantity: 2,
            magicTreatments: [.surgeFoil]
        )
        context.insert(canonicalRow)

        let operationID = UUID()
        guard case .appended = InventoryLedger(context: context).record(
            canonicalRow,
            kind: .acquire,
            source: .scan,
            deltaQuantity: 2,
            operationID: operationID
        ) else {
            return XCTFail("Expected the canonical acquisition event to be appended")
        }
        try context.save()

        // This is the mixed-version direction the old gate missed: the newer
        // canonical row and ledger are local, while the caller still presents
        // the treatment-free key.
        let resolved = try XCTUnwrap(try store.card(forAnyKey: legacyKey))
        XCTAssertEqual(resolved.collectionKey, canonicalKey)
        XCTAssertEqual(resolved.quantity, 2)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CollectedCard>()).map(\.collectionKey),
            [canonicalKey]
        )
        XCTAssertEqual(
            Set(try context.fetch(FetchDescriptor<InventoryEvent>()).map(\.collectionKey)),
            [canonicalKey]
        )
    }

    func testDuplicatePhysicalRowsAreMergedBeforeEveryOwnershipMutation() throws {
        func seed(
            in context: ModelContext,
            quantities: [Int]
        ) throws -> (
            key: String,
            rows: [CollectedCard],
            activities: [CollectionActivity],
            operationIDs: [UUID]
        ) {
            let key = "sv08.5-074#normal"
            let ledger = InventoryLedger(context: context)
            var rows: [CollectedCard] = []
            var activities: [CollectionActivity] = []
            var operationIDs: [UUID] = []

            for (index, quantity) in quantities.enumerated() {
                let row = makeCollectedCard(quantity: quantity)
                row.dateAdded = Date(timeIntervalSince1970: Double(index + 1))
                context.insert(row)
                let operationID = UUID()
                guard case .appended = ledger.record(
                    row,
                    kind: .acquire,
                    source: .scan,
                    deltaQuantity: quantity,
                    operationID: operationID,
                    occurredAt: row.dateAdded
                ) else {
                    throw CollectionStoreError.ledgerConflict("fixture event was not appended")
                }
                let activity = CollectionActivity(
                    card: row,
                    source: .scan,
                    quantity: quantity,
                    occurredAt: row.dateAdded,
                    kind: .added,
                    deltaQuantity: quantity,
                    ledgerOperationIDs: [operationID]
                )
                context.insert(activity)
                rows.append(row)
                activities.append(activity)
                operationIDs.append(operationID)
            }
            try context.save()
            return (key, rows, activities, operationIDs)
        }

        func assertLogicalPosition(
            in context: ModelContext,
            key: String,
            quantity: Int,
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            let rows = try context.fetch(FetchDescriptor<CollectedCard>())
            let projection = LogicalCollection.project(
                cards: rows,
                ledger: InventoryLedger(context: context)
            )
            XCTAssertEqual(rows.count, 1, file: file, line: line)
            XCTAssertEqual(projection.positions.count, 1, file: file, line: line)
            XCTAssertEqual(projection.byKey[key]?.quantity, quantity, file: file, line: line)
            let events = try context.fetch(FetchDescriptor<InventoryEvent>())
            XCTAssertEqual(
                InventoryLedger.quantities(from: events),
                [key: quantity],
                file: file,
                line: line
            )
        }

        do {
            let context = try makeContext()
            let seeded = try seed(in: context, quantities: [1, 2])
            let mutation = try CollectionStore(context: context).add(
                identifiedCard(),
                resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
                source: .scan
            )
            XCTAssertFalse(mutation.didInsert)
            try assertLogicalPosition(in: context, key: seeded.key, quantity: 4)
        }

        do {
            let context = try makeContext()
            let seeded = try seed(in: context, quantities: [1, 2])
            let store = CollectionStore(context: context)
            let representative = try XCTUnwrap(store.card(forKey: seeded.key))
            try store.setQuantity(7, for: representative)
            try assertLogicalPosition(in: context, key: seeded.key, quantity: 7)
        }

        do {
            let context = try makeContext()
            let seeded = try seed(in: context, quantities: [1, 2])
            let representative = try XCTUnwrap(
                CollectionStore(context: context).card(forKey: seeded.key)
            )
            _ = try CollectionStore(context: context).remove(representative)
            XCTAssertTrue(try context.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
            XCTAssertTrue(
                InventoryLedger.quantities(
                    from: try context.fetch(FetchDescriptor<InventoryEvent>())
                ).isEmpty
            )
        }

        do {
            let context = try makeContext()
            let seeded = try seed(in: context, quantities: [1, 2])
            let mutation = CollectionMutation(
                collectionKey: seeded.key,
                activityID: seeded.activities[0].id,
                didInsert: false,
                ledgerOperationIDs: [seeded.operationIDs[0]]
            )
            try CollectionStore(context: context).undo(mutation)
            try assertLogicalPosition(in: context, key: seeded.key, quantity: 2)
        }

        do {
            let context = try makeContext()
            let seeded = try seed(in: context, quantities: [1, 2])
            let removedRow = seeded.rows[0]
            removedRow.quantity = 0
            seeded.activities[0].resolvedQuantity = 1
            let removalOperationID = UUID()
            guard case .appended = InventoryLedger(context: context).record(
                removedRow,
                kind: .dispose,
                source: .correction,
                deltaQuantity: -1,
                operationID: removalOperationID
            ) else {
                throw CollectionStoreError.ledgerConflict("fixture removal was not appended")
            }
            var snapshot = RemovedCardSnapshot(card: removedRow, quantity: 1)
            snapshot.operationID = removalOperationID
            let removal = CollectionActivity(
                card: removedRow,
                source: .correction,
                quantity: 1,
                kind: .removed,
                deltaQuantity: -1,
                ledgerOperationIDs: [removalOperationID],
                removalSnapshotData: try JSONEncoder().encode(snapshot)
            )
            context.insert(removal)
            try context.save()

            try CollectionStore(context: context).restore(removal)
            try assertLogicalPosition(in: context, key: seeded.key, quantity: 3)
        }
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            CollectedCard.self,
            PriceRecord.self,
            CollectionActivity.self,
            InventoryEvent.self,
            PriceObservation.self,
            PriceCheckDay.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container.mainContext
    }

    private func makeCollectedCard(quantity: Int = 1) -> CollectedCard {
        CollectedCard(
            collectionKey: "sv08.5-074#normal",
            game: .pokemon,
            providerID: "sv08.5-074",
            name: "Eevee",
            setName: "Prismatic Evolutions",
            setCode: "PRE",
            cardNumber: "074",
            rarity: "Common",
            imageURL: nil,
            thumbnailURL: nil,
            variant: .normal,
            variantResolution: .userConfirmed,
            quantity: quantity
        )
    }

    private func identifiedCard() throws -> IdentifiedCard {
        let json = #"""
        {
          "id": "sv08.5-074", "localId": "074", "name": "Eevee",
          "image": "https://assets.tcgdex.net/en/sv/sv08.5/074", "rarity": "Common",
          "set": { "id": "sv08.5", "name": "Prismatic Evolutions", "cardCount": { "total": 180, "official": 131 } },
          "variants": { "firstEdition": false, "holo": false, "normal": true, "reverse": true }
        }
        """#
        let pokemon = try JSONDecoder().decode(TCGdexCard.self, from: Data(json.utf8))
        return .pokemon(pokemon, setCode: "PRE")
    }

    private func magicIdentifiedCard() throws -> IdentifiedCard {
        let json = #"""
        {
          "id": "cb82d614-13d8-40ec-9213-8e6852d37c9c",
          "name": "Fixture",
          "set": "fic",
          "set_name": "Fixture Set",
          "collector_number": "10",
          "lang": "en",
          "digital": false,
          "layout": "normal",
          "finishes": ["foil"],
          "promo_types": ["surgefoil"]
        }
        """#
        let card = try JSONDecoder().decode(
            ScryfallCard.self,
            from: Data(json.utf8)
        )
        return .magic(card)
    }
}
