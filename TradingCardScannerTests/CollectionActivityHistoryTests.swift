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
        let first = makeCollectedCard(quantity: 2)
        let second = makeCollectedCard(quantity: 1)
        second.collectionKey = "sv08.5-075#normal"
        second.providerID = "sv08.5-075"
        second.name = "Pikachu"
        context.insert(first)
        context.insert(second)
        try context.save()

        try store.deleteAll()

        XCTAssertTrue(try context.fetch(FetchDescriptor<CollectedCard>()).isEmpty)
        let activities = try context.fetch(FetchDescriptor<CollectionActivity>())
        XCTAssertEqual(activities.filter { $0.kind == .removed }.count, 2)
        XCTAssertEqual(activities.reduce(0) { $0 + $1.signedQuantity }, -3)
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

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            CollectedCard.self,
            PriceRecord.self,
            CollectionActivity.self,
            InventoryEvent.self
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
}
